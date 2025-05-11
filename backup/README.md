# Hướng dẫn Backup Workflow & Credential n8n lên Github (Docker Server)

> Áp dụng cho hệ thống n8n self-hosted bằng Docker.  
> Giúp bạn tự động backup và quản lý version workflow / credential một cách an toàn, gọn gàng trên Github.

* * *
Ngắn gọn: Tạo SSH theo hướng dẫn:  
👉 [Tạo SSH key và kết nối Github bằng SSH](https://github.com/Nhattanktnn/n8n_setup/blob/main/backup/T%E1%BA%A1o%20SSH%20Key%20GitHub.md)  
Sau đó Import và chạy workflows sau:  
👉 [backup-credential-and-workflow](https://github.com/Nhattanktnn/n8n_setup/blob/main/backup/backup-credentials-and-workflows.json)  
Xong!!!

* * *

# Dưới đây chỉ là mô tả chi tiết hơn

# 📦Chuẩn bị

### 1\. Truy cập container n8n

    docker exec -it <container-name> /bin/sh

> Thay `<container-name>` bằng tên container n8n của bạn (VD: `n8n`).

* * *

## 🔐 Cấu hình SSH để push code lên Github

Làm theo hướng dẫn chi tiết tại:  
👉 [Tạo SSH key và kết nối Github bằng SSH](https://community.autoai.asia/d/9-huong-dan-tao-ssh-key-va-clone-git-repository-bang-ssh-github)

* * *

## 🧠 Tự động backup workflow & credential

Làm theo hướng dẫn chi tiết tại:  
👉 [Backup & Đổi tên file Workflow tự động trong n8n Docker](https://community.autoai.asia/d/10-huong-dan-backup-va-doi-ten-file-workflow-tu-dong-trong-n8n-docker)

* * *

## 🧰 Cấu trúc thư mục khuyến nghị

    n8n_backup/
    ├── workflows/
    │   └── <workflow-name>.json
    ├── credentials/
    │   └── <credential-name>.json
    └── rename-workflow-files.sh  #Theo workflows mới thì không cần thiết file này

* * *

## 🔁 Quy trình chuẩn để backup và push lên Github

1.  **Xoá các file `.json` cũ trong thư mục workflows:**

        rm /home/node/n8n_backup/workflows/*.json

2.  **Export lại toàn bộ workflow và credential:**

```
npx n8n export:workflow --backup --output /home/node/n8n_backup/workflows/ --pretty
```

```
npx n8n export:credentials --backup --output /home/node/n8n_backup/credentials/ --pretty
```

4.  **Đổi tên file theo tên thực tế của workflow (nếu chưa có file):**

        sh /home/node/rename-workflow-files.sh

5.  **Push lên Github:**

        cd /home/node/n8n-autoai-backup
        git add .
        git commit -m " Backup auto $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        git push origin main

* * *

## 💡 Gợi ý tự động hoá

Bạn có thể tạo một workflow trong chính n8n để chạy định kỳ các bước trên (qua `Execute Command`) nhằm tự động backup mỗi ngày.

* * *

## 📌 Ghi chú

-   File `.sh` đổi tên có thể tạo nhanh bằng lệnh sau:
```
    cat > rename-workflow-files.sh << 'EOF'
    #!/bin/sh
    
    WORKFLOW_DIR="/home/node/n8n_backup/workflows"
    
    cd "$WORKFLOW_DIR" || exit 1
    
    # Check if jq exists
    if ! command -v jq > /dev/null 2>&1; then
      echo "jq not found, installing..."
      apt update && apt install -y jq
    fi
    
    # Rename files using workflow name
    for file in *.json; do
      name=$(jq -r '.name' "$file")
      safe_name=$(echo "$name" | tr -cd '[:alnum:]-_ ' | tr ' ' '_')
      mv "$file" "${safe_name}.json"
    done
    
    echo " Rename completed."
    EOF
    
    chmod +x rename-workflow-files.sh
```
* * *

## ✅ Kết quả

Bạn sẽ có:

-   Backup tự động của tất cả workflow và credential
-   File `.json` được đặt đúng tên, dễ quản lý version
-   Lưu trữ an toàn trên Github bằng SSH
