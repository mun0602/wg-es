#!/bin/bash

# Script tự động cài đặt WireGuard với wg-easy trên Ubuntu
# Tác giả: Auto Install Script
# Phiên bản: 1.0

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Hàm hiển thị thông báo
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script này cần chạy với quyền root. Vui lòng chạy: sudo $0"
        exit 1
    fi
}

# Kiểm tra hệ điều hành
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Không thể xác định hệ điều hành"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "Script này chỉ hỗ trợ Ubuntu"
        exit 1
    fi
    
    print_success "Phát hiện Ubuntu $VERSION_ID"
}

# Cài đặt Docker
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker đã được cài đặt"
        return
    fi
    
    print_status "Đang cài đặt Docker..."
    
    # Cập nhật package index
    apt-get update
    
    # Cài đặt các package cần thiết
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Thêm Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Thêm Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Cài đặt Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Khởi động Docker service
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker đã được cài đặt thành công"
}

# Cài đặt Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose đã được cài đặt"
        return
    fi
    
    print_status "Đang cài đặt Docker Compose..."
    
    # Tải Docker Compose
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Cấp quyền thực thi
    chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker Compose đã được cài đặt thành công"
}

# Tạo bcrypt hash cho mật khẩu
generate_password_hash() {
    local password="$1"
    print_status "Đang tạo bcrypt hash cho mật khẩu..."
    
    # Sử dụng Docker để tạo bcrypt hash
    PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy:latest node -e "const bcrypt = require('bcryptjs'); const hash = bcrypt.hashSync('$password', 10); console.log(hash.replace(/\$/g, '\$\$'));")
    
    if [[ -z "$PASSWORD_HASH" ]]; then
        print_error "Không thể tạo bcrypt hash cho mật khẩu"
        exit 1
    fi
    
    print_success "Đã tạo bcrypt hash thành công"
}

# Lấy thông tin từ người dùng
get_user_input() {
    echo
    print_status "Cấu hình WireGuard"
    echo
    
    # Tên container
    read -p "Nhập tên container (mặc định: wg-easy): " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-wg-easy}
    
    # Cổng WireGuard
    read -p "Nhập cổng WireGuard (mặc định: 51820): " WG_PORT
    WG_PORT=${WG_PORT:-51820}
    
    # Cổng Web UI
    read -p "Nhập cổng Web UI (mặc định: 51821): " WEB_PORT
    WEB_PORT=${WEB_PORT:-51821}
    
    # Mật khẩu admin
    read -s -p "Nhập mật khẩu admin: " ADMIN_PASSWORD
    echo
    
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        print_error "Mật khẩu admin không được để trống"
        exit 1
    fi
    
    # Tạo bcrypt hash cho mật khẩu
    generate_password_hash "$ADMIN_PASSWORD"
    
    # Lấy IP công khai
    print_status "Đang lấy địa chỉ IP công khai..."
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    
    if [[ -z "$PUBLIC_IP" ]]; then
        read -p "Không thể tự động lấy IP công khai. Vui lòng nhập IP hoặc domain: " PUBLIC_IP
    fi
    
    print_success "Sử dụng địa chỉ: $PUBLIC_IP"
}

# Tạo docker-compose.yml
create_docker_compose() {
    print_status "Đang tạo file docker-compose.yml..."
    
    mkdir -p /opt/wireguard
    cd /opt/wireguard
    
    cat > docker-compose.yml << EOF
services:
  ${CONTAINER_NAME}:
    image: 'ghcr.io/wg-easy/wg-easy:latest'
    container_name: ${CONTAINER_NAME}
    environment:
      - WG_HOST=${PUBLIC_IP}
      - PASSWORD_HASH=${PASSWORD_HASH}
      - WG_PORT=${WG_PORT}
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=1.1.1.1
      - WG_ALLOWED_IPS=0.0.0.0/0
      - LANG=vi
    volumes:
      - wg-easy-data:/etc/wireguard
    ports:
      - '${WG_PORT}:51820/udp'
      - '${WEB_PORT}:51821/tcp'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    networks:
      - wg-network

volumes:
  wg-easy-data:
    driver: local

networks:
  wg-network:
    driver: bridge
EOF
    
    print_success "File docker-compose.yml đã được tạo tại /opt/wireguard/"
}

# Cấu hình firewall
setup_firewall() {
    print_status "Đang cấu hình firewall..."
    
    # Cài đặt ufw nếu chưa có
    if ! command -v ufw &> /dev/null; then
        apt-get install -y ufw
    fi
    
    # Cấu hình ufw
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Cho phép SSH
    ufw allow ssh
    
    # Cho phép cổng WireGuard và Web UI
    ufw allow ${WG_PORT}/udp
    ufw allow ${WEB_PORT}/tcp
    
    # Kích hoạt firewall
    ufw --force enable
    
    print_success "Firewall đã được cấu hình"
}

# Kiểm tra container đã tồn tại
check_existing_container() {
    if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_warning "Container '${CONTAINER_NAME}' đã tồn tại!"
        echo
        echo "Lựa chọn:"
        echo "1) Xóa container cũ và cài đặt lại"
        echo "2) Giữ nguyên và thoát"
        echo "3) Chỉ khởi động lại container hiện tại"
        echo
        read -p "Nhập lựa chọn (1-3): " choice
        
        case $choice in
            1)
                print_status "Đang xóa container cũ..."
                docker stop ${CONTAINER_NAME} 2>/dev/null || true
                docker rm ${CONTAINER_NAME} 2>/dev/null || true
                
                # Xóa volume nếu người dùng muốn
                read -p "Bạn có muốn xóa dữ liệu cũ (volume) không? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    docker volume rm wg-easy-data 2>/dev/null || true
                    print_success "Đã xóa dữ liệu cũ"
                fi
                
                print_success "Đã xóa container cũ, tiếp tục cài đặt..."
                return 0
                ;;
            2)
                print_status "Giữ nguyên container hiện tại và thoát"
                exit 0
                ;;
            3)
                print_status "Khởi động lại container hiện tại..."
                docker restart ${CONTAINER_NAME}
                if docker ps --format "table {{.Names}}\t{{.Status}}" | grep "^${CONTAINER_NAME}" | grep -q "Up"; then
                    print_success "Container đã được khởi động lại thành công"
                    show_existing_container_info
                else
                    print_error "Không thể khởi động lại container"
                fi
                exit 0
                ;;
            *)
                print_error "Lựa chọn không hợp lệ"
                exit 1
                ;;
        esac
    fi
}

# Hiển thị thông tin container đã tồn tại
show_existing_container_info() {
    echo
    print_success "=== THÔNG TIN CONTAINER HIỆN TẠI ==="
    
    # Lấy thông tin container
    CONTAINER_INFO=$(docker inspect ${CONTAINER_NAME} 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        # Lấy cổng từ container
        WG_PORT_CURRENT=$(echo "$CONTAINER_INFO" | grep -o '"51820/udp"' -A 5 -B 5 | grep -o '"[0-9]*"' | head -1 | tr -d '"')
        WEB_PORT_CURRENT=$(echo "$CONTAINER_INFO" | grep -o '"51821/tcp"' -A 5 -B 5 | grep -o '"[0-9]*"' | head -1 | tr -d '"')
        
        # Lấy IP từ biến môi trường
        WG_HOST_CURRENT=$(docker exec ${CONTAINER_NAME} printenv WG_HOST 2>/dev/null || echo "Không xác định")
        
        echo -e "${GREEN}Container:${NC} ${CONTAINER_NAME}"
        echo -e "${GREEN}Trạng thái:${NC} $(docker ps --format "table {{.Status}}" --filter "name=${CONTAINER_NAME}" | tail -1)"
        echo -e "${GREEN}Web UI:${NC} http://${WG_HOST_CURRENT}:${WEB_PORT_CURRENT:-51821}"
        echo -e "${GREEN}Cổng WireGuard:${NC} ${WG_PORT_CURRENT:-51820}/udp"
        echo
        echo -e "${YELLOW}Lệnh quản lý:${NC}"
        echo "  docker restart ${CONTAINER_NAME}  - Khởi động lại"
        echo "  docker logs ${CONTAINER_NAME}     - Xem log"
        echo "  docker stop ${CONTAINER_NAME}     - Dừng container"
    fi
    echo
}

# Khởi động WireGuard
start_wireguard() {
    print_status "Đang khởi động WireGuard..."
    
    cd /opt/wireguard
    
    # Dừng container cũ nếu có
    docker-compose down 2>/dev/null || true
    
    # Khởi động container
    docker-compose up -d
    
    # Chờ container khởi động
    sleep 10
    
    # Kiểm tra trạng thái
    if docker-compose ps | grep -q "Up"; then
        print_success "WireGuard đã được khởi động thành công"
    else
        print_error "Có lỗi khi khởi động WireGuard"
        docker-compose logs
        exit 1
    fi
}

# Tạo script quản lý
create_management_script() {
    print_status "Đang tạo script quản lý..."
    
    cat > /usr/local/bin/wg-manager << 'EOF'
#!/bin/bash

WG_DIR="/opt/wireguard"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

case "$1" in
    start)
        print_status "Khởi động WireGuard..."
        cd $WG_DIR && docker-compose up -d
        ;;
    stop)
        print_status "Dừng WireGuard..."
        cd $WG_DIR && docker-compose down
        ;;
    restart)
        print_status "Khởi động lại WireGuard..."
        cd $WG_DIR && docker-compose restart
        ;;
    status)
        print_status "Trạng thái WireGuard:"
        cd $WG_DIR && docker-compose ps
        echo
        print_status "Chi tiết container:"
        docker ps --filter "name=wg-easy" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    logs)
        print_status "Log WireGuard:"
        cd $WG_DIR && docker-compose logs -f
        ;;
    update)
        print_status "Cập nhật WireGuard..."
        cd $WG_DIR && docker-compose pull && docker-compose up -d
        ;;
    remove)
        print_warning "Xóa WireGuard container và dữ liệu"
        echo "Lựa chọn:"
        echo "1) Chỉ xóa container (giữ dữ liệu)"
        echo "2) Xóa container và dữ liệu"
        echo "3) Hủy"
        read -p "Nhập lựa chọn (1-3): " choice
        
        case $choice in
            1)
                print_status "Đang xóa container..."
                cd $WG_DIR && docker-compose down
                print_success "Đã xóa container, dữ liệu được giữ lại"
                ;;
            2)
                print_status "Đang xóa container và dữ liệu..."
                cd $WG_DIR && docker-compose down -v
                print_success "Đã xóa container và dữ liệu"
                ;;
            3)
                print_status "Hủy thao tác"
                ;;
            *)
                print_error "Lựa chọn không hợp lệ"
                ;;
        esac
        ;;
    reinstall)
        print_warning "Cài đặt lại WireGuard"
        read -p "Bạn có chắc chắn muốn cài đặt lại? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Đang cài đặt lại..."
            cd $WG_DIR && docker-compose down
            docker-compose pull
            docker-compose up -d
            print_success "Đã cài đặt lại WireGuard"
        else
            print_status "Hủy cài đặt lại"
        fi
        ;;
    backup)
        print_status "Sao lưu cấu hình WireGuard..."
        BACKUP_FILE="/tmp/wireguard-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        docker run --rm -v wg-easy-data:/data -v /tmp:/backup alpine tar czf /backup/$(basename $BACKUP_FILE) -C /data .
        print_success "Đã sao lưu vào: $BACKUP_FILE"
        ;;
    info)
        print_status "Thông tin WireGuard:"
        if docker ps --filter "name=wg-easy" --format "table {{.Names}}" | grep -q "wg-easy"; then
            CONTAINER_INFO=$(docker inspect wg-easy 2>/dev/null)
            WG_HOST=$(docker exec wg-easy printenv WG_HOST 2>/dev/null || echo "Không xác định")
            WG_PORT=$(docker port wg-easy 51820/udp 2>/dev/null | cut -d: -f2 || echo "51820")
            WEB_PORT=$(docker port wg-easy 51821/tcp 2>/dev/null | cut -d: -f2 || echo "51821")
            
            echo -e "${GREEN}Container:${NC} wg-easy"
            echo -e "${GREEN}Trạng thái:${NC} $(docker ps --format "table {{.Status}}" --filter "name=wg-easy" | tail -1)"
            echo -e "${GREEN}Web UI:${NC} http://${WG_HOST}:${WEB_PORT}"
            echo -e "${GREEN}Cổng WireGuard:${NC} ${WG_PORT}/udp"
            echo -e "${GREEN}Thư mục cấu hình:${NC} $WG_DIR"
        else
            print_warning "Container WireGuard không tồn tại hoặc đã dừng"
        fi
        ;;
    *)
        echo "WireGuard Manager - Công cụ quản lý WireGuard"
        echo
        echo "Sử dụng: $0 {command}"
        echo
        echo "Các lệnh có sẵn:"
        echo "  start     - Khởi động WireGuard"
        echo "  stop      - Dừng WireGuard"
        echo "  restart   - Khởi động lại WireGuard"
        echo "  status    - Xem trạng thái"
        echo "  logs      - Xem log (Ctrl+C để thoát)"
        echo "  update    - Cập nhật WireGuard"
        echo "  remove    - Xóa container/dữ liệu"
        echo "  reinstall - Cài đặt lại WireGuard"
        echo "  backup    - Sao lưu cấu hình"
        echo "  info      - Hiển thị thông tin chi tiết"
        echo
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/wg-manager
    
    print_success "Script quản lý đã được tạo tại /usr/local/bin/wg-manager"
}

# Hiển thị thông tin hoàn thành
show_completion_info() {
    echo
    print_success "=== CÀI ĐẶT HOÀN TẤT ==="
    echo
    echo -e "${GREEN}Web UI:${NC} http://${PUBLIC_IP}:${WEB_PORT}"
    echo -e "${GREEN}Mật khẩu:${NC} ${ADMIN_PASSWORD}"
    echo -e "${GREEN}Cổng WireGuard:${NC} ${WG_PORT}/udp"
    echo
    echo -e "${YELLOW}Các lệnh quản lý:${NC}"
    echo "  wg-manager start     - Khởi động WireGuard"
    echo "  wg-manager stop      - Dừng WireGuard"
    echo "  wg-manager restart   - Khởi động lại WireGuard"
    echo "  wg-manager status    - Xem trạng thái"
    echo "  wg-manager logs      - Xem log"
    echo "  wg-manager update    - Cập nhật WireGuard"
    echo "  wg-manager remove    - Xóa container/dữ liệu"
    echo "  wg-manager reinstall - Cài đặt lại WireGuard"
    echo "  wg-manager backup    - Sao lưu cấu hình"
    echo "  wg-manager info      - Hiển thị thông tin chi tiết"
    echo
    echo -e "${YELLOW}File cấu hình:${NC} /opt/wireguard/docker-compose.yml"
    echo
    print_warning "Hãy truy cập Web UI để tạo và quản lý các client WireGuard"
    echo
}

# Hàm main
main() {
    echo
    echo "================================================"
    echo "    Script Tự Động Cài Đặt WireGuard Ubuntu    "
    echo "================================================"
    echo
    
    check_root
    check_os
    install_docker
    install_docker_compose
    get_user_input
    check_existing_container
    create_docker_compose
    setup_firewall
    start_wireguard
    create_management_script
    show_completion_info
}

# Chạy script
main "$@"
