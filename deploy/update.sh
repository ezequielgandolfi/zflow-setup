#!/usr/bin/env bash
# Installs, updates and restarts zflow. Installed as /opt/zflow/bin/zflow-update and run as root, either by
# zflow-update.service when the Studio writes a request, by the zflow CLI, or by install.sh.
#
#   zflow-update                     handle /var/lib/zflow/update/request.json (from the Studio)
#   zflow-update --update [version]  download a release (the latest by default) and deploy it
#   zflow-update --restart           restart the services
#   zflow-update --from-dir <dir>    deploy an extracted release (install.sh, and --update through the new release)
set -euo pipefail

REPO="ezequielgandolfi/zflow-setup"
OPT=/opt/zflow
DATA=/var/lib/zflow
UPDATES="$DATA/update"
ENV_FILE=/etc/zflow/zflow.env
SYSTEMD=/etc/systemd/system
KEEP=3
HEALTH_TIMEOUT=60

ACTION=""
TARGET_VERSION=""
FROM_VERSION=""

log() { echo "[zflow] $*"; }

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\t' '  '; }

# Written next to it and renamed, like the Studio does, so readers never see half a file.
status() {
  local state="$1" message="${2:-}"
  mkdir -p "$UPDATES"
  local tmp="$UPDATES/.status.json.root"
  printf '{"state":"%s","action":"%s","version":"%s","from":"%s","message":"%s","at":"%s"}\n' \
    "$state" "$ACTION" "$(json_escape "$TARGET_VERSION")" "$(json_escape "$FROM_VERSION")" \
    "$(json_escape "$message")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$UPDATES/status.json"
  [ -n "$message" ] && log "$message"
  return 0
}

fail() {
  status failed "$1"
  exit 1
}

current_version() { cat "$OPT/current/VERSION" 2>/dev/null || true; }

node_arch() {
  case "$(uname -m)" in
    x86_64) echo x64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) fail "zflow runs on x86_64 and aarch64, not $(uname -m)" ;;
  esac
}

latest_version() {
  curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest" |
    sed -n 's/.*"tag_name": *"v\([0-9][0-9.]*\)".*/\1/p' | head -1
}

ensure_system() {
  if ! id zflow &>/dev/null; then
    log "Creating the zflow user"
    useradd --system --home-dir "$DATA" --shell /usr/sbin/nologin zflow
  fi
  # Serial adapters (Zigbee coordinators) belong to dialout.
  getent group dialout >/dev/null && usermod -aG dialout zflow
  mkdir -p "$OPT/releases" "$OPT/bin" "$DATA/backups" "$UPDATES" /etc/zflow
  chown zflow:zflow "$DATA" "$UPDATES"
  chmod 750 "$DATA"
  if [ ! -f "$ENV_FILE" ]; then
    sed -e "s/^HOST=.*/HOST=${ZFLOW_HOST:-0.0.0.0}/" -e "s/^PORT=.*/PORT=${ZFLOW_PORT:-4000}/" \
      "$1/deploy/zflow.env" >"$ENV_FILE"
    chmod 644 "$ENV_FILE"
  fi
}

# Installs the Node the release asks for next to the others and prints its folder.
ensure_node() {
  local version arch dir tmp
  version="$(tr -d '[:space:]' <"$1/deploy/node-version")"
  arch="$(node_arch)"
  dir="$OPT/node-$version"
  if [ ! -x "$dir/bin/node" ]; then
    log "Installing Node $version" >&2
    tmp="$(mktemp -d)"
    local name="node-v$version-linux-$arch.tar.xz"
    curl -fsSL -o "$tmp/$name" "https://nodejs.org/dist/v$version/$name" || fail "Couldn't download Node $version"
    curl -fsSL -o "$tmp/SHASUMS256.txt" "https://nodejs.org/dist/v$version/SHASUMS256.txt" ||
      fail "Couldn't download Node's checksums"
    (cd "$tmp" && grep " $name\$" SHASUMS256.txt | sha256sum -c --quiet -) || fail "Node $version failed its checksum"
    mkdir -p "$dir.partial"
    tar -xJf "$tmp/$name" -C "$dir.partial" --strip-components=1
    rm -rf "$dir" "$tmp"
    mv "$dir.partial" "$dir"
  fi
  echo "$dir"
}

read_env() {
  PORT=4000 HOST=127.0.0.1 CONTROL_PORT=4100
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && . "$ENV_FILE"
  case "$HOST" in 0.0.0.0 | :: | "") HOST=127.0.0.1 ;; esac
}

# Waits for the Studio to answer with the expected version (any, when empty) and for the engine's control API.
healthy() {
  local expected="$1" deadline=$((SECONDS + HEALTH_TIMEOUT)) answer
  read_env
  while [ $SECONDS -lt $deadline ]; do
    answer="$(curl -fsS "http://$HOST:$PORT/api/version" 2>/dev/null || true)"
    if [[ -n "$answer" && ("$expected" == "" || "$answer" == *"\"$expected\""*) ]] &&
      curl -fsS -o /dev/null "http://127.0.0.1:$CONTROL_PORT/control/engine" 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

install_units() {
  local dir="$1" unit
  for unit in zflow.target zflow-engine.service zflow-studio.service zflow-update.path zflow-update.service; do
    install -m 644 "$dir/deploy/$unit" "$SYSTEMD/$unit"
  done
  # Replaced by renaming, so a copy of this script that's running keeps reading the old file.
  install -m 755 "$dir/deploy/update.sh" "$OPT/bin/.zflow-update.new" && mv -f "$OPT/bin/.zflow-update.new" "$OPT/bin/zflow-update"
  install -m 755 "$dir/deploy/zflow" "$OPT/bin/.zflow.new" && mv -f "$OPT/bin/.zflow.new" "$OPT/bin/zflow"
  ln -sfn "$OPT/bin/zflow" /usr/local/bin/zflow
  systemctl daemon-reload
  systemctl enable zflow.target zflow-engine.service zflow-studio.service zflow-update.path >/dev/null 2>&1
  systemctl reset-failed zflow-update.path zflow-update.service 2>/dev/null || true
  systemctl start zflow-update.path
}

backup_db() {
  local dest
  dest="$DATA/backups/$(date -u +%Y%m%d%H%M%S)-${FROM_VERSION:-none}"
  mkdir -p "$dest"
  for file in "$DATA"/zflow.db "$DATA"/zflow.db-wal "$DATA"/zflow.db-shm; do
    [ -f "$file" ] && cp -p "$file" "$dest/"
  done
  echo "$dest"
}

restore_db() {
  rm -f "$DATA"/zflow.db "$DATA"/zflow.db-wal "$DATA"/zflow.db-shm
  cp -p "$1"/zflow.db* "$DATA/" 2>/dev/null || true
}

prune() {
  local keep_current keep_node
  keep_current="$(readlink -f "$OPT/current" || true)"
  # shellcheck disable=SC2012
  ls -1dt "$OPT"/releases/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r dir; do
    [ "$(readlink -f "$dir")" != "$keep_current" ] && rm -rf "$dir"
  done
  # shellcheck disable=SC2012
  ls -1dt "$DATA"/backups/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
  keep_node="$(readlink -f "$OPT/node" || true)"
  for dir in "$OPT"/node-*; do
    [ -d "$dir" ] || continue
    local used=false release
    for release in "$OPT"/releases/*/; do
      [ -f "$release/deploy/node-version" ] && [ "$OPT/node-$(tr -d '[:space:]' <"$release/deploy/node-version")" = "$dir" ] && used=true
    done
    [ "$dir" = "$keep_node" ] && used=true
    $used || rm -rf "$dir"
  done
}

# Deploys an extracted release: installs it beside the running one, then swaps them, rolling back if it won't start.
deploy() {
  local source dir node old_release old_node backup
  source="$(cd "$1" && pwd)"
  TARGET_VERSION="$(tr -d '[:space:]' <"$source/VERSION")"
  FROM_VERSION="$(current_version)"
  [ -n "$ACTION" ] || ACTION=update
  ensure_system "$source"

  status installing "Installing zflow $TARGET_VERSION"
  node="$(ensure_node "$source")"
  dir="$OPT/releases/$TARGET_VERSION-$(date -u +%Y%m%d%H%M%S)"
  mkdir -p "$dir"
  cp -a "$source/." "$dir/"
  (cd "$dir" && PATH="$node/bin:$PATH" npm_config_cache=/var/cache/zflow/npm \
    npm ci --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error) || {
    rm -rf "$dir"
    fail "Couldn't install the dependencies of $TARGET_VERSION"
  }
  chown -R root:root "$dir"

  status restarting "Restarting zflow on $TARGET_VERSION"
  old_release="$(readlink -f "$OPT/current" 2>/dev/null || true)"
  old_node="$(readlink -f "$OPT/node" 2>/dev/null || true)"
  systemctl stop zflow.target 2>/dev/null || true
  backup="$(backup_db)"
  ln -sfn "$dir" "$OPT/current"
  ln -sfn "$node" "$OPT/node"
  install_units "$dir"
  systemctl start zflow.target

  if healthy "$TARGET_VERSION"; then
    prune
    status "done" "zflow $TARGET_VERSION is running"
    return 0
  fi
  if [ -z "$old_release" ]; then
    fail "zflow $TARGET_VERSION didn't start. See: journalctl -u zflow-engine -u zflow-studio"
  fi
  log "zflow $TARGET_VERSION didn't start, going back to $FROM_VERSION"
  systemctl stop zflow.target || true
  restore_db "$backup"
  ln -sfn "$old_release" "$OPT/current"
  ln -sfn "$old_node" "$OPT/node"
  install_units "$old_release"
  systemctl start zflow.target
  rm -rf "$dir"
  healthy "$FROM_VERSION" || true
  fail "zflow $TARGET_VERSION didn't start, so $FROM_VERSION is back. See: journalctl -u zflow-engine -u zflow-studio"
}

# Downloads and verifies a release, then hands it to its own update.sh so each release deploys itself.
update() {
  local version="$1" tmp name
  FROM_VERSION="$(current_version)"
  [ -n "$version" ] || version="$(latest_version)"
  TARGET_VERSION="$version"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Couldn't find the version to install"
  status downloading "Downloading zflow $version"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  name="zflow-$version.tar.gz"
  local base="https://github.com/$REPO/releases/download/v$version"
  curl -fsSL -o "$tmp/$name" "$base/$name" || fail "Couldn't download zflow $version"
  curl -fsSL -o "$tmp/$name.sha256" "$base/$name.sha256" || fail "Couldn't download the checksum of zflow $version"
  (cd "$tmp" && sha256sum -c --quiet "$name.sha256") || fail "zflow $version failed its checksum"
  tar -xzf "$tmp/$name" -C "$tmp"
  bash "$tmp/zflow/deploy/update.sh" --from-dir "$tmp/zflow"
}

restart() {
  ACTION=restart
  TARGET_VERSION="$(current_version)"
  FROM_VERSION="$TARGET_VERSION"
  status restarting "Restarting zflow"
  systemctl restart zflow.target
  if healthy ""; then
    status "done" "zflow restarted"
  else
    fail "zflow didn't come back after the restart. See: journalctl -u zflow-engine -u zflow-studio"
  fi
}

# The request is deleted first: the path unit starts this again for as long as the file exists.
from_request() {
  local file="$UPDATES/request.json" request
  [ -f "$file" ] || exit 0
  request="$(cat "$file")"
  rm -f "$file"
  case "$request" in
    *'"action":"restart"'*) restart ;;
    *'"action":"update"'*)
      ACTION=update
      local version
      version="$(printf '%s' "$request" | sed -n 's/.*"version":"\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p')"
      [ -n "$version" ] || fail "The update request has no version"
      update "$version"
      ;;
    *) fail "Unknown request: $request" ;;
  esac
}

[ "$(id -u)" -eq 0 ] || {
  echo "Run this as root (sudo)." >&2
  exit 1
}

# One at a time: the Studio, the CLI and install.sh can all start one.
if [ -z "${ZFLOW_UPDATE_LOCKED:-}" ]; then
  exec 9>/run/zflow-update.lock
  if ! flock -n 9; then
    echo "Waiting for another zflow update to finish…" >&2
    flock -w 1800 9 || {
      echo "Another zflow update is still running." >&2
      exit 1
    }
  fi
  export ZFLOW_UPDATE_LOCKED=1
fi

usage() {
  echo "Usage: zflow-update [--update [version] | --restart | --from-dir <extracted release>]" >&2
  exit 1
}

case "${1:-}" in
  "") from_request ;;
  --update) ACTION=update && update "${2:-}" ;;
  --restart) restart ;;
  --from-dir)
    [ -n "${2:-}" ] || usage
    ACTION="${ZFLOW_ACTION:-update}"
    deploy "$2"
    ;;
  *) usage ;;
esac
