#!/bin/sh

# Định nghĩa đường dẫn
BACKUP_DIR="/home/node/n8n_backup"
WORKFLOW_DIR="$BACKUP_DIR/workflows"
CREDENTIALS_DIR="$BACKUP_DIR/credentials"

# Hàm chuẩn hóa tên file chạy TRONG container
NORMALIZE_SCRIPT='
normalize() {
  echo "$1" | 
  iconv -f utf8 -t ascii//TRANSLIT//IGNORE | 
  tr "[:upper:]" "[:lower:]" |
  sed -E "s/[^a-z0-9]+/-/g" |
  sed -E "s/^-+|-+$//g" |
  sed -E "s/-+/-/g"
}'

rename_files() {
  DIR_TYPE="$1"
  CONTAINER_DIR="$2"
  
  echo "🔄 Đang đổi tên ${DIR_TYPE}..."
  
  docker exec -u node n8n sh <<EOF
    $NORMALIZE_SCRIPT

    for file in ${CONTAINER_DIR}/*.json; do
      [ -f "\$file" ] || continue
      
      # Lấy thông tin từ file
      id=\$(jq -r '.id // ""' "\$file" 2>/dev/null)
      name=\$(jq -r '.name // ""' "\$file" 2>/dev/null)
      
      # Tạo filename
      if [ -n "\$name" ]; then
        safe_name=\$(normalize "\$name")
        filename="\${safe_name}"
      elif [ -n "\$id" ]; then
        filename="\${id}"
      else
        echo "⚠️ File \$file thiếu cả name và id, bỏ qua..."
        continue
      fi

      # Đảm bảo không trùng
      new_path="${CONTAINER_DIR}/\${filename}.json"
      counter=1
      while [ -f "\$new_path" ] && [ "\$(realpath "\$new_path")" != "\$(realpath "\$file")" ]; do
        new_path="${CONTAINER_DIR}/\${filename}-\${counter}.json"
        counter=\$((counter+1))
      done

      # Đổi tên
      if ! mv -f "\$file" "\$new_path"; then
        echo "❌ Lỗi khi đổi tên \$file"
      else
        echo "✅ Đổi: \$(basename "\$file") → \$(basename "\$new_path")"
      fi
    done
EOF
}

# Gọi hàm đổi tên
rename_files "workflows" "$WORKFLOW_DIR"
rename_files "credentials" "$CREDENTIALS_DIR"

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
