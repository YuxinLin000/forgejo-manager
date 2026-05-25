# forgejo-manager

Simple Forgejo deployment / backup / restore manager for WSL + Docker environments.

Designed for:
- small internal teams
- offline / LAN setups
- Windows + WSL workflows
- lightweight self-hosted Git infrastructure

## Features

- Deploy Forgejo with Docker
- Persistent SQLite-based setup
- Backup and restore support
- Interactive and non-interactive modes
- Existing configuration preservation
- Automatic secret generation
- WSL-friendly path handling

## Requirements

- Ubuntu WSL2
- Docker
- Bash

## Deploy

Interactive:

```bash
./forgejo-manager.sh deploy
````

Non-interactive:

```bash
./forgejo-manager.sh deploy -y \
  --external-host 192.168.137.1 \
  --external-port 3001
```

## Backup

```bash
./forgejo-manager.sh backup
```

## Restore

Interactive restore:

```bash
./forgejo-manager.sh restore
```

Direct restore:

```bash
./forgejo-manager.sh restore \
  --backup ~/forgejo-backups/forgejo-backup-YYYYMMDD-HHMMSS.tar.gz
```

## Notes

This script does not configure Windows `portproxy`.

Typical WSL LAN exposure example:

```powershell
netsh interface portproxy add v4tov4 `
  listenaddress=192.168.137.1 `
  listenport=3001 `
  connectaddress=<WSL_IP> `
  connectport=3000
```

Default configuration targets offline/internal network usage:

* SQLite
* registration disabled
* SSH disabled
* offline mode enabled