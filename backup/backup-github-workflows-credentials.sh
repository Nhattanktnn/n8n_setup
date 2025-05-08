#!/bin/sh

# Đường dẫn backup
BACKUP_DIR="/home/node/n8n_backup"
WORKFLOW_DIR="$BACKUP_DIR/workflows"
CREDENTIALS_DIR="$BACKUP_DIR/credentials"

# Tạo thư mục
docker exec n8n sh -c "mkdir -p $WORKFLOW_DIR $CREDENTIALS_DIR"

# Xoá file cũ
docker exec n8n sh -c "rm -f $WORKFLOW_DIR/*.json $CREDENTIALS_DIR/*.json"

# Export workflows + credentials
docker exec n8n sh -c "npx n8n export:workflow --backup --output $WORKFLOW_DIR --pretty"
docker exec n8n sh -c "npx n8n export:credentials --backup --output $CREDENTIALS_DIR --pretty"

# Sửa quyền tránh lỗi permission
docker exec n8n sh -c "chown -R node:node $BACKUP_DIR"

# Hàm đổi tên file trong container mà không dùng iconv
rename_files_in_container_dir() {
  DIR="$1"
  echo "🔄 Đang đổi tên các file trong $DIR..."

  docker exec n8n sh -c "
    for file in $DIR/*.json; do
      [ ! -f \"\$file\" ] && continue
      name=\$(jq -r '.name' \"\$file\" 2>/dev/null)
      [ -z \"\$name\" ] || [ \"\$name\" = \"null\" ] && continue
      safe_name=\$(echo \"\$name\" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' | sed -e 's/-\+/-/g' | sed -e 's/^-//' | sed -e 's/-\$//')
      new_path=\"$DIR/\$safe_name.json\"
      [ \"\$file\" != \"\$new_path\" ] && mv \"\$file\" \"\$new_path\" && echo \"✅ Đã đổi: \$(basename \"\$file\") → \$(basename \"\$new_path\")\"
    done
  "
}

rename_files_in_container_dir "$WORKFLOW_DIR"
rename_files_in_container_dir "$CREDENTIALS_DIR"

# Cấu hình git nếu chưa có
echo "⚙️ Đang cấu hình Git trong container..."
docker exec n8n sh -c "
  git config --global user.email 'you@example.com'
  git config --global user.name 'Your Name'
"

# Push lên Github
echo "🚀 Đang push lên Github..."
docker exec n8n sh -c "
  cd $BACKUP_DIR && \
  if [ ! -d .git ]; then
    git init
    git remote add origin https://github.com/yourusername/your-repository.git
    git pull origin main || true
  fi && \
  git add . && \
  git commit -m 'Backup auto $(date -u +'%Y-%m-%dT%H:%M:%SZ')' && \
  git push origin main
"

echo "🎉 Hoàn tất!"
