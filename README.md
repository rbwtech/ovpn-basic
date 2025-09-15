# OpenVPN Basic Auto Installer

Quick OpenVPN server setup untuk akses remote yang mudah dan cepat. Dibuat untuk kebutuhan development dan testing.

## Install

```bash
wget https://raw.githubusercontent.com/rbwtech/ovpn-basic/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## Supported OS

- Ubuntu 18.04+
- Debian 9+
- CentOS 7+

## Default Config

- Port: 1194
- Protocol: UDP
- DNS: Cloudflare (1.1.1.1)
- Encryption: AES-256-CBC

## Client Management

Tambah client baru:
```bash
ovpn-manage add
```

Hapus client:
```bash
ovpn-manage remove
```

Status server:
```bash
ovpn-manage status
```

## File Locations

- Server config: `/etc/openvpn/server.conf`
- Client configs: `/etc/openvpn/clients/`
- Certificates: `/etc/openvpn/easy-rsa/pki/`

## Quick Start

1. Run installer script
2. Follow prompts
3. Download `.ovpn` file from `/etc/openvpn/clients/`
4. Import to OpenVPN client app
5. Connect

## Notes

- Pastikan port terbuka di firewall
- File client berisi embedded certificates
- Auto-generates TLS auth key
- IP forwarding enabled otomatis

## Troubleshooting

Service tidak jalan:
```bash
systemctl status openvpn@server
journalctl -u openvpn@server
```

Cek koneksi:
```bash
cat /etc/openvpn/openvpn-status.log
```

Restart service:
```bash
systemctl restart openvpn@server
```

## License

MIT - gunakan bebas untuk project apapun.