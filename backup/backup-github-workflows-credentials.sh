#!/bin/sh
set -e

# === Cấu hình thư mục cố định trong container ===
BASE_DIR="/home/node/n8n_backup"
WORKFLOW_DIR="$BASE_DIR/workflows"
CREDENTIALS_DIR="$BASE_DIR/credentials"

# === Kiểm tra jq đã cài chưa ===
if ! command -v jq > /dev/null 2>&1; then
  echo "jq chưa được cài đặt, đang cài đặt..."
  apt update && apt install -y jq
fi

# === Hàm tạo slug: bỏ dấu, lowercase, thay ký tự đặc biệt bằng "-" ===
remove_vietnamese_accents() {
  echo "$1" \
    | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g' \
    | sed -E 's/-+/-/g'
}

# === Hàm đổi tên file JSON trong thư mục ===
rename_files_in_directory() {
  DIR="$1"

  if [ ! -d "$DIR" ]; then
    echo "📂 Thư mục $DIR không tồn tại, bỏ qua..."
    return
  fi

  for file in "$DIR"/*.json; do
    [ -f "$file" ] || continue

    name=$(jq -r '.name' "$file" 2>/dev/null)
    if [ -z "$name" ] || [ "$name" = "null" ]; then
      echo "⚠️ Không lấy được tên từ $(basename "$file"), bỏ qua..."
      continue
    fi

    safe_name=$(remove_vietnamese_accents "$name")
    new_path="$DIR/${safe_name}.json"

    if [ "$file" != "$new_path" ]; then
      mv "$file" "$new_path"
      echo "✅ Đã đổi: $(basename "$file") → $(basename "$new_path")"
    fi
  done
}

# === Xoá các file cũ ===
echo "🧹 Xoá file JSON cũ..."
mkdir -p "$WORKFLOW_DIR" "$CREDENTIALS_DIR"
rm -f "$WORKFLOW_DIR/"*.json "$CREDENTIALS_DIR/"*.json || true

# === Export dữ liệu từ n8n ===
echo "📤 Export workflows và credentials..."
npx n8n export:workflow --backup --output "$WORKFLOW_DIR" --pretty
npx n8n export:credentials --backup --output "$CREDENTIALS_DIR" --pretty

# === Đổi tên file ===
echo "🔤 Đổi tên file JSON..."
rename_files_in_directory "$WORKFLOW_DIR"
rename_files_in_directory "$CREDENTIALS_DIR"

# === Push Git ===
echo "📦 Đẩy lên GitHub..."
cd "$BASE_DIR"
git add .
git commit -m "Backup auto $(date -u +'%Y-%m-%dT%H:%M:%SZ')" || echo "🟡 Không có thay đổi để commit."
git push origin main

echo "✅ Hoàn tất backup và đẩy GitHub."
