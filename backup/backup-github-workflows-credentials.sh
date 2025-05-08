#!/bin/sh

# Định nghĩa đường dẫn lưu trữ backup
BACKUP_DIR="/home/node/n8n_backup"
WORKFLOW_DIR="$BACKUP_DIR/workflows"
CREDENTIALS_DIR="$BACKUP_DIR/credentials"

# Tạo thư mục lưu trữ nếu chưa tồn tại
mkdir -p "$WORKFLOW_DIR"
mkdir -p "$CREDENTIALS_DIR"

# Xoá các file JSON cũ trong thư mục backup
echo "🧹 Đang xoá các file JSON cũ trong thư mục workflows..."
rm -f "$WORKFLOW_DIR"/*.json
rm -f "$CREDENTIALS_DIR"/*.json

# Export lại toàn bộ workflows và credentials
echo "📦 Đang export workflows..."
docker exec -it n8n npx n8n export:workflow --backup --output "$WORKFLOW_DIR" --pretty

echo "📦 Đang export credentials..."
docker exec -it n8n npx n8n export:credentials --backup --output "$CREDENTIALS_DIR" --pretty

# Đổi tên các file theo tên thực tế của workflow/credential (nếu có file rename)
echo "🔄 Đang đổi tên các file..."
sh /home/node/rename-workflow-files.sh

# Push lên Github (cần cấu hình git và token để push)
echo "🚀 Đang push lên Github..."
cd "$BACKUP_DIR"
git add .
git commit -m "Backup auto $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
git push origin main

echo "🎉 Backup và push lên Github hoàn tất!"
