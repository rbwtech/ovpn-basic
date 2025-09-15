#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [[ $EUID -ne 0 ]]; then
    print_error "Script ini harus dijalankan sebagai root!"
    echo "Gunakan: sudo $0"
    exit 1
fi

print_warning "Script ini akan menghapus SEMUA konfigurasi OpenVPN!"
read -p "Lanjutkan? [y/N]: " confirm
if [[ $confirm != "y" && $confirm != "Y" ]]; then
    print_status "Dibatalkan."
    exit 0
fi

print_status "Menghentikan layanan OpenVPN..."
systemctl stop openvpn@server 2>/dev/null || true
systemctl disable openvpn@server 2>/dev/null || true
systemctl stop openvpn 2>/dev/null || true
systemctl disable openvpn 2>/dev/null || true

print_status "Menghapus paket OpenVPN..."
apt purge -y openvpn easy-rsa 2>/dev/null || true
apt autoremove -y 2>/dev/null || true

print_status "Menghapus direktori konfigurasi..."
rm -rf /etc/openvpn/
rm -rf /var/log/openvpn/
rm -rf /run/openvpn/
rm -rf /usr/share/easy-rsa/

print_status "Menghapus script management..."
rm -f /usr/local/bin/ovpn-manage

print_status "Membersihkan iptables rules..."
NIC=$(ip route | grep default | awk '{print $5}' | head -1)

iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE 2>/dev/null || true
iptables -D INPUT -p udp --dport 1194 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --dport 1194 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

if command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

print_status "Membersihkan systemd services..."
systemctl daemon-reload

print_status "Menghapus sysctl config..."
sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf 2>/dev/null || true

print_status "Membersihkan network config..."

ip link delete tun0 2>/dev/null || true

print_status "Membersihkan log files..."
rm -f /var/log/openvpn*.log
rm -f /etc/openvpn*.log

print_status "Update package database..."
apt update

echo
print_status "================================"
print_status "  UNINSTALL SELESAI!"
print_status "================================"
echo
print_status "OpenVPN telah dihapus sepenuhnya dari sistem."
print_status "Anda bisa menjalankan install.sh untuk fresh install."
echo
print_warning "Reboot sistem untuk memastikan semua perubahan diterapkan:"
echo "  sudo reboot"