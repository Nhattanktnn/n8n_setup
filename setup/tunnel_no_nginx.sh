#!/bin/bash
set -e
export DOCKER_BUILDKIT=1

ROOT_DIR=~/n8n-docker
read -p "Nhập tên Tunnel Cloudflare cần tạo/đồng bộ: " CLOUDFLARE_TUNNEL_NAME

# Cập nhật package list
sudo apt-get update -qq

# Kiểm tra và cài đặt dependencies
echo "🔎 Kiểm tra dependencies..."
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq chưa cài. Đang cài đặt..."
    sudo apt-get install -y jq || { echo "❌ Cài jq thất bại"; exit 1; }
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker chưa cài. Đang cài đặt..."
    sudo apt-get install -y docker.io || { echo "❌ Cài Docker thất bại"; exit 1; }
fi

# Đảm bảo Docker daemon hoạt động
if ! sudo systemctl is-active --quiet docker; then
    echo "❌ Docker daemon không hoạt động. Đang khởi động..."
    sudo systemctl start docker || { echo "❌ Không thể khởi động Docker"; exit 1; }
fi
sudo systemctl enable docker

# Thêm user vào nhóm docker (nếu chưa)
if ! groups $USER | grep -q '\bdocker\b'; then
    echo "➕ Thêm user '$USER' vào nhóm docker..."
    sudo usermod -aG docker $USER
    echo "⚠️ Bạn cần đăng xuất đăng nhập lại HOẶC chạy: newgrp docker"
fi

# Docker Compose
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ Docker Compose chưa cài. Đang cài đặt..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "❌ Tải Docker Compose thất bại"; exit 1; }
    sudo chmod +x /usr/local/bin/docker-compose || { echo "❌ Cài Docker Compose thất bại"; exit 1; }
fi

# Tạo thư mục dự án
echo "🚀 Đang tạo thư mục dự án tại $ROOT_DIR..."
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
read -p "Nhập API Token Cloudflare: " CF_API_TOKEN
echo

# Kiểm tra và xử lý Cloudflared
echo "🔧 Kiểm tra cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    echo "⚠️ Cloudflared chưa cài đặt. Đang cài đặt..."
    sudo wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
        -O /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb || { echo "❌ Cài đặt cloudflared thất bại"; exit 1; }
fi

# Đăng nhập Cloudflare
CERT_FILE="$HOME/.cloudflared/cert.pem"
if [ ! -f "$CERT_FILE" ]; then
    echo "🔐 Đăng nhập Cloudflare..."
    cloudflared tunnel login || { echo "❌ Đăng nhập Cloudflare thất bại"; exit 1; }
fi

# Xử lý Tunnel
echo "🔍 Kiểm tra tunnel tồn tại..."
TUNNEL_EXISTS=$(cloudflared tunnel list | grep -c "$CLOUDFLARE_TUNNEL_NAME" || true)
if [ "$TUNNEL_EXISTS" -eq 0 ]; then
    echo "🆕 Tạo tunnel mới: $CLOUDFLARE_TUNNEL_NAME..."
    cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME" || { echo "❌ Tạo tunnel thất bại"; exit 1; }
else
    echo "✅ Tunnel đã tồn tại: $CLOUDFLARE_TUNNEL_NAME"
fi

# Lấy Tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep "$CLOUDFLARE_TUNNEL_NAME" | awk '{print $1}' | head -n 1)
[ -z "$TUNNEL_ID" ] && { echo "❌ Không tìm thấy Tunnel ID"; exit 1; }
echo "✅ Tunnel ID: $TUNNEL_ID"

# Xử lý credentials file
CRED_FILE="$ROOT_DIR/cloudflared/${TUNNEL_ID}.json"
if [ ! -f "$CRED_FILE" ]; then
    echo "🔑 Sao chép credentials file..."
    cp ~/.cloudflared/${TUNNEL_ID}.json "$CRED_FILE" || { echo "❌ Không tìm thấy credentials file"; exit 1; }
fi

# Tạo file .env
echo "📝 Tạo file cấu hình .env..."
cat <<EOL > .env
N8N_PROTOCOL=https
N8N_HOST=$DOMAIN
N8N_EDITOR_BASE_URL=https://$DOMAIN
WEBHOOK_URL=https://$DOMAIN
N8N_SECURE_COOKIE=false
GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
N8N_BASIC_AUTH_ACTIVE=false
CLOUDFLARED_TUNNEL_TOKEN=$(cloudflared tunnel token "$CLOUDFLARE_TUNNEL_NAME")
EOL

# Docker Compose configuration
echo "🐳 Tạo file docker-compose.yml..."
cat <<EOL > docker-compose.yml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    env_file: .env
    networks:
      - cf_network

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
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
echo "🔧 Xử lý file cấu hình Cloudflared..."
if [ -f "$CONFIG_FILE" ]; then
    echo "🔄 Phát hiện config.yml đã tồn tại, đang cập nhật..."
    
    # Kiểm tra hostname đã tồn tại
    if grep -q "hostname: $DOMAIN" "$CONFIG_FILE"; then
        echo "✅ Hostname đã tồn tại trong config.yml"
    else
        # Thêm hostname mới vào trước rule 404
        sed -i '/http_status:404/i \
  - hostname: '"$DOMAIN"'\
    service: http://n8n:5678' "$CONFIG_FILE"
        echo "✅ Đã thêm hostname mới vào config.yml"
    fi
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
echo "🔗 Xử lý bản ghi DNS..."
ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json")

ZONE_ID=$(echo "$ZONE_INFO" | jq -r --arg domain "$DOMAIN" '.result[] | select(.name == $domain | .id)')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
    echo "⚠️ Không tìm thấy Zone ID cho domain chính, thử tìm zone cha..."
    DOMAIN_PARTS=(${DOMAIN//./ })
    PARENT_DOMAIN="${DOMAIN_PARTS[-2]}.${DOMAIN_PARTS[-1]}"
    ZONE_ID=$(echo "$ZONE_INFO" | jq -r --arg domain "$PARENT_DOMAIN" '.result[] | select(.name == $domain) | .id')
fi

if [ -n "$ZONE_ID" ] && [ "$ZONE_ID" != "null" ]; then
    echo "🔍 Kiểm tra bản ghi DNS cho $DOMAIN..."
    DNS_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${DOMAIN}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json")
    
    if [ $(echo "$DNS_CHECK" | jq '.result | length') -eq 0 ]; then
        echo "🆕 Tạo bản ghi CNAME mới..."
        CREATE_DNS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data '{
              "type":"CNAME",
              "name":"'"${DOMAIN}"'",
              "content":"'"${TUNNEL_ID}.cfargotunnel.com"'",
              "ttl":120,
              "proxied":true
          }')
        
        if [ $(echo "$CREATE_DNS" | jq '.success') = "true" ]; then
            echo "✅ Đã tạo bản ghi DNS thành công!"
        else
            echo "⚠️ Không thể tạo bản ghi DNS: $(echo "$CREATE_DNS" | jq '.errors')"
        fi
    else
        echo "✅ Bản ghi DNS đã tồn tại"
    fi
else
    echo "⚠️ Không tìm thấy Zone ID phù hợp, bỏ qua tạo DNS Record"
fi

# Khởi động hệ thống
echo "🚀 Khởi động containers..."
docker-compose down
docker-compose up -d --force-recreate

echo "✨ Cài đặt hoàn tất!"
echo "👉 Truy cập: https://$DOMAIN sau vài phút"
echo "🔧 Kiểm tra trạng thái tunnel: docker logs cloudflared"
