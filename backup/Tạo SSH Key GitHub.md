# Hướng Dẫn Tạo SSH Key và Clone Git Repository Bằng SSH (GitHub)

Bạn cần phải vào N8N docker trước bằng lệnh (Hoặc nếu tạo trên vps mà không phải trong container thì không cần bước này):

    docker exec -it n8n sh

Đường dẫn trong container docker có dạng như sau:
```
/home/node/n8n_backup/
├── credentials/
└── workflows/
```

## 1\. Kiểm tra SSH key hiện có

Mở Terminal và chạy:

    ls -al ~/.ssh

Nếu thấy id\_rsa và id\_rsa.pub thì bạn đã có SSH key. Nếu không, sang bước 2 để tạo.

## 2\. Tạo SSH key mới

    ssh-keygen -t rsa -b 4096 -C "youremail@example.com"

  •	Nhấn Enter để lưu tại ~/.ssh/id_rsa  
  •	Đặt passphrase nếu muốn, hoặc để trống

## 3\. Thêm SSH key vào SSH agent

    eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/id_rsa

## 4\. Thêm SSH key vào GitHub

4.1. Sao chép public key

    cat ~/.ssh/id_rsa.pub
4.2. Dán vào GitHub  
• Truy cập: [https://github.com/settings/keys](https://github.com/settings/keys)  
• Nhấn “New SSH key”  
• Dán key vào ô “Key”, đặt tên, rồi nhấn Add SSH key

## 5\. Kiểm tra kết nối với GitHub

    ssh -T git@github.com  
Kết quả thành công:

Hi your-username! You've successfully authenticated...

## 6\. Clone repository bằng SSH

Thay vì HTTPS, dùng SSH:

    git clone git@github.com:username/repo.git
Ví dụ:

    git clone git@github.com:Nhattanktnn/n8n_backup.git

hoặc sau khi đã clone muốn pull về lại thì dùng câu lệnh:

    cd n8n_backup && git pull

** Lưu ý: Nếu tạo trong vps và ánh xạ vào container, thì docker-compose.yml bổ sung đoạn này trong ```volumes```:

    - ~/.ssh:/home/node/.ssh:ro

## Tóm tắt nhanh

Bước Lệnh chính  
Kiểm tra key `ls -al ~/.ssh`  
Tạo key mới `ssh-keygen -t rsa -b 4096 -C "youremail@example.com"`  
Thêm vào agent `ssh-add ~/.ssh/id\_rsa`  
Copy key `cat ~/.ssh/id\_rsa.pub`  
Kiểm tra kết nối `ssh -T git@github.com`  
Clone repo git clone `git clone git@github.com:username/repo.git`

SSH giúp làm việc với Git nhanh hơn, bảo mật hơn mà không cần nhập mật khẩu mỗi lần git push.
