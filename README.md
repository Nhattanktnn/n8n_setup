# n8n_setup
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
bash <(curl -L https://raw.githubusercontent.com/Nhattanktnn/n8n_setup/refs/heads/main/setup.sh)

** Sau khi cài, nếu lỗi, hãy thử:
sudo usermod -aG docker $USER \n
sudo reboot
