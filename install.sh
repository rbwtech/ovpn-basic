#!/bin/bash

# OpenVPN Auto Installer Script
# For quick deployment and easy access
# Repository: https://github.com/rbwtech/ovpn-basic

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  OpenVPN Quick Setup Script${NC}"
    echo -e "${BLUE}  Repository: rbwtech/ovpn-basic${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        echo "Gunakan: sudo $0"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        print_status "Terdeteksi: Debian/Ubuntu"
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
        print_status "Terdeteksi: CentOS/RHEL"
    else
        print_error "OS tidak didukung!"
        exit 1
    fi
}

# Get server information
get_server_info() {
    echo
    print_status "Mengumpulkan informasi server..."
    
    # Get public IP
    PUBLIC_IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)
    if [[ -z $PUBLIC_IP ]]; then
        print_warning "Tidak bisa mendapatkan IP publik otomatis"
        read -p "Masukkan IP publik server: " PUBLIC_IP
    else
        print_status "IP Publik terdeteksi: $PUBLIC_IP"
        read -p "Konfirmasi IP publik [$PUBLIC_IP]: " ip_input
        if [[ -n $ip_input ]]; then
            PUBLIC_IP=$ip_input
        fi
    fi
    
    # Get server port
    echo
    read -p "Port OpenVPN [1194]: " VPN_PORT
    VPN_PORT=${VPN_PORT:-1194}
    
    # Get protocol
    echo
    echo "Pilih protokol:"
    echo "1) UDP (recommended)"
    echo "2) TCP"
    read -p "Pilihan [1]: " proto_choice
    case $proto_choice in
        2) VPN_PROTOCOL="tcp" ;;
        *) VPN_PROTOCOL="udp" ;;
    esac
    
    # Get client name
    echo
    read -p "Nama client [client1]: " CLIENT_NAME
    CLIENT_NAME=${CLIENT_NAME:-client1}
    
    # DNS servers
    echo
    echo "Pilih DNS server:"
    echo "1) Cloudflare (1.1.1.1)"
    echo "2) Google (8.8.8.8)"
    echo "3) Custom"
    read -p "Pilihan [1]: " dns_choice
    case $dns_choice in
        2) DNS1="8.8.8.8"; DNS2="8.8.4.4" ;;
        3) 
            read -p "DNS 1: " DNS1
            read -p "DNS 2: " DNS2
            ;;
        *) DNS1="1.1.1.1"; DNS2="1.0.0.1" ;;
    esac
}

# Install packages
install_packages() {
    print_status "Menginstall paket yang diperlukan..."
    
    if [[ $OS == "debian" ]]; then
        apt update -y
        apt install -y openvpn easy-rsa iptables-persistent curl
    elif [[ $OS == "centos" ]]; then
        yum update -y
        yum install -y epel-release
        yum install -y openvpn easy-rsa iptables-services curl
        systemctl enable iptables
    fi
}

# Setup Easy-RSA
setup_easyrsa() {
    print_status "Menyiapkan Easy-RSA..."
    
    cd /etc/openvpn/
    
    if [[ $OS == "debian" ]]; then
        cp -r /usr/share/easy-rsa/ ./
    elif [[ $OS == "centos" ]]; then
        cp -r /usr/share/easy-rsa/3/ ./easy-rsa
    fi
    
    cd easy-rsa/
    
    # Initialize PKI
    ./easyrsa init-pki
    
    # Build CA
    echo "set_var EASYRSA_BATCH \"1\"" > pki/vars
    echo "set_var EASYRSA_REQ_CN \"OpenVPN-CA\"" >> pki/vars
    
    ./easyrsa build-ca nopass
    
    # Generate server certificate
    ./easyrsa build-server-full server nopass
    
    # Generate client certificate
    ./easyrsa build-client-full $CLIENT_NAME nopass
    
    # Generate DH parameters
    ./easyrsa gen-dh
    
    # Generate TLS-Auth key
    openvpn --genkey --secret pki/ta.key
    
    print_status "Sertifikat berhasil dibuat!"
}

# Create server config
create_server_config() {
    print_status "Membuat konfigurasi server..."
    
    cat > /etc/openvpn/server.conf << EOF
port $VPN_PORT
proto $VPN_PROTOCOL
dev tun

ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
tls-auth /etc/openvpn/easy-rsa/pki/ta.key 0

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $DNS1"
push "dhcp-option DNS $DNS2"

keepalive 10 120
cipher AES-256-CBC
auth SHA256
comp-lzo
user nobody
group nogroup
persist-key
persist-tun

status openvpn-status.log
log openvpn.log
verb 3
explicit-exit-notify 1
EOF

    print_status "Konfigurasi server selesai!"
}

# Setup firewall
setup_firewall() {
    print_status "Mengkonfigurasi firewall..."
    
    # Enable IP forwarding (check if already exists)
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1
    
    # Get network interface
    NIC=$(ip route | grep default | awk '{print $5}' | head -1)
    print_status "Network interface: $NIC"
    
    # Setup iptables rules
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
    iptables -A INPUT -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT
    iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Save iptables rules
    if [[ $OS == "debian" ]]; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
    elif [[ $OS == "centos" ]]; then
        service iptables save
    fi
    
    print_status "Firewall dikonfigurasi!"
}

# Create client config
create_client_config() {
    print_status "Membuat konfigurasi client..."
    
    mkdir -p /etc/openvpn/clients
    
    cat > /etc/openvpn/clients/$CLIENT_NAME.ovpn << EOF
client
dev tun
proto $VPN_PROTOCOL
remote $PUBLIC_IP $VPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
comp-lzo
verb 3

<ca>
$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/easy-rsa/pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat /etc/openvpn/easy-rsa/pki/private/$CLIENT_NAME.key)
</key>

<tls-auth>
$(cat /etc/openvpn/easy-rsa/pki/ta.key)
</tls-auth>
key-direction 1
EOF

    print_status "File konfigurasi client: /etc/openvpn/clients/$CLIENT_NAME.ovpn"
}

# Start services
start_services() {
    print_status "Memulai layanan OpenVPN..."
    
    if [[ $OS == "debian" ]]; then
        systemctl enable openvpn@server
        systemctl start openvpn@server
    elif [[ $OS == "centos" ]]; then
        systemctl enable openvpn@server
        systemctl start openvpn@server
    fi
    
    # Check status
    if systemctl is-active --quiet openvpn@server; then
        print_status "OpenVPN server berhasil dijalankan!"
    else
        print_error "Gagal menjalankan OpenVPN server!"
        exit 1
    fi
}

# Create management script
create_management_script() {
    print_status "Membuat script manajemen..."
    
    cat > /usr/local/bin/ovpn-manage << 'EOF'
#!/bin/bash

EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_DIR="/etc/openvpn/clients"

add_client() {
    read -p "Nama client baru: " CLIENT_NAME
    if [[ -z $CLIENT_NAME ]]; then
        echo "Nama client tidak boleh kosong!"
        return 1
    fi
    
    cd $EASYRSA_DIR
    ./easyrsa build-client-full $CLIENT_NAME nopass
    
    # Get server info
    PUBLIC_IP=$(grep "remote " /etc/openvpn/server.conf | awk '{print $2}')
    VPN_PORT=$(grep "port " /etc/openvpn/server.conf | awk '{print $2}')
    VPN_PROTOCOL=$(grep "proto " /etc/openvpn/server.conf | awk '{print $2}')
    
    # Create client config
    cat > $CLIENT_DIR/$CLIENT_NAME.ovpn << EOFCLIENT
client
dev tun
proto $VPN_PROTOCOL
remote $PUBLIC_IP $VPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
comp-lzo
verb 3

<ca>
$(cat $EASYRSA_DIR/pki/ca.crt)
</ca>

<cert>
$(cat $EASYRSA_DIR/pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat $EASYRSA_DIR/pki/private/$CLIENT_NAME.key)
</key>

<tls-auth>
$(cat $EASYRSA_DIR/pki/ta.key)
</tls-auth>
key-direction 1
EOFCLIENT

    echo "Client $CLIENT_NAME berhasil ditambahkan!"
    echo "File konfigurasi: $CLIENT_DIR/$CLIENT_NAME.ovpn"
}

remove_client() {
    echo "Daftar client:"
    ls $CLIENT_DIR/*.ovpn 2>/dev/null | sed 's|.*/||;s|\.ovpn||' || echo "Tidak ada client"
    echo
    read -p "Nama client yang akan dihapus: " CLIENT_NAME
    
    if [[ -z $CLIENT_NAME ]]; then
        echo "Nama client tidak boleh kosong!"
        return 1
    fi
    
    cd $EASYRSA_DIR
    ./easyrsa revoke $CLIENT_NAME
    ./easyrsa gen-crl
    
    rm -f $CLIENT_DIR/$CLIENT_NAME.ovpn
    rm -f $EASYRSA_DIR/pki/issued/$CLIENT_NAME.crt
    rm -f $EASYRSA_DIR/pki/private/$CLIENT_NAME.key
    
    echo "Client $CLIENT_NAME berhasil dihapus!"
}

show_status() {
    echo "=== Status OpenVPN Server ==="
    systemctl status openvpn@server --no-pager
    echo
    echo "=== Connected Clients ==="
    cat /etc/openvpn/openvpn-status.log 2>/dev/null | grep "CLIENT_LIST" || echo "Tidak ada client terhubung"
}

case $1 in
    add)
        add_client
        ;;
    remove)
        remove_client
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {add|remove|status}"
        echo "  add    - Tambah client baru"
        echo "  remove - Hapus client"
        echo "  status - Lihat status server"
        ;;
esac
EOF

    chmod +x /usr/local/bin/ovpn-manage
    print_status "Script manajemen dibuat: ovpn-manage"
}

# Main installation function
main() {
    print_header
    
    print_status "Memulai instalasi OpenVPN..."
    echo
    
    check_root
    detect_os
    get_server_info
    
    echo
    print_status "Informasi yang akan digunakan:"
    echo "  IP Publik: $PUBLIC_IP"
    echo "  Port: $VPN_PORT"
    echo "  Protokol: $VPN_PROTOCOL"
    echo "  Client: $CLIENT_NAME"
    echo "  DNS: $DNS1, $DNS2"
    echo
    
    read -p "Lanjutkan instalasi? [y/N]: " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        print_warning "Instalasi dibatalkan."
        exit 0
    fi
    
    install_packages
    setup_easyrsa
    create_server_config
    setup_firewall
    create_client_config
    start_services
    create_management_script
    
    echo
    print_status "================================"
    print_status "  INSTALASI SELESAI!"
    print_status "================================"
    echo
    print_status "File konfigurasi client tersedia di:"
    echo "  /etc/openvpn/clients/$CLIENT_NAME.ovpn"
    echo
    print_status "Untuk mengelola client, gunakan:"
    echo "  ovpn-manage add     - Tambah client"
    echo "  ovpn-manage remove  - Hapus client"
    echo "  ovpn-manage status  - Lihat status"
    echo
    print_status "Download file .ovpn ke device Anda dan import ke aplikasi OpenVPN client."
    print_warning "Pastikan port $VPN_PORT/$VPN_PROTOCOL terbuka di firewall!"
    echo
}

# Run main function
main "$@"