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

# Kiểm tra xem container wg-easy đã tồn tại chưa
if docker ps -a --format "table {{.Names}}" | grep -q "wg-easy"; then
    echo "Phát hiện container wg-easy đã tồn tại!"
    echo "Bạn có muốn:"
    echo "1. Thay đổi cấu hình (domain, cổng, mật khẩu)"
    echo "2. Xóa container cũ và cài đặt lại"
    echo "3. Thoát"
    read -p "Chọn lựa chọn (1-3): " choice
    
    case $choice in
        1)
            echo "Đang dừng và xóa container cũ..."
            docker stop wg-easy 2>/dev/null
            docker rm wg-easy 2>/dev/null
            ;;
        2)
            echo "Đang xóa container cũ..."
            docker stop wg-easy 2>/dev/null
            docker rm wg-easy 2>/dev/null
            ;;
        3)
            echo "Thoát script."
            exit 0
            ;;
        *)
            echo "Lựa chọn không hợp lệ. Thoát script."
            exit 1
            ;;
    esac
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
echo "Đang khởi chạy wg-easy với cấu hình mới..."
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

# Kiểm tra xem container có chạy thành công không
if docker ps --format "table {{.Names}}" | grep -q "wg-easy"; then
    echo "✅ Cài đặt và khởi chạy wg-easy hoàn tất!"
    echo "🌐 Bạn có thể truy cập tại: http://$WG_HOST:$PORT_TCP"
    echo "🔑 Mật khẩu: $PASSWORD"
    echo "📁 Thư mục cấu hình: $CONFIG_DIR"
else
    echo "❌ Có lỗi xảy ra khi khởi chạy container. Kiểm tra logs:"
    docker logs wg-easy
fi
