# forgejo-manager

Lightweight Forgejo deployment / backup / restore manager for Docker environments.

Designed for:
- self-hosted internal Git
- small teams
- offline / LAN environments
- WSL2 and Linux servers
- low-maintenance deployments

## Features

- Deploy Forgejo with Docker
- Interactive and non-interactive workflows
- Backup and restore support
- Upgrade workflow with automatic pre-upgrade backup
- Existing configuration preservation
- WSL-friendly path handling
- Linux and WSL deployment modes
- SQLite-based persistent setup

## Requirements

- Linux or WSL2
- Docker
- Bash

## Quick Start

Interactive deployment:

```bash
./forgejo-manager.sh deploy
```

Linux server deployment:

```bash
./forgejo-manager.sh deploy -y \
  --mode linux \
  --external-host 192.168.1.10 \
  --external-port 3000
```

WSL deployment:

```bash
./forgejo-manager.sh deploy -y \
  --mode wsl \
  --external-host 192.168.137.1 \
  --external-port 3001
```

## Commands

### Deploy

```bash
./forgejo-manager.sh deploy
```

### Backup

```bash
./forgejo-manager.sh backup
```

### Restore

Interactive restore:

```bash
./forgejo-manager.sh restore
```

Direct restore:

```bash
./forgejo-manager.sh restore \
  --backup ~/forgejo-backups/forgejo-backup-YYYYMMDD-HHMMSS.tar.gz
```

### Upgrade

```bash
./forgejo-manager.sh upgrade
```

Creates a pre-upgrade backup automatically before pulling newer images.

### Status

```bash
./forgejo-manager.sh status
```

### WSL Portproxy Helper

```bash
./forgejo-manager.sh portproxy-info
```

Displays example Windows `portproxy` commands for exposing WSL services to LAN.

## Notes

Default configuration targets offline/internal network usage:

- SQLite
- registration disabled
- SSH disabled
- offline mode enabled
- update checker disabled

The script does not automatically configure Windows `portproxy`.

Typical WSL LAN exposure example:

```powershell
netsh interface portproxy add v4tov4 `
  listenaddress=192.168.137.1 `
  listenport=3001 `
  connectaddress=<WSL_IP> `
  connectport=3000
```

## License

MIT

## Disclaimer

This project is not affiliated with Forgejo.

Forgejo is a trademark of its respective owners.