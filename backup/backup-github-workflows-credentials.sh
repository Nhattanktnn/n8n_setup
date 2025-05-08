#!/bin/sh

# Định nghĩa đường dẫn lưu trữ backup
BACKUP_DIR="/home/node/n8n_backup"
WORKFLOW_DIR="$BACKUP_DIR/workflows"
CREDENTIALS_DIR="$BACKUP_DIR/credentials"

# Tạo thư mục lưu trữ với quyền user node
echo "🛠️ Đang tạo thư mục lưu trữ..."
docker exec -u node n8n sh -c "mkdir -p $WORKFLOW_DIR && mkdir -p $CREDENTIALS_DIR"

# Xoá các file JSON cũ
echo "🧹 Đang xoá các file JSON cũ..."
docker exec -u node n8n sh -c "rm -f $WORKFLOW_DIR/*.json $CREDENTIALS_DIR/*.json"

# Export workflows và credentials
echo "📦 Đang export workflows..."
docker exec -u node n8n sh -c "npx n8n export:workflow --backup --output $WORKFLOW_DIR --pretty"

echo "📦 Đang export credentials..."
docker exec -u node n8n sh -c "npx n8n export:credentials --backup --output $CREDENTIALS_DIR --pretty"

# Hàm chuẩn hóa tên file
normalize_filename() {
  echo "$1" | 
  iconv -f utf8 -t ascii//TRANSLIT//IGNORE | 
  tr '[:upper:]' '[:lower:]' |
  sed -E 's/[^a-z0-9]+/-/g' |
  sed -E 's/^-+|-+$//g' |
  sed -E 's/-+/-/g'
}

# Hàm đổi tên file trong container
rename_files() {
  DIR_TYPE="$1"
  CONTAINER_DIR="$2"
  
  docker exec -u node n8n sh <<EOF
    for file in $CONTAINER_DIR/*.json; do
      [ -f "\$file" ] || continue
      
      # Lấy ID và Name từ file
      id=\$(jq -r '.id' "\$file" 2>/dev/null)
      name=\$(jq -r '.name' "\$file" 2>/dev/null)
      
      # Tạo tên file an toàn
      if [ -n "\$name" ] && [ "\$name" != "null" ]; then
        safe_name=\$(echo "\$name" | normalize_filename)
        filename="\${safe_name}"
      else
        filename="\${id}"
      fi
      
      # Đảm bảo không trùng lặp
      new_path="$CONTAINER_DIR/\${filename}.json"
      counter=1
      while [ -f "\$new_path" ]; do
        new_path="$CONTAINER_DIR/\${filename}-\${counter}.json"
        counter=\$((counter+1))
      done
      
      mv "\$file" "\$new_path"
      echo "✅ Đã đổi $DIR_TYPE: \$(basename "\$file") → \$(basename "\$new_path")"
    done
EOF
}

# Đổi tên workflows và credentials
echo "🔄 Đang đổi tên workflows..."
rename_files "workflow" "$WORKFLOW_DIR"

echo "🔄 Đang đổi tên credentials..."
rename_files "credential" "$CREDENTIALS_DIR"

# Cấu hình GitHub
GIT_REPO="https://github_token@github.com/yourusername/yourrepo.git"
GIT_BRANCH="main"

echo "🚀 Đang đồng bộ với GitHub..."
docker exec -u node n8n sh <<EOF
  set -e
  cd $BACKUP_DIR
  
  # Khởi tạo repo nếu chưa có
  if [ ! -d .git ]; then
    git init
    git remote add origin "$GIT_REPO" || true
    git fetch origin
    git checkout -b $GIT_BRANCH || git checkout $GIT_BRANCH
  fi

  # Commit và push
  git add .
  if git diff-index --quiet HEAD --; then
    echo "🟢 Không có thay đổi để commit"
  else
    git config user.name "n8n Backup Bot"
    git config user.email "backup@n8n"
    git commit -m "Backup auto \$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    git push -u origin $GIT_BRANCH
  fi
EOF

echo "🎉 Backup và đồng bộ hoàn tất!"
