# n8n_setup
## Cây thư mục có dạng như sau:

```
n8n-docker/
├── docker-compose.yml
├── .env
├── cloudflared/
│   └── config.yml
├── nginx/
│   └── conf.d/
│       └── default.conf
```

## B1: Thêm domain vào cloudflared: 
Đăng nhập vào Cloudflared -> Account Home -> Add domain
## B2: Tạo API token:
Vào Account (góc phải) -> Profile -> API Tokens -> Create Custom Token :
- Permissions:
  Account | Account Setting | Read
  Zone | Zone | Read
  Zone | DNS | Edit
- Account Resource:
  Include | All Account
- Zone Resources:
  Include | Special Zone | domain của bạn
=> Continue to summary

Copy Token API để sử dụng.
Copy domain để sử dụng

## B3: Chạy code
```
bash <(curl -L https://raw.githubusercontent.com/Nhattanktnn/n8n_setup/refs/heads/main/setup.sh)
```
### Sau khi cài, nếu lỗi, hãy thử lệnh dưới đây, sau đó chạy lại bước 3:
```
sudo usermod -aG docker $USER
```
```
sudo reboot
```
### Muốn xoá docker và các container đã cài thì:
```
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras && \
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker ~/.docker /var/run/docker.sock && \
sudo groupdel docker 2>/dev/null && \
sudo rm -rf /etc/apt/sources.list.d/docker* && \
sudo apt-get autoremove -y --purge && \
sudo updatedb && echo "Docker đã được xóa sạch 100%"
```
