#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
BACKUP_DIR="/opt/proxmox-config-backup"
CONFIG_DIRS=(
    "/etc/pve"
    "/etc/network"
    "/etc/systemd/network"
    "/etc/hosts"
    "/etc/hostname"
    "/etc/resolv.conf"
    "/etc/postfix"
    "/etc/ssh"
    "/etc/cron.d"
    "/etc/crontab"
)

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
    echo -e "${BLUE}  Proxmox Config Backup Tool${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

# Check if running on Proxmox
check_proxmox() {
    if ! command -v pveversion &> /dev/null; then
        print_error "Script ini hanya untuk Proxmox VE!"
        exit 1
    fi
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        echo "Gunakan: sudo $0"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    if [[ ! -d $BACKUP_DIR ]]; then
        mkdir -p $BACKUP_DIR
        print_status "Direktori backup dibuat: $BACKUP_DIR"
    fi
}

# Backup configurations
backup_configs() {
    print_status "Membackup konfigurasi Proxmox..."
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
    
    mkdir -p "$BACKUP_PATH"
    
    # Backup each directory/file
    for item in "${CONFIG_DIRS[@]}"; do
        if [[ -e "$item" ]]; then
            ITEM_NAME=$(basename "$item")
            if [[ -d "$item" ]]; then
                print_status "Backup direktori: $item"
                cp -r "$item" "$BACKUP_PATH/$ITEM_NAME"
            else
                print_status "Backup file: $item"
                cp "$item" "$BACKUP_PATH/$ITEM_NAME"
            fi
        else
            print_warning "Item tidak ditemukan: $item"
        fi
    done
    
    # Backup VM/CT configurations
    if [[ -d "/etc/pve/qemu-server" ]]; then
        print_status "Backup konfigurasi VM..."
        mkdir -p "$BACKUP_PATH/qemu-server"
        cp /etc/pve/qemu-server/*.conf "$BACKUP_PATH/qemu-server/" 2>/dev/null || true
    fi
    
    if [[ -d "/etc/pve/lxc" ]]; then
        print_status "Backup konfigurasi Container..."
        mkdir -p "$BACKUP_PATH/lxc"
        cp /etc/pve/lxc/*.conf "$BACKUP_PATH/lxc/" 2>/dev/null || true
    fi
    
    # Backup storage configuration
    if [[ -f "/etc/pve/storage.cfg" ]]; then
        print_status "Backup konfigurasi storage..."
        cp /etc/pve/storage.cfg "$BACKUP_PATH/"
    fi
    
    # Create archive
    cd "$BACKUP_DIR"
    tar -czf "proxmox_config_$TIMESTAMP.tar.gz" "backup_$TIMESTAMP"
    rm -rf "backup_$TIMESTAMP"
    
    print_status "Backup selesai: proxmox_config_$TIMESTAMP.tar.gz"
    
    # Keep only last 10 backups
    ls -t proxmox_config_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null || true
}

# Restore configurations
restore_configs() {
    echo "Daftar backup yang tersedia:"
    ls -la "$BACKUP_DIR"/proxmox_config_*.tar.gz 2>/dev/null || {
        print_error "Tidak ada backup yang ditemukan!"
        exit 1
    }
    
    echo
    read -p "Masukkan nama file backup (tanpa path): " BACKUP_FILE
    
    if [[ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]]; then
        print_error "File backup tidak ditemukan!"
        exit 1
    fi
    
    print_warning "PERINGATAN: Ini akan menimpa konfigurasi yang ada!"
    read -p "Lanjutkan restore? [y/N]: " confirm
    
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        print_status "Restore dibatalkan."
        exit 0
    fi
    
    print_status "Memulai restore dari: $BACKUP_FILE"
    
    # Extract backup
    cd "$BACKUP_DIR"
    tar -xzf "$BACKUP_FILE"
    
    EXTRACT_DIR=$(ls -d backup_* | head -1)
    
    # Restore configurations
    for item in "${CONFIG_DIRS[@]}"; do
        ITEM_NAME=$(basename "$item")
        if [[ -e "$EXTRACT_DIR/$ITEM_NAME" ]]; then
            print_status "Restore: $item"
            if [[ -d "$EXTRACT_DIR/$ITEM_NAME" ]]; then
                rm -rf "$item" 2>/dev/null || true
                cp -r "$EXTRACT_DIR/$ITEM_NAME" "$item"
            else
                cp "$EXTRACT_DIR/$ITEM_NAME" "$item"
            fi
        fi
    done
    
    # Restore VM/CT configs
    if [[ -d "$EXTRACT_DIR/qemu-server" ]]; then
        print_status "Restore konfigurasi VM..."
        cp "$EXTRACT_DIR/qemu-server"/*.conf /etc/pve/qemu-server/ 2>/dev/null || true
    fi
    
    if [[ -d "$EXTRACT_DIR/lxc" ]]; then
        print_status "Restore konfigurasi Container..."
        cp "$EXTRACT_DIR/lxc"/*.conf /etc/pve/lxc/ 2>/dev/null || true
    fi
    
    # Restore storage config
    if [[ -f "$EXTRACT_DIR/storage.cfg" ]]; then
        print_status "Restore konfigurasi storage..."
        cp "$EXTRACT_DIR/storage.cfg" /etc/pve/
    fi
    
    # Cleanup
    rm -rf "$EXTRACT_DIR"
    
    print_status "Restore selesai!"
    print_warning "Restart layanan Proxmox untuk menerapkan perubahan."
}

# Auto backup on reboot
setup_auto_backup() {
    print_status "Mengatur auto backup saat startup..."
    
    # Create systemd service
    cat > /etc/systemd/system/proxmox-config-backup.service << 'EOF'
[Unit]
Description=Proxmox Configuration Auto Backup
After=pve-cluster.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/proxmox-backup backup
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create cron job for daily backup
    cat > /etc/cron.d/proxmox-backup << 'EOF'
# Proxmox daily backup at 2 AM
0 2 * * * root /usr/local/bin/proxmox-backup backup >/dev/null 2>&1
EOF

    # Copy script to system location
    cp "$0" /usr/local/bin/proxmox-backup
    chmod +x /usr/local/bin/proxmox-backup
    
    # Enable service
    systemctl daemon-reload
    systemctl enable proxmox-config-backup.service
    
    print_status "Auto backup telah dikonfigurasi:"
    echo "  - Backup otomatis saat startup"
    echo "  - Backup harian jam 2 pagi"
    echo "  - Script tersimpan di: /usr/local/bin/proxmox-backup"
}

# Monitor config changes
monitor_configs() {
    print_status "Mengatur monitoring perubahan config..."
    
    # Install inotify-tools if not present
    if ! command -v inotifywait &> /dev/null; then
        apt update && apt install -y inotify-tools
    fi
    
    # Create monitoring service
    cat > /etc/systemd/system/proxmox-config-monitor.service << 'EOF'
[Unit]
Description=Proxmox Configuration Monitor
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/proxmox-config-monitor.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create monitoring script
    cat > /usr/local/bin/proxmox-config-monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/proxmox-config-monitor.log"

echo "$(date): Proxmox Config Monitor started" >> $LOG_FILE

inotifywait -m -r -e modify,create,delete,move \
    /etc/pve \
    /etc/network \
    --format '%w%f %e %T' \
    --timefmt '%Y-%m-%d %H:%M:%S' | \
while read file event time; do
    echo "$time: $event detected on $file" >> $LOG_FILE
    # Auto backup on important changes
    if [[ $file == *"/etc/pve/"* ]] || [[ $file == *"/etc/network/"* ]]; then
        /usr/local/bin/proxmox-backup backup-silent
    fi
done
EOF

    chmod +x /usr/local/bin/proxmox-config-monitor.sh
    
    systemctl daemon-reload
    systemctl enable proxmox-config-monitor.service
    systemctl start proxmox-config-monitor.service
    
    print_status "Monitoring config aktif!"
}

# Silent backup (for automated calls)
backup_silent() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_PATH="$BACKUP_DIR/auto_backup_$TIMESTAMP"
    
    mkdir -p "$BACKUP_PATH"
    
    for item in "${CONFIG_DIRS[@]}"; do
        if [[ -e "$item" ]]; then
            ITEM_NAME=$(basename "$item")
            if [[ -d "$item" ]]; then
                cp -r "$item" "$BACKUP_PATH/$ITEM_NAME" 2>/dev/null || true
            else
                cp "$item" "$BACKUP_PATH/$ITEM_NAME" 2>/dev/null || true
            fi
        fi
    done
    
    cd "$BACKUP_DIR"
    tar -czf "auto_backup_$TIMESTAMP.tar.gz" "auto_backup_$TIMESTAMP" 2>/dev/null
    rm -rf "auto_backup_$TIMESTAMP"
    
    # Keep only last 5 auto backups
    ls -t auto_backup_*.tar.gz | tail -n +6 | xargs rm -f 2>/dev/null || true
}

# Show backup status
show_status() {
    print_header
    
    echo "=== Status Backup ==="
    if [[ -d $BACKUP_DIR ]]; then
        echo "Direktori backup: $BACKUP_DIR"
        echo "Jumlah backup manual: $(ls $BACKUP_DIR/proxmox_config_*.tar.gz 2>/dev/null | wc -l)"
        echo "Jumlah auto backup: $(ls $BACKUP_DIR/auto_backup_*.tar.gz 2>/dev/null | wc -l)"
        echo
        echo "Backup terbaru:"
        ls -la "$BACKUP_DIR"/*.tar.gz | head -5
    else
        echo "Belum ada backup"
    fi
    
    echo
    echo "=== Status Service ==="
    systemctl is-enabled proxmox-config-backup.service 2>/dev/null && echo "Auto backup: ENABLED" || echo "Auto backup: DISABLED"
    systemctl is-active proxmox-config-monitor.service 2>/dev/null && echo "Config monitor: RUNNING" || echo "Config monitor: STOPPED"
}

# Main function
main() {
    check_proxmox
    create_backup_dir
    
    case ${1:-menu} in
        backup)
            backup_configs
            ;;
        backup-silent)
            backup_silent
            ;;
        restore)
            restore_configs
            ;;
        setup)
            setup_auto_backup
            ;;
        monitor)
            monitor_configs
            ;;
        status)
            show_status
            ;;
        menu|*)
            print_header
            echo "Pilihan yang tersedia:"
            echo "1) Backup manual"
            echo "2) Restore backup"
            echo "3) Setup auto backup"
            echo "4) Setup monitoring"
            echo "5) Lihat status"
            echo "0) Keluar"
            echo
            read -p "Pilihan [1]: " choice
            
            case $choice in
                1|"") backup_configs ;;
                2) restore_configs ;;
                3) setup_auto_backup ;;
                4) monitor_configs ;;
                5) show_status ;;
                0) exit 0 ;;
                *) print_error "Pilihan tidak valid!" ;;
            esac
            ;;
    esac
}

main "$@"