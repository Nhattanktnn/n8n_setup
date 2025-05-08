#!/bin/sh

# Định nghĩa đường dẫn lưu trữ backup trong container
BACKUP_DIR="/home/node/n8n_backup"
WORKFLOW_DIR="$BACKUP_DIR/workflows"
CREDENTIALS_DIR="$BACKUP_DIR/credentials"

# 🛠️ Tạo thư mục lưu trữ nếu chưa tồn tại
echo "🛠️ Đang tạo thư mục lưu trữ..."
docker exec n8n sh -c "mkdir -p $WORKFLOW_DIR && mkdir -p $CREDENTIALS_DIR"

# 🧹 Xoá các file JSON cũ trong thư mục backup
echo "🧹 Đang xoá các file JSON cũ trong thư mục workflows và credentials..."
docker exec n8n sh -c "rm -f $WORKFLOW_DIR/*.json $CREDENTIALS_DIR/*.json"

# 📦 Export workflows và credentials
echo "📦 Đang export workflows..."
docker exec n8n sh -c "npx n8n export:workflow --backup --output $WORKFLOW_DIR --pretty"

echo "📦 Đang export credentials..."
docker exec n8n sh -c "npx n8n export:credentials --backup --output $CREDENTIALS_DIR --pretty"

# 🔐 Sửa quyền cho thư mục backup để tránh lỗi permission khi rename
docker exec n8n sh -c "chown -R node:node $BACKUP_DIR"

# 🔄 Hàm đổi tên file JSON trong container
rename_files_in_container_dir() {
  DIR="$1"
  echo "🔄 Đang đổi tên các file trong $DIR..."
  docker exec n8n sh -c "
    if [ ! -d \"$DIR\" ]; then
      echo 'Thư mục $DIR không tồn tại trong container, bỏ qua...'
      exit 0
    fi

    for file in $DIR/*.json; do
      if [ -f \"\$file\" ]; then
        name=\$(jq -r '.name' \"\$file\" 2>/dev/null)
        if [ -z \"\$name\" ] || [ \"\$name\" = \"null\" ]; then
          echo \"Không lấy được tên từ \$file, bỏ qua...\"
          continue
        fi
        safe_name=\$(echo \"\$name\" | iconv -f utf-8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+\$//g' | sed -E 's/-+/-/g')
        new_path=\"$DIR/\${safe_name}.json\"
        if [ \"\$file\" != \"\$new_path\" ]; then
          mv \"\$file\" \"\$new_path\"
          echo \"✅ Đã đổi: \$(basename \"\$file\") → \$(basename \"\$new_path\")\"
        fi
      fi
    done
  "
}

rename_files_in_container_dir "$WORKFLOW_DIR"
rename_files_in_container_dir "$CREDENTIALS_DIR"

# 🚀 Push lên GitHub (nếu container đã cấu hình git từ trước)
echo "🚀 Đang push lên Github..."
docker exec n8n sh -c "
  cd $BACKUP_DIR && \
  if [ ! -d .git ]; then \
    git init && \
    git remote add origin https://github.com/yourusername/your-repository.git && \
    git pull origin main || true; \
  fi && \
  git add . && \
  git commit -m 'Backup auto $(date -u +'%Y-%m-%dT%H:%M:%SZ')' && \
  git push origin main
"

echo "🎉 Backup và push lên Github hoàn tất!"
