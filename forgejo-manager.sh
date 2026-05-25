#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DIR="$HOME/forgejo"
DEFAULT_BACKUP_DIR="$HOME/forgejo-backups"
DEFAULT_IMAGE="code.forgejo.org/forgejo/forgejo:15.0.2"
DEFAULT_INTERNAL_PORT="3000"
DEFAULT_EXTERNAL_HOST="192.168.137.1"
DEFAULT_EXTERNAL_PORT="3001"
DEFAULT_APP_NAME="Forgejo"

COMMAND="${1:-}"
shift || true

FORGEJO_DIR="$DEFAULT_DIR"
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
IMAGE="$DEFAULT_IMAGE"
INTERNAL_PORT="$DEFAULT_INTERNAL_PORT"
EXTERNAL_HOST="$DEFAULT_EXTERNAL_HOST"
EXTERNAL_PORT="$DEFAULT_EXTERNAL_PORT"
APP_NAME="$DEFAULT_APP_NAME"
BACKUP_FILE=""
YES=0
FORCE_CONFIG=0

expand_path() {
  local p="$1"
  if [[ "$p" == "~" ]]; then
    echo "$HOME"
  elif [[ "$p" == "~/"* ]]; then
    echo "$HOME/${p:2}"
  else
    echo "$p"
  fi
}

ask() {
  local prompt="$1"
  local default="$2"
  local var
  if [[ "$YES" -eq 1 ]]; then
    echo "$default"
    return
  fi
  read -r -p "$prompt [$default]: " var
  echo "${var:-$default}"
}

confirm() {
  local prompt="$1"
  if [[ "$YES" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N]: " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

usage() {
  cat <<USAGE
Usage:
  $0 deploy [options]
  $0 backup [options]
  $0 restore --backup FILE [options]
  $0 status [options]

Options:
  --dir PATH              Forgejo directory, default: $DEFAULT_DIR
  --backup-dir PATH       Backup directory, default: $DEFAULT_BACKUP_DIR
  --backup FILE           Backup file for restore
  --image IMAGE           Docker image, default: $DEFAULT_IMAGE
  --internal-port PORT    WSL/Docker port, default: $DEFAULT_INTERNAL_PORT
  --external-host IP      External host shown in ROOT_URL, default: $DEFAULT_EXTERNAL_HOST
  --external-port PORT    External port shown in ROOT_URL, default: $DEFAULT_EXTERNAL_PORT
  --app-name NAME         Forgejo instance name, default: "$DEFAULT_APP_NAME"
  --force-config          Regenerate data/app.ini even if it already exists
  -y, --yes               Non-interactive mode
  -h, --help              Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) FORGEJO_DIR="$(expand_path "$2")"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$(expand_path "$2")"; shift 2 ;;
    --backup) BACKUP_FILE="$(expand_path "$2")"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --internal-port) INTERNAL_PORT="$2"; shift 2 ;;
    --external-host) EXTERNAL_HOST="$2"; shift 2 ;;
    --external-port) EXTERNAL_PORT="$2"; shift 2 ;;
    --app-name) APP_NAME="$2"; shift 2 ;;
    --force-config) FORCE_CONFIG=1; shift ;;
    -y|--yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg git openssl
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "Docker installed. Run: newgrp docker"
    echo "Then rerun this script."
    exit 0
  fi

  if ! docker ps >/dev/null 2>&1; then
    echo "Current user cannot access Docker."
    echo "Run: newgrp docker"
    exit 1
  fi
}

generate_app_ini() {
  local app_ini="$FORGEJO_DIR/data/app.ini"

  SECRET_KEY="$(openssl rand -hex 32)"
  INTERNAL_TOKEN="$(openssl rand -hex 48)"
  LFS_JWT_SECRET="$(openssl rand -hex 32)"
  OAUTH2_JWT_SECRET="$(openssl rand -hex 32)"

  if [[ -f "$app_ini" ]]; then
    SECRET_KEY="$(grep -E '^SECRET_KEY\s*=' "$app_ini" | cut -d= -f2- | xargs || echo "$SECRET_KEY")"
    INTERNAL_TOKEN="$(grep -E '^INTERNAL_TOKEN\s*=' "$app_ini" | cut -d= -f2- | xargs || echo "$INTERNAL_TOKEN")"
    LFS_JWT_SECRET="$(grep -E '^LFS_JWT_SECRET\s*=' "$app_ini" | cut -d= -f2- | xargs || echo "$LFS_JWT_SECRET")"
    OAUTH2_JWT_SECRET="$(grep -E '^JWT_SECRET\s*=' "$app_ini" | cut -d= -f2- | xargs || echo "$OAUTH2_JWT_SECRET")"
  fi

  cat > "$app_ini" <<INI
APP_NAME = ${APP_NAME}
RUN_USER = git
RUN_MODE = prod
WORK_PATH = /data
APP_SLOGAN =

[server]
APP_DATA_PATH = /data
DOMAIN = ${EXTERNAL_HOST}
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
ROOT_URL = http://${EXTERNAL_HOST}:${EXTERNAL_PORT}/
DISABLE_SSH = true
LFS_START_SERVER = true
LFS_JWT_SECRET = ${LFS_JWT_SECRET}
OFFLINE_MODE = true
SSH_DOMAIN = ${EXTERNAL_HOST}

[database]
DB_TYPE = sqlite3
PATH = /data/forgejo.db
SSL_MODE = disable
LOG_SQL = false

[repository]
ROOT = /data/git/repositories

[lfs]
PATH = /data/lfs

[log]
MODE = console
LEVEL = info
ROOT_PATH = /data/log

[security]
INSTALL_LOCK = true
SECRET_KEY = ${SECRET_KEY}
INTERNAL_TOKEN = ${INTERNAL_TOKEN}
PASSWORD_HASH_ALGO = pbkdf2_hi

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
ENABLE_CAPTCHA = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = true
NO_REPLY_ADDRESS = noreply.${EXTERNAL_HOST}

[mailer]
ENABLED = false

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[cron.update_checker]
ENABLED = false

[session]
PROVIDER = file

[repository.pull-request]
DEFAULT_MERGE_STYLE = merge

[repository.signing]
DEFAULT_TRUST_MODEL = committer

[oauth2]
JWT_SECRET = ${OAUTH2_JWT_SECRET}
INI
}

deploy() {
  FORGEJO_DIR="$(expand_path "$(ask "Forgejo directory" "$FORGEJO_DIR")")"
  IMAGE="$(ask "Forgejo image" "$IMAGE")"
  INTERNAL_PORT="$(ask "Internal Docker/WSL HTTP port" "$INTERNAL_PORT")"
  EXTERNAL_HOST="$(ask "External host/IP for access from other PCs" "$EXTERNAL_HOST")"
  EXTERNAL_PORT="$(ask "External port for access from other PCs" "$EXTERNAL_PORT")"
  APP_NAME="$(ask "Instance name" "$APP_NAME")"

  sudo apt update
  sudo apt install -y ca-certificates curl gnupg git openssl

  require_docker

  mkdir -p "$FORGEJO_DIR/data"
  cd "$FORGEJO_DIR"

  docker compose down --remove-orphans 2>/dev/null || true
  docker rm -f forgejo 2>/dev/null || true

  sudo chown -R "$(id -u):$(id -g)" data

  cat > docker-compose.yml <<YAML
services:
  forgejo:
    image: ${IMAGE}
    container_name: forgejo
    restart: unless-stopped
    user: "$(id -u):$(id -g)"
    working_dir: /data
    command:
      - /usr/local/bin/forgejo
      - web
      - --config
      - /data/app.ini
    environment:
      - HOME=/data
      - USER=git
    ports:
      - "0.0.0.0:${INTERNAL_PORT}:3000"
    volumes:
      - ./data:/data
YAML

  if [[ ! -f data/app.ini || "$FORCE_CONFIG" -eq 1 ]]; then
    generate_app_ini
    echo "Generated app.ini"
  else
    echo "Existing app.ini found. Keeping it unchanged."
    echo "Use --force-config to regenerate app.ini."
  fi

  docker compose pull
  docker compose up -d

  echo "Waiting for Forgejo..."
  for i in {1..30}; do
    if curl -fsS "http://127.0.0.1:${INTERNAL_PORT}/" >/dev/null 2>&1; then
      echo "Forgejo is up."
      echo "Internal local: http://localhost:${INTERNAL_PORT}"
      echo "Configured external URL: http://${EXTERNAL_HOST}:${EXTERNAL_PORT}"
      return
    fi
    sleep 1
  done

  echo "Forgejo did not respond. Logs:"
  docker logs --tail=120 forgejo
  exit 1
}

backup() {
  FORGEJO_DIR="$(expand_path "$(ask "Forgejo directory" "$FORGEJO_DIR")")"
  BACKUP_DIR="$(expand_path "$(ask "Backup directory" "$BACKUP_DIR")")"

  mkdir -p "$BACKUP_DIR"

  if [[ ! -d "$FORGEJO_DIR" ]]; then
    echo "Forgejo directory not found: $FORGEJO_DIR"
    exit 1
  fi

  cd "$FORGEJO_DIR"

  echo "Stopping Forgejo for consistent backup..."
  docker compose down 2>/dev/null || true

  ts="$(date +%Y%m%d-%H%M%S)"
  backup_path="$BACKUP_DIR/forgejo-backup-$ts.tar.gz"

  cd "$(dirname "$FORGEJO_DIR")"
  tar -czf "$backup_path" "$(basename "$FORGEJO_DIR")"

  cd "$FORGEJO_DIR"
  docker compose up -d 2>/dev/null || true

  echo "Backup created:"
  echo "$backup_path"
}

restore() {
  FORGEJO_DIR="$(expand_path "$(ask "Forgejo directory" "$FORGEJO_DIR")")"
  BACKUP_DIR="$(expand_path "$BACKUP_DIR")"

  if [[ -z "$BACKUP_FILE" ]]; then
    if [[ "$YES" -eq 0 && -d "$BACKUP_DIR" ]]; then
      mapfile -t backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.gz" | sort -r)

      if [[ "${#backup_files[@]}" -gt 0 ]]; then
        echo
        echo "Available backups in $BACKUP_DIR:"
        for i in "${!backup_files[@]}"; do
          printf "  %d) %s\n" "$((i + 1))" "$(basename "${backup_files[$i]}")"
        done
        echo

        read -r -p "Select backup number, or enter custom path: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backup_files[@]} )); then
          BACKUP_FILE="${backup_files[$((choice - 1))]}"
        else
          BACKUP_FILE="$(expand_path "$choice")"
        fi
      else
        BACKUP_FILE="$(expand_path "$(ask "Backup file to restore" "$BACKUP_FILE")")"
      fi
    else
      BACKUP_FILE="$(expand_path "$(ask "Backup file to restore" "$BACKUP_FILE")")"
    fi
  else
    BACKUP_FILE="$(expand_path "$BACKUP_FILE")"
  fi

  if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
  fi

  if [[ -d "$FORGEJO_DIR" ]]; then
    echo "Existing Forgejo directory found: $FORGEJO_DIR"
    confirm "This will stop Forgejo and replace the directory. Continue?" || exit 1
    cd "$FORGEJO_DIR"
    docker compose down 2>/dev/null || true
    cd ~
    mv "$FORGEJO_DIR" "${FORGEJO_DIR}.before-restore-$(date +%Y%m%d-%H%M%S)"
  fi

  mkdir -p "$(dirname "$FORGEJO_DIR")"
  tar -xzf "$BACKUP_FILE" -C "$(dirname "$FORGEJO_DIR")"

  cd "$FORGEJO_DIR"
  sudo chown -R "$(id -u):$(id -g)" .
  require_docker
  docker compose up -d

  echo "Restore completed."
  echo "Restored from:"
  echo "$BACKUP_FILE"
}

status() {
  FORGEJO_DIR="$(expand_path "$FORGEJO_DIR")"
  echo "Forgejo dir: $FORGEJO_DIR"
  if [[ -d "$FORGEJO_DIR" ]]; then
    cd "$FORGEJO_DIR"
    docker compose ps || true
    echo
    docker logs --tail=40 forgejo 2>/dev/null || true
  else
    echo "Directory not found."
  fi
}

case "$COMMAND" in
  deploy) deploy ;;
  backup) backup ;;
  restore) restore ;;
  status) status ;;
  ""|-h|--help) usage ;;
  *) echo "Unknown command: $COMMAND"; usage; exit 1 ;;
esac
