#!/bin/sh

# Lấy đường dẫn thư mục chứa file script (base directory)
BASE_DIR=$(dirname "$(realpath "$0")")
WORKFLOW_DIR="$BASE_DIR/workflows"
CREDENTIALS_DIR="$BASE_DIR/credentials"

# Kiểm tra jq đã cài chưa
if ! command -v jq > /dev/null 2>&1; then
  echo "jq chưa được cài đặt, đang cài đặt..."
  apt update && apt install -y jq
fi

# Hàm tạo slug: bỏ dấu, lowercase, thay ký tự đặc biệt bằng "-"
remove_vietnamese_accents() {
  echo "$1" \
    | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g' \
    | sed -E 's/-+/-/g'
}

# Hàm đổi tên file trong một thư mục
rename_files_in_directory() {
  DIR="$1"

  if [ ! -d "$DIR" ]; then
    echo "Thư mục $DIR không tồn tại, bỏ qua..."
    return
  fi

  for file in "$DIR"/*.json; do
    if [ -f "$file" ]; then
      name=$(jq -r '.name' "$file" 2>/dev/null)

      if [ -z "$name" ] || [ "$name" = "null" ]; then
        echo "Không lấy được tên từ $file, bỏ qua..."
        continue
      fi

      safe_name=$(remove_vietnamese_accents "$name")
      new_path="$DIR/${safe_name}.json"

      if [ "$file" != "$new_path" ]; then
        mv "$file" "$new_path"
        echo "✅ Đã đổi: $(basename "$file") → $(basename "$new_path")"
      fi
    fi
  done
}

# Thực thi
echo "📁 Đang xử lý workflows..."
rename_files_in_directory "$WORKFLOW_DIR"

echo "📁 Đang xử lý credentials..."
rename_files_in_directory "$CREDENTIALS_DIR"

echo "🎉 Đổi tên hoàn tất!"
