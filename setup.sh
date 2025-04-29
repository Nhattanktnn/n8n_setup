#!/bin/bash
set -e # Dừng script nếu có lỗi
export DOCKER_BUILDKIT=1

ROOT_DIR=~/n8n-docker
CLOUDFLARE_TUNNEL_NAME=n8n-selfhost-tunnel

# Cập nhật package list
sudo apt-get update

# Kiểm tra và cài đặt dependencies
echo "🔎 Kiểm tra dependencies..."
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq chưa cài. Đang cài đặt..."
    sudo apt-get install -y jq || { echo "❌ Cài jq thất bại"; exit 1; }
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker chưa cài. Đang cài đặt..."
    sudo apt-get install -y docker.io || { echo "❌ Cài Docker thất bại"; exit 1; }
    sudo systemctl start docker
    sudo systemctl enable docker
fi
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ Docker Compose chưa cài. Đang cài đặt..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "❌ Tải Docker Compose thất bại"; exit 1; }
    sudo chmod +x /usr/local/bin/docker-compose || { echo "❌ Cài Docker Compose thất bại"; exit 1; }
fi

echo "🚀 Đang tạo thư mục dự án tại $ROOT_DIR..."
mkdir -p $ROOT_DIR/nginx/conf.d $ROOT_DIR/cloudflared
cd $ROOT_DIR

# Nhập và kiểm tra domain
read -p "🌐 Nhập tên miền (VD: https://n8n.domain.com hoặc n8n.domain.com): " DOMAIN_INPUT
DOMAIN=$(echo "$DOMAIN_INPUT" | sed -E 's~^https?://~~')
if ! echo "$DOMAIN" | grep -P '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
    echo "❌ Tên miền không hợp lệ!"
    exit 1
fi
N8N_PROTOCOL=$(echo "$DOMAIN_INPUT" | grep -Eo '^https?://' | sed 's~://~~')
if [ -z "$N8N_PROTOCOL" ]; then
    N8N_PROTOCOL="https"
fi

echo "🔑 API Token cần quyền Zone:Read, Zone:DNS:Edit"
read -sp "🔑 Nhập API Token Cloudflare: " CF_API_TOKEN
echo

# Tìm tên vùng (zone) từ tên miền
DOMAIN_ZONE=$(echo "$DOMAIN_INPUT" | awk -F. '{print $(NF-1)"."$NF}')

echo "🔎 Kiểm tra cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    echo "❌ Cloudflared chưa cài. Đang cài đặt..."
    if [[ $(uname -s) == "Linux" && $(dpkg --print-architecture) == "amd64" ]]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared-linux-amd64.deb || { echo "❌ Cài cloudflared thất bại"; exit 1; }
        rm cloudflared-linux-amd64.deb
        sudo cloudflared --version || { echo "❌ Kiểm tra cloudflared thất bại"; exit 1; }
    else
        echo "❌ Hệ thống không hỗ trợ cài tự động. Cài cloudflared thủ công:"
        echo "wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        echo "chmod +x cloudflared-linux-amd64 && sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared"
        exit 1
    fi
else
    echo "✅ Cloudflared đã cài."
fi

# Đăng nhập Cloudflare
echo "🔐 Đăng nhập Cloudflare..."
cloudflared tunnel login || { echo "❌ Đăng nhập Cloudflare thất bại"; exit 1; }

# Kiểm tra và xóa Tunnel nếu đã tồn tại
if cloudflared tunnel list | grep -q $CLOUDFLARE_TUNNEL_NAME; then
    echo "⚠️ Tunnel $CLOUDFLARE_TUNNEL_NAME đã tồn tại. Xóa trước khi tạo lại? (y/N)"
    read -r delete_tunnel
    if [[ "$delete_tunnel" =~ ^[Yy]$ ]]; then
        cloudflared tunnel delete $CLOUDFLARE_TUNNEL_NAME
    else
        echo "❌ Hủy thao tác."
        exit 1
    fi
fi

# Tạo tunnel
echo "🔨 Tạo Tunnel mới: $CLOUDFLARE_TUNNEL_NAME..."
cloudflared tunnel create $CLOUDFLARE_TUNNEL_NAME || { echo "❌ Tạo tunnel thất bại"; exit 1; }

# Lấy Tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep $CLOUDFLARE_TUNNEL_NAME | awk '{print $1}' | head -n 1)
if [ -z "$TUNNEL_ID" ]; then
    echo "❌ Không lấy được Tunnel ID"
    exit 1
fi
echo "✅ Tunnel ID: $TUNNEL_ID"

# Copy credentials
CREDENTIALS_SOURCE_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
CREDENTIALS_DEST_FILE="$ROOT_DIR/cloudflared/${TUNNEL_ID}.json"
if [ ! -f "$CREDENTIALS_SOURCE_FILE" ]; then
    echo "❌ File credentials không tồn tại: $CREDENTIALS_SOURCE_FILE"
    exit 1
fi
cp "$CREDENTIALS_SOURCE_FILE" "$CREDENTIALS_DEST_FILE"

# Ghi file .env
if [ -f ".env" ]; then
    echo "⚠️ File .env đã tồn tại. Ghi đè? (y/N)"
    read -r overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "❌ Hủy ghi file .env"
        exit 1
    fi
fi
cat <<EOL > .env
# .env cấu hình n8n
DOMAIN=${DOMAIN}
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_HOST=${DOMAIN}
N8N_EDITOR_BASE_URL=${N8N_PROTOCOL}://${DOMAIN}
WEBHOOK_URL=${N8N_PROTOCOL}://${DOMAIN}
N8N_SECURE_COOKIE=false
GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
N8N_PORT=5678
N8N_BASIC_AUTH_ACTIVE=false
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_ON_PROGRESS=true
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=false
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=259200
NODE_FUNCTION_ALLOW_BUILTIN=*
CLOUDFLARED_TUNNEL_TOKEN=$(cloudflared tunnel token $CLOUDFLARE_TUNNEL_NAME)
EOL

# Ghi file docker-compose.yml
if [ -f "docker-compose.yml" ]; then
    echo "⚠️ File docker-compose.yml đã tồn tại. Ghi đè? (y/N)"
    read -r overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "❌ Hủy ghi file docker-compose.yml"
        exit 1
    fi
fi
cat <<EOL > docker-compose.yml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "\${N8N_PORT}:5678"
    environment:
      - GENERIC_TIMEZONE=\${N8N_TIMEZONE}
      - N8N_BASIC_AUTH_ACTIVE=\${N8N_BASIC_AUTH_ACTIVE}
    volumes:
      - n8n_data:/home/node/.n8n
    restart: always
    networks:
      - internal

  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "8080:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
    depends_on:
      - n8n
    restart: always
    networks:
      - internal

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    command: tunnel --no-autoupdate run --token \${CLOUDFLARED_TUNNEL_TOKEN}
    volumes:
      - ./cloudflared:/etc/cloudflared
    restart: always
    networks:
      - internal

volumes:
  n8n_data:

networks:
  internal:
    driver: bridge
EOL

# Ghi nginx config
cat <<EOL > nginx/conf.d/default.conf
server {
    listen 80;
    server_name ${DOMAIN_INPUT};

    location / {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOL

# Ghi cloudflared config
cat <<EOL > cloudflared/config.yml
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: ${DOMAIN_INPUT}
    service: http://nginx:80
  - service: http_status:404
EOL

echo "🌐 Tạo bản ghi DNS trỏ tên miền vào Tunnel..."

# Lấy Zone ID
ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN_ZONE}" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
ZONE_ID=$(echo $ZONE_INFO | jq -r '.result[0].id')

if [ "$ZONE_ID" = "null" ] || [ -z "$ZONE_ID" ]; then
    echo "❌ Không tìm được Zone ID. Kiểm tra domain hoặc token."
    cloudflared tunnel delete $CLOUDFLARE_TUNNEL_NAME >/dev/null 2>&1 || true
    exit 1
fi

# Kiểm tra bản ghi DNS
DNS_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${DOMAIN_INPUT}" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
DNS_EXISTS=$(echo $DNS_CHECK | jq -r '.result | length')

if [ "$DNS_EXISTS" -gt 0 ]; then
    echo "⚠️ Bản ghi DNS cho $DOMAIN_INPUT đã tồn tại. Bỏ qua tạo mới."
else
    # Tạo bản ghi CNAME
    CREATE_DNS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" --data '{
      "type":"CNAME",
      "name":"'"${DOMAIN_INPUT}"'",
      "content":"'"${TUNNEL_ID}.cfargotunnel.com"'",
      "ttl":120,
      "proxied":true
    }')
    SUCCESS=$(echo $CREATE_DNS | jq -r '.success')
    if [ "$SUCCESS" != "true" ]; then
        echo "❌ Tạo DNS thất bại: $(echo $CREATE_DNS | jq -r '.errors')"
        cloudflared tunnel delete $CLOUDFLARE_TUNNEL_NAME >/dev/null 2>&1 || true
        exit 1
    fi
    echo "✅ Đã tạo bản ghi DNS CNAME cho $DOMAIN_INPUT!"
fi

echo ""
echo "✅ Đã hoàn tất setup!"
echo "👉 Chạy hệ thống bằng lệnh:"
echo "cd $ROOT_DIR && docker-compose --env-file .env up -d"
echo ""
echo "🌟 Hệ thống n8n + nginx + cloudflared + DNS ready!"
