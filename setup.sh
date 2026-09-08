#!/usr/bin/env bash

set -Eeuo pipefail

REPO_SSH="${YUPANEL_REPO_SSH:-git@github.com:Yu817/Yu-Panel.git}"
BRANCH="${YUPANEL_BRANCH:-main}"
INSTALL_DIR="${YUPANEL_INSTALL_DIR:-/opt/yu-panel}"
RUNTIME_DIR="${YUPANEL_RUNTIME_DIR:-/opt/yu-panel-runtime}"
DATA_DIR="${YUPANEL_DATA_DIR_ROOT:-/opt/yu-panel-data}"
SERVICE_USER="${YUPANEL_USER:-${SUDO_USER:-${USER:-root}}}"

log() { printf '\n\033[1;36m[Yu-Panel]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[Yu-Panel]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[Yu-Panel] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [ "${EUID}" -ne 0 ]; then
  fail "Please run this installer with sudo/root privileges."
fi

if [ ! -f /etc/os-release ]; then
  fail "Unable to detect Linux distribution."
fi

. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) fail "This installer currently supports Ubuntu/Debian only (detected: ${ID:-unknown})." ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ;;
  *) fail "Yu-Panel one-command installer currently supports x86_64/amd64 only (detected: $ARCH)." ;;
esac

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  SERVICE_USER="root"
fi
SERVICE_GROUP="$(id -gn "$SERVICE_USER")"
SERVICE_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
[ -n "$SERVICE_HOME" ] || SERVICE_HOME="/root"

run_user() {
  if [ "$SERVICE_USER" = "root" ]; then
    env HOME="$SERVICE_HOME" "$@"
  else
    sudo -u "$SERVICE_USER" -H "$@"
  fi
}

log "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl wget git sudo openssh-client build-essential lib32gcc-s1 openjdk-21-jre-headless

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
if [ "$NODE_MAJOR" != "20" ]; then
  log "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

if ! command -v pm2 >/dev/null 2>&1; then
  log "Installing PM2..."
  npm install -g pm2
fi

install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$INSTALL_DIR" "$DATA_DIR" "$DATA_DIR/daemon" "$DATA_DIR/web"

SSH_DIR="$SERVICE_HOME/.ssh"
DEPLOY_KEY="$SSH_DIR/yupanel_deploy_ed25519"
DEPLOY_KEY_PUB="$DEPLOY_KEY.pub"
GIT_SSH_COMMAND_VALUE=""

repo_access_default() {
  run_user git ls-remote "$REPO_SSH" HEAD >/dev/null 2>&1
}

repo_access_deploy_key() {
  [ -f "$DEPLOY_KEY" ] || return 1
  run_user env GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
    git ls-remote "$REPO_SSH" HEAD >/dev/null 2>&1
}

configure_repo_access() {
  if repo_access_default; then
    log "GitHub access is already configured for '$SERVICE_USER'."
    GIT_SSH_COMMAND_VALUE=""
    return 0
  fi

  install -d -m 0700 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$SSH_DIR"

  if [ ! -f "$DEPLOY_KEY" ]; then
    log "Creating a dedicated read-only Yu-Panel deploy key..."
    run_user ssh-keygen -q -t ed25519 -N "" \
      -C "yupanel-deploy@$(hostname)" \
      -f "$DEPLOY_KEY"
  fi

  chmod 0600 "$DEPLOY_KEY"
  chmod 0644 "$DEPLOY_KEY_PUB"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$DEPLOY_KEY" "$DEPLOY_KEY_PUB"

  if repo_access_deploy_key; then
    log "Yu-Panel deploy key is authorized."
    GIT_SSH_COMMAND_VALUE="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    return 0
  fi

  printf '\n\033[1;33mYu-Panel needs read access to the private GitHub repository.\033[0m\n'
  printf 'Add the following public key as a Deploy Key:\n\n'
  cat "$DEPLOY_KEY_PUB"
  printf '\n\nGitHub page:\n'
  printf '  https://github.com/Yu817/Yu-Panel/settings/keys\n\n'
  printf 'Recommended settings:\n'
  printf '  Title: Yu-Panel - %s\n' "$(hostname)"
  printf '  Allow write access: OFF\n\n'

  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf 'After adding the key in GitHub, press Enter here to continue... ' > /dev/tty
    read -r _ < /dev/tty || true
    printf '\n' > /dev/tty

    if repo_access_deploy_key; then
      log "Deploy Key verified successfully. Continuing installation..."
      GIT_SSH_COMMAND_VALUE="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
      return 0
    fi
  fi

  fail "Deploy Key is not authorized yet. Add the public key above to Yu817/Yu-Panel and run the same installer command again."
}

configure_repo_access

git_user() {
  if [ -n "$GIT_SSH_COMMAND_VALUE" ]; then
    run_user env GIT_SSH_COMMAND="$GIT_SSH_COMMAND_VALUE" git "$@"
  else
    run_user git "$@"
  fi
}

if [ -d "$INSTALL_DIR/.git" ]; then
  log "Updating Yu-Panel source from $BRANCH..."
  git_user -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  git_user -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
else
  if [ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    fail "$INSTALL_DIR is not empty and is not a Git repository. Move or remove it first."
  fi
  log "Cloning private Yu-Panel repository..."
  git_user clone --depth 1 --branch "$BRANCH" "$REPO_SSH" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
chmod +x install-dependents.sh build.sh

log "Installing Node.js dependencies..."
run_user ./install-dependents.sh

log "Downloading Yu-Panel Linux helper binaries..."
mkdir -p daemon/lib
wget -q --show-progress --input-file=lib-urls.txt --directory-prefix=daemon/lib/
chmod +x daemon/lib/* 2>/dev/null || true
chown -R "$SERVICE_USER:$SERVICE_GROUP" daemon/lib

log "Building Yu-Panel production package..."
run_user ./build.sh

log "Installing runtime files..."
rm -rf "$RUNTIME_DIR.new"
mkdir -p "$RUNTIME_DIR.new"
cp -a "$INSTALL_DIR/production-code/." "$RUNTIME_DIR.new/"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$RUNTIME_DIR.new"
rm -rf "$RUNTIME_DIR.old"
if [ -d "$RUNTIME_DIR" ]; then
  mv "$RUNTIME_DIR" "$RUNTIME_DIR.old"
fi
mv "$RUNTIME_DIR.new" "$RUNTIME_DIR"
rm -rf "$RUNTIME_DIR.old"

log "Configuring PM2 services..."
run_user bash -lc "pm2 delete yu-panel-daemon >/dev/null 2>&1 || true"
run_user bash -lc "pm2 delete yu-panel-web >/dev/null 2>&1 || true"

run_user env YUPANEL_DATA_DIR="$DATA_DIR/daemon" pm2 start "$RUNTIME_DIR/daemon/app.js" \
  --name yu-panel-daemon \
  --cwd "$RUNTIME_DIR/daemon" \
  --node-args="--max-old-space-size=8192 --enable-source-maps"

run_user env YUPANEL_DATA_DIR="$DATA_DIR/web" pm2 start "$RUNTIME_DIR/web/app.js" \
  --name yu-panel-web \
  --cwd "$RUNTIME_DIR/web" \
  --node-args="--max-old-space-size=8192 --enable-source-maps"

run_user pm2 save

log "Configuring PM2 startup..."
env PATH="$PATH:/usr/bin:/usr/local/bin" pm2 startup systemd -u "$SERVICE_USER" --hp "$SERVICE_HOME" >/dev/null
systemctl enable "pm2-$SERVICE_USER" >/dev/null 2>&1 || true
systemctl restart "pm2-$SERVICE_USER" >/dev/null 2>&1 || true

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

printf '\n\033[1;32mYu-Panel installation completed successfully.\033[0m\n'
printf 'Source:   %s\n' "$INSTALL_DIR"
printf 'Runtime:  %s\n' "$RUNTIME_DIR"
printf 'Data:     %s\n' "$DATA_DIR"
printf 'Web:      http://%s:30660\n' "${HOST_IP:-SERVER_IP}"
printf 'Daemon:   port 30661\n'
printf '\nUseful commands:\n'
printf '  sudo -u %s -H pm2 status\n' "$SERVICE_USER"
printf '  sudo -u %s -H pm2 logs yu-panel-web\n' "$SERVICE_USER"
printf '  sudo -u %s -H pm2 logs yu-panel-daemon\n' "$SERVICE_USER"
printf '\nTo update later, run the same installer command again.\n'
