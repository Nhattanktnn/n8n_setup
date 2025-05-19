#!/bin/bash
set -e
export DOCKER_BUILDKIT=1

ROOT_DIR=~/n8n-docker
read -p "Nhập tên Tunnel Cloudflare cần tạo/đồng bộ: " CLOUDFLARE_TUNNEL_NAME

# Cập nhật package list
sudo apt-get update -qq

# Kiểm tra và cài đặt dependencies
echo "🔎 Kiểm tra dependencies..."
command -v jq >/dev/null 2>&1 || sudo apt-get install -y jq
command -v docker >/dev/null 2>&1 || sudo apt-get install -y docker.io
command -v docker-compose >/dev/null 2>&1 || {
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
}

# Khởi động Docker nếu chưa chạy
sudo systemctl start docker || true
sudo systemctl enable docker

# Thêm user vào nhóm docker (nếu chưa)
groups $USER | grep -q '\bdocker\b' || sudo usermod -aG docker $USER

# Tạo thư mục dự án
mkdir -p $ROOT_DIR/cloudflared
cd $ROOT_DIR

# Nhập domain và validate
read -p "🌐 Nhập domain (VD: sub.domain.com hoặc domain.com): " DOMAIN_INPUT
DOMAIN=$(echo "$DOMAIN_INPUT" | sed -E 's~^https?://~~;s/\/$//')
if ! echo "$DOMAIN" | grep -qP '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)'; then
    echo "❌ Domain không hợp lệ!"
    exit 1
fi

# Nhập Cloudflare API Token
echo "🔑 API Token cần quyền: Zone.Zone, Zone.DNS, Tunnel:Edit"
read -sp "Nhập API Token Cloudflare: " CF_API_TOKEN
echo

# Kiểm tra và xử lý Cloudflared
if ! command -v cloudflared &>/dev/null; then
    echo "🔧 Cài đặt cloudflared..."
    sudo wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
        -O /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb
fi

# Đăng nhập Cloudflare nếu chưa
if [ ! -f ~/.cloudflared/cert.pem ]; then
    echo "🔐 Đăng nhập Cloudflare..."
    cloudflared tunnel login
fi

# Xử lý Tunnel
TUNNEL_EXISTS=$(cloudflared tunnel list | grep -c "$CLOUDFLARE_TUNNEL_NAME" || true)
if [ "$TUNNEL_EXISTS" -eq 0 ]; then
    echo "🆕 Tạo tunnel mới: $CLOUDFLARE_TUNNEL_NAME..."
    cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME"
else
    echo "🔍 Phát hiện tunnel đã tồn tại: $CLOUDFLARE_TUNNEL_NAME"
fi

# Lấy Tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep "$CLOUDFLARE_TUNNEL_NAME" | awk '{print $1}' | head -n 1)
[ -z "$TUNNEL_ID" ] && { echo "❌ Không tìm thấy Tunnel ID"; exit 1; }
echo "✅ Tunnel ID: $TUNNEL_ID"

# Xử lý credentials file
CRED_FILE="$ROOT_DIR/cloudflared/${TUNNEL_ID}.json"
[ ! -f "$CRED_FILE" ] && cp ~/.cloudflared/${TUNNEL_ID}.json "$CRED_FILE"

# Tạo/Ghi đè file .env
cat <<EOL > .env
N8N_HOST=$DOMAIN
WEBHOOK_URL=https://$DOMAIN
N8N_EDITOR_BASE_URL=https://$DOMAIN
CLOUDFLARED_TUNNEL_TOKEN=$(cloudflared tunnel token "$CLOUDFLARE_TUNNEL_NAME")
# Các biến môi trường khác cho n8n...
EOL

# Docker Compose configuration
cat <<EOL > docker-compose.yml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    env_file: .env
    networks:
      - cf_network

  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=\${CLOUDFLARED_TUNNEL_TOKEN}
    volumes:
      - ./cloudflared:/etc/cloudflared
    networks:
      - cf_network

networks:
  cf_network:
    driver: bridge
EOL

# Xử lý config.yml
CONFIG_FILE="cloudflared/config.yml"
if [ -f "$CONFIG_FILE" ]; then
    echo "🔄 Cập nhật config.yml hiện có..."
    grep -q "hostname: $DOMAIN" "$CONFIG_FILE" && {
        echo "✅ Domain đã tồn tại trong config.yml"
    } || {
        sed -i '/^ingress:/a \
  - hostname: '"$DOMAIN"'\
    service: http://n8n:5678' "$CONFIG_FILE"
        echo "✅ Đã thêm domain vào config.yml"
    }
else
    echo "🆕 Tạo config.yml mới..."
    cat <<EOL > "$CONFIG_FILE"
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json
ingress:
  - hostname: $DOMAIN
    service: http://n8n:5678
  - service: http_status:404
EOL
fi

# Xử lý DNS Records
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN#*.}" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ "$ZONE_ID" != "null" ]; then
    echo "🔗 Xử lý bản ghi DNS cho $DOMAIN..."
    DNS_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN" \
        -H "Authorization: Bearer $CF_API_TOKEN")
    
    if [ $(echo "$DNS_RECORD" | jq '.result | length') -eq 0 ]; then
        echo "🆕 Tạo bản ghi CNAME..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data '{
                "type":"CNAME",
                "name":"'"$DOMAIN"'",
                "content":"'"${TUNNEL_ID}.cfargotunnel.com"'",
                "ttl":120,
                "proxied":true
            }' | jq
    else
        echo "✅ Bản ghi DNS đã tồn tại"
    fi
else
    echo "⚠️ Không tìm thấy Zone ID, bỏ qua tạo DNS Record"
fi

# Khởi động hệ thống
echo "🚀 Khởi động containers..."
docker-compose down
docker-compose up -d --force-recreate

echo "✨ Cài đặt hoàn tất! Truy cập https://$DOMAIN sau vài phút"
