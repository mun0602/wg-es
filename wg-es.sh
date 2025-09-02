#!/bin/bash

# ==============================================================================
# Script cài đặt ngoduykhanh/wireguard-ui bằng Docker trên Ubuntu
#
# Chức năng:
# 1. Kiểm tra và cài đặt Docker & Docker Compose.
# 2. Tạo thư mục và file docker-compose.yml.
# 3. Yêu cầu người dùng đặt username/password.
# 4. Cấu hình sẵn volumes để lưu trữ dữ liệu lâu dài.
# 5. Mở firewall (UFW) cho các port cần thiết.
# 6. Hướng dẫn các lệnh để khởi chạy và quản lý.
# ==============================================================================

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Hàm kiểm tra và cài đặt Docker
install_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✅ Docker đã được cài đặt.${NC}"
    else
        echo -e "${YELLOW}⚠️ Docker chưa được cài đặt. Bắt đầu cài đặt...${NC}"
        sudo apt-get update -y
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo usermod -aG docker $USER
        echo -e "${GREEN}✅ Cài đặt Docker hoàn tất!${NC}"
        echo -e "${YELLOW}💡 Bạn cần đăng xuất và đăng nhập lại, hoặc chạy 'newgrp docker' để dùng lệnh docker không cần 'sudo'.${NC}"
    fi
}

# --- Main Script ---
clear
echo "====================================================="
echo "   Cài đặt wireguard-ui (ngoduykhanh) bằng Docker   "
echo "====================================================="
echo

# Bước 1: Cài đặt Docker
install_docker

# Bước 2: Tạo thư mục và cấu hình
echo -e "\n${BLUE}▶️ Bước 2: Chuẩn bị thư mục và file cấu hình...${NC}"
mkdir -p ~/wireguard-ui-docker
cd ~/wireguard-ui-docker
echo -e "Đã tạo thư mục tại: ${YELLOW}$(pwd)${NC}"

# Bước 3: Lấy thông tin cấu hình từ người dùng
echo -e "\n${BLUE}▶️ Bước 3: Cấu hình đăng nhập cho giao diện web...${NC}"
read -p "Nhập username bạn muốn dùng để đăng nhập: " WGUI_USERNAME
read -sp "Nhập password bạn muốn dùng để đăng nhập: " WGUI_PASSWORD
echo

# Bước 4: Tạo file docker-compose.yml
echo -e "\n${BLUE}▶️ Bước 4: Tạo file docker-compose.yml...${NC}"
cat << EOF > docker-compose.yml
version: "3.8"
services:
  wireguard-ui:
    image: ngoduykhanh/wireguard-ui:latest
    container_name: wireguard-ui
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - WGUI_USERNAME=${WGUI_USERNAME}
      - WGUI_PASSWORD=${WGUI_PASSWORD}
      - WGUI_MANAGE_START=true
      - WGUI_MANAGE_RESTART=true
    ports:
      - "5000:5000/tcp"
      - "51820:51820/udp"
    volumes:
      - ./etc-wireguard:/etc/wireguard
      - ./db:/db
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
EOF
echo -e "${GREEN}✅ File docker-compose.yml đã được tạo thành công!${NC}"

# Bước 5: Cấu hình Firewall
echo -e "\n${BLUE}▶️ Bước 5: Cấu hình firewall (UFW)...${NC}"
sudo ufw allow 5000/tcp comment 'WireGuard UI (Docker)'
sudo ufw allow 51820/udp comment 'WireGuard VPN (Docker)'
echo -e "${GREEN}✅ Đã mở port 5000/tcp (UI) và 51820/udp (VPN).${NC}"

# Hoàn tất
SERVER_IP=$(curl -s ifconfig.me)
echo -e "\n${GREEN}🎉 CÀI ĐẶT HOÀN TẤT! 🎉${NC}"
echo "--------------------------------------------------"
echo "Thực hiện các bước cuối cùng:"
echo
echo -e "1. Di chuyển vào thư mục cấu hình:"
echo -e "   ${BLUE}cd ~/wireguard-ui-docker${NC}"
echo
echo -e "2. Khởi chạy container:"
echo -e "   ${BLUE}docker compose up -d${NC}"
echo
echo -e "3. Truy cập giao diện web tại:"
echo -e "   URL:      ${YELLOW}http://${SERVER_IP}:5000${NC}"
echo -e "   Username: ${YELLOW}${WGUI_USERNAME}${NC}"
echo -e "   Password: ${YELLOW}(mật khẩu bạn đã nhập)${NC}"
echo
echo "Các lệnh quản lý container:"
echo -e "   - Xem logs:       ${BLUE}docker compose logs -f${NC}"
echo -e "   - Dừng:            ${BLUE}docker compose down${NC}"
echo -e "   - Khởi động lại:   ${BLUE}docker compose restart${NC}"
echo "--------------------------------------------------"
