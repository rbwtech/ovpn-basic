#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BACKUP_DIR="/opt/system-backup"

CONFIG_TO_BACKUP=(
    "/etc"
    "/home"
    "/root"
    "/var/log"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        exit 1
    fi
}

do_backup() {
    check_root
    
    print_status "Memulai backup konfigurasi sistem..."
    mkdir -p "$BACKUP_DIR"
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/system_config_$TIMESTAMP.tar.gz"
    
    print_status "File backup akan disimpan di: $BACKUP_FILE"

    tar -czf "$BACKUP_FILE" "${CONFIG_TO_BACKUP[@]}"
    
    if [[ $? -eq 0 ]]; then
        print_status "Backup berhasil dibuat!"
    else
        print_error "Backup gagal!"
        exit 1
    fi
    
    print_status "Menghapus backup lama (menyimpan 7 terakhir)..."
    ls -t "$BACKUP_DIR"/system_config_*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null || true
    
    print_status "Proses selesai."
}

do_restore() {
    check_root
    
    echo "Daftar backup yang tersedia di $BACKUP_DIR:"
    ls -1 "$BACKUP_DIR"/system_config_*.tar.gz 2>/dev/null || { print_error "Tidak ada backup ditemukan!"; exit 1; }
    
    echo
    read -p "Masukkan nama file backup lengkap untuk restore: " RESTORE_FILE
    
    if [[ ! -f "$RESTORE_FILE" ]]; then
        print_error "File backup tidak ditemukan!"
        exit 1
    fi
    
    print_warning "PERINGATAN: Ini akan menimpa semua file konfigurasi yang ada!"
    read -p "Anda yakin ingin melanjutkan? [ketik 'YA' untuk konfirmasi]: " confirm
    
    if [[ "$confirm" != "YA" ]]; then
        print_status "Restore dibatalkan."
        exit 0
    fi
    
    print_status "Memulai restore dari file: $RESTORE_FILE"
    tar -xzf "$RESTORE_FILE" -C /
    
    print_status "Restore selesai!"
    print_warning "Disarankan untuk me-reboot sistem."
}

main() {
    case $1 in
        backup)
            do_backup
            ;;
        restore)
            do_restore
            ;;
        *)
            echo "Usage: $0 {backup|restore}"
            echo "  backup  - Membuat backup baru dari konfigurasi sistem."
            echo "  restore - Mengembalikan sistem dari file backup."
            ;;
    esac
}

main "$@"