#!/bin/bash
set -e # Dừng script nếu có lỗi
export DOCKER_BUILDKIT=1

ROOT_DIR=~/n8n-docker
read -p "Nhập tên Tunnel Cloudflare cần sử dụng/tạo: " CLOUDFLARE_TUNNEL_NAME

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
fi

# Đảm bảo Docker daemon hoạt động
if ! sudo systemctl is-active --quiet docker; then
    echo "❌ Docker daemon không hoạt động. Đang khởi động..."
    sudo systemctl start docker
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

echo "🚀 Đang tạo thư mục dự án tại $ROOT_DIR..."
mkdir -p $ROOT_DIR/cloudflared
cd $ROOT_DIR

# Nhập và kiểm tra domain
[ -t 0 ] || exec < /dev/tty
read -p "🌐 Nhập tên miền (VD: n8n.domain.com): " DOMAIN_INPUT
DOMAIN=$(echo "$DOMAIN_INPUT" | sed 's~^https\?://~~')

# Kiểm tra tên miền
if ! echo "$DOMAIN" | grep -qE '^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$'; then
    echo "❌ Tên miền không hợp lệ!"
    exit 1
fi

N8N_PROTOCOL=$(echo "$DOMAIN_INPUT" | grep -Eo '^https?://' | sed 's~://~~')
if [ -z "$N8N_PROTOCOL" ]; then
    N8N_PROTOCOL="https"
fi

# Nhập API Token (ẩn input)
echo "🔑 API Token cần quyền Zone:Read, Zone:DNS:Edit"
printf "🔑 Nhập API Token Cloudflare: "
read CF_API_TOKEN

# Kiểm tra cloudflared
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
CERT_FILE="$HOME/.cloudflared/cert.pem"

# Kiểm tra certificate đã tồn tại
if [ ! -f "$CERT_FILE" ]; then
    echo "🔐 Đăng nhập Cloudflare..."
    cloudflared tunnel login || { echo "❌ Đăng nhập Cloudflare thất bại"; exit 1; }
else
    echo "✅ Certificate Cloudflare đã tồn tại."
fi

# Kiểm tra Tunnel đã tồn tại
TUNNEL_EXISTS=$(cloudflared tunnel list | grep -w "$CLOUDFLARE_TUNNEL_NAME" | wc -l)

if [ "$TUNNEL_EXISTS" -eq 0 ]; then
    # Tunnel chưa tồn tại, tạo mới
    echo "🔨 Tạo Tunnel mới: $CLOUDFLARE_TUNNEL_NAME..."
    cloudflared tunnel create $CLOUDFLARE_TUNNEL_NAME || { echo "❌ Tạo tunnel thất bại"; exit 1; }
else
    echo "✅ Tunnel $CLOUDFLARE_TUNNEL_NAME đã tồn tại, sẽ sử dụng tunnel này."
fi

# Lấy Tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep -w "$CLOUDFLARE_TUNNEL_NAME" | awk '{print $1}' | head -n 1)
if [ -z "$TUNNEL_ID" ]; then
    echo "❌ Không lấy được Tunnel ID"
    exit 1
fi
echo "✅ Tunnel ID: $TUNNEL_ID"

# Copy credentials
CREDENTIALS_SOURCE_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
CREDENTIALS_DEST_FILE="$ROOT_DIR/cloudflared/${TUNNEL_ID}.json"

# Xác định Credential cần copy tồn tại hay không
if [ ! -f "$CREDENTIALS_SOURCE_FILE" ]; then
    echo "❌ File credentials không tồn tại: $CREDENTIALS_SOURCE_FILE"
    exit 1
fi

# Copy credentials nếu chưa tồn tại
if [ ! -f "$CREDENTIALS_DEST_FILE" ]; then
    cp "$CREDENTIALS_SOURCE_FILE" "$CREDENTIALS_DEST_FILE" || { echo "❌ Không thể copy credentials"; exit 1; }
    echo "✅ Đã copy credentials"
else
    echo "✅ Credentials đã tồn tại"
fi

# Ghi file .env
cat <<EOL > .env
# .env cấu hình n8n
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_HOST=${DOMAIN}
N8N_EDITOR_BASE_URL=${N8N_PROTOCOL}://${DOMAIN}
WEBHOOK_URL=${N8N_PROTOCOL}://${DOMAIN}
N8N_SECURE_COOKIE=false
GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
N8N_BASIC_AUTH_ACTIVE=false
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_ON_PROGRESS=true
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=false
EXECUTIONS_DATA_PRUNE=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_RUNNERS_ENABLED=true
EXECUTIONS_DATA_MAX_AGE=259200
# NODE_FUNCTION_ALLOW_BUILTIN=*
# NODE_FUNCTION_ALLOW_EXTERNAL=zca-js
CLOUDFLARED_TUNNEL_TOKEN=$(cloudflared tunnel token $CLOUDFLARE_TUNNEL_NAME)
EOL

# Ghi file docker-compose.yml
cat <<EOL > docker-compose.yml
#version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "5678:5678"
    env_file: .env
    volumes:
      - n8n_data:/home/node/.n8n
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

# Kiểm tra và cập nhật file cấu hình cloudflared
CONFIG_FILE="$ROOT_DIR/cloudflared/config.yml"

# Lấy nội dung config hiện tại nếu có
if [ -f "$CONFIG_FILE" ]; then
    echo "🔄 Đang đọc file cấu hình cloudflared hiện tại..."
    # Kiểm tra xem hostname đã tồn tại trong config chưa
    HOSTNAME_EXISTS=$(grep -c "hostname: $DOMAIN" "$CONFIG_FILE" || true)
    
    if [ "$HOSTNAME_EXISTS" -gt 0 ]; then
        echo "✅ Domain $DOMAIN đã tồn tại trong cấu hình cloudflared."
    else
        echo "🔄 Đang thêm domain $DOMAIN vào cấu hình cloudflared..."
        # Tạo file tạm với nội dung mới
        TEMP_CONFIG_FILE="$ROOT_DIR/cloudflared/config.yml.tmp"
        
        # Lấy dòng đầu tiên có chứa 'ingress:'
        INGRESS_LINE=$(grep -n "ingress:" "$CONFIG_FILE" | cut -d: -f1)
        
        # Tách file thành hai phần: trước và sau 'ingress:'
        head -n "$INGRESS_LINE" "$CONFIG_FILE" > "$TEMP_CONFIG_FILE"
        echo "  - hostname: $DOMAIN" >> "$TEMP_CONFIG_FILE"
        echo "    service: http://n8n:5678" >> "$TEMP_CONFIG_FILE"
        tail -n +$((INGRESS_LINE+1)) "$CONFIG_FILE" >> "$TEMP_CONFIG_FILE"
        
        # Thay thế file cũ bằng file mới
        mv "$TEMP_CONFIG_FILE" "$CONFIG_FILE"
        echo "✅ Đã thêm cấu hình cho domain $DOMAIN."
    fi
else
    # Tạo file cấu hình mới
    echo "🔄 Tạo file cấu hình cloudflared mới..."
    cat <<EOL > "$CONFIG_FILE"
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: ${DOMAIN}
    service: http://n8n:5678
  - service: http_status:404
EOL
    echo "✅ Đã tạo file cấu hình cloudflared."
fi

echo "🌐 Tạo bản ghi DNS trỏ tên miền vào Tunnel..."

# Lấy thông tin domain từ tên miền đầy đủ
DOMAIN_PARTS=(${DOMAIN//./ })
ROOT_DOMAIN="${DOMAIN_PARTS[*]: -2:2}"
ROOT_DOMAIN="${ROOT_DOMAIN// /.}"

# Lấy Zone ID
ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json")

ZONE_ID=$(echo "$ZONE_INFO" | jq -r --arg name "$ROOT_DOMAIN" '.result[] | select(.name == $name) | .id')

if [ "$ZONE_ID" = "null" ] || [ -z "$ZONE_ID" ]; then
    echo "❌ Không tìm được Zone ID. Kiểm tra domain hoặc token."
    exit 1
fi

# Kiểm tra bản ghi DNS
DNS_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${DOMAIN}" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
DNS_EXISTS=$(echo $DNS_CHECK | jq -r '.result | length')

if [ "$DNS_EXISTS" -gt 0 ]; then
    echo "⚠️ Bản ghi DNS cho $DOMAIN đã tồn tại."
    
    # Kiểm tra nội dung bản ghi
    CURRENT_CONTENT=$(echo "$DNS_CHECK" | jq -r '.result[0].content')
    if [ "$CURRENT_CONTENT" = "${TUNNEL_ID}.cfargotunnel.com" ]; then
        echo "✅ Bản ghi DNS đã trỏ đúng vào tunnel. Không cần sửa."
    else
        echo "🔄 Bản ghi DNS không trỏ đúng tunnel. Đang cập nhật..."
        
        # Lấy DNS Record ID
        DNS_RECORD_ID=$(echo "$DNS_CHECK" | jq -r '.result[0].id')
        
        # Cập nhật bản ghi DNS
        UPDATE_DNS=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${DNS_RECORD_ID}" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data '{
            "type":"CNAME",
            "name":"'"${DOMAIN}"'",
            "content":"'"${TUNNEL_ID}.cfargotunnel.com"'",
            "ttl":120,
            "proxied":true
          }')
        
        if [ "$(echo "$UPDATE_DNS" | jq -r '.success')" != "true" ]; then
            echo "❌ Cập nhật bản ghi DNS thất bại: $(echo "$UPDATE_DNS" | jq -r '.errors')"
            exit 1
        fi
        echo "✅ Đã cập nhật bản ghi DNS thành công!"
    fi
else
    # Tạo bản ghi CNAME mới
    echo "🔄 Đang tạo bản ghi DNS mới..."
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

    SUCCESS=$(echo "$CREATE_DNS" | jq -r '.success')
    if [ "$SUCCESS" != "true" ]; then
        echo "❌ Tạo DNS thất bại: $(echo "$CREATE_DNS" | jq -r '.errors')"
        exit 1
    fi
    echo "✅ Đã tạo bản ghi DNS CNAME cho $DOMAIN!"
fi

echo "👉 Setup n8n bằng docker-compose:"
cd ~/n8n-docker && docker-compose pull && docker-compose up -d --force-recreate

echo "🌟 Hệ thống n8n + cloudflared + DNS ready!"
echo "🌐 Truy cập n8n tại: ${N8N_PROTOCOL}://${DOMAIN}"
echo '⚠️ Lưu ý: Nếu Docker vẫn không hoạt động, hãy chạy: newgrp docker hoặc sudo reboot'
