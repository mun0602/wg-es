#!/bin/bash

# Kiểm tra Docker đã được cài đặt chưa
if ! command -v docker &> /dev/null; then
    echo "Docker chưa được cài đặt. Đang tiến hành cài đặt Docker..."
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    echo "Cài đặt Docker hoàn tất."
else
    echo "Docker đã được cài đặt."
fi

# Nhập thông tin từ người dùng
read -p "Nhập domain hoặc IP cho WG_HOST: " WG_HOST
read -sp "Nhập mật khẩu (PASSWORD): " PASSWORD
echo
read -p "Nhập cổng TCP (51821 mặc định): " PORT_TCP

# Sử dụng giá trị mặc định nếu người dùng không nhập
PORT_TCP=${PORT_TCP:-51821}

# Tạo thư mục cấu hình nếu chưa tồn tại
CONFIG_DIR=$(pwd)/config
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    echo "Thư mục cấu hình đã được tạo: $CONFIG_DIR"
fi

# Thực thi lệnh docker run
docker run -d \
  --name=wg-easy \
  -e WG_HOST="$WG_HOST" \
  -e PASSWORD="$PASSWORD" \
  -v "$CONFIG_DIR:/etc/wireguard" \
  -p "51820:51820/udp" \
  -p "$PORT_TCP:51821/tcp" \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --restart=always \
  weejewel/wg-easy

# Hiển thị đường dẫn truy cập
echo "Cài đặt và khởi chạy wg-easy hoàn tất!"
echo "Bạn có thể truy cập tại: http://$WG_HOST:$PORT_TCP"
