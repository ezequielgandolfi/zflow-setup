#!/usr/bin/env bash
# Installs zflow as a service on Debian, Ubuntu or Raspberry Pi OS (x86_64 or aarch64).
#
#   curl -fsSL https://raw.githubusercontent.com/ezequielgandolfi/zflow-setup/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/ezequielgandolfi/zflow-setup/main/install.sh | sudo bash -s -- --port 8080
#
# Running it again reinstalls the chosen release over the current one, keeping the data and settings.
set -euo pipefail

REPO="ezequielgandolfi/zflow-setup"

VERSION=""
FILE=""
PORT=""
HOST=""
UNINSTALL=false
PURGE=false

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --version <x.y.z>   Install this release instead of the latest
  --port <port>       Port the Studio listens on (default 4000; only used on the first install)
  --host <address>    Address the Studio listens on (default 0.0.0.0; only used on the first install)
  --file <tarball>    Install a release tarball from disk instead of downloading it
  --uninstall         Remove zflow, keeping its data in /var/lib/zflow
  --purge             With --uninstall, also delete the data and settings
EOF
}

info() { echo -e "\033[0;32m[zflow]\033[0m $*"; }
die() {
  echo -e "\033[0;31m[zflow]\033[0m $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}" && shift ;;
    --port) PORT="${2:-}" && shift ;;
    --host) HOST="${2:-}" && shift ;;
    --file) FILE="${2:-}" && shift ;;
    --uninstall) UNINSTALL=true ;;
    --purge) PURGE=true ;;
    -h | --help) usage && exit 0 ;;
    *) usage >&2 && exit 1 ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "Run the installer as root, for example: curl -fsSL … | sudo bash"

if $UNINSTALL; then
  [ -x /opt/zflow/bin/zflow ] || die "zflow isn't installed"
  if $PURGE; then exec /opt/zflow/bin/zflow uninstall --purge; else exec /opt/zflow/bin/zflow uninstall; fi
fi

[ "$(uname -s)" = Linux ] || die "zflow installs on Linux only"
command -v systemctl >/dev/null && [ -d /run/systemd/system ] || die "zflow runs as a systemd service, and systemd isn't running"
# In a subshell, since os-release has a VERSION of its own.
# shellcheck disable=SC1091
os="$(. /etc/os-release && echo "$ID ${ID_LIKE:-}|${PRETTY_NAME:-$ID}")"
[[ " ${os%%|*} " == *" debian "* || " ${os%%|*} " == *" ubuntu "* ]] ||
  die "This installer supports Debian, Ubuntu and Raspberry Pi OS, not ${os#*|}"
case "$(uname -m)" in
  x86_64 | aarch64) ;;
  *) die "zflow runs on x86_64 and aarch64 (64-bit) systems, not $(uname -m)" ;;
esac
[ -z "$VERSION" ] || [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version takes a version like 1.2.0"
[ -z "$PORT" ] || [[ "$PORT" =~ ^[0-9]+$ ]] || die "--port takes a number"

missing=()
for cmd in curl tar xz sha256sum flock; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
if [ ${#missing[@]} -gt 0 ]; then
  info "Installing system packages"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates tar xz-utils coreutils util-linux >/dev/null
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || die "There's no file at $FILE"
  cp "$FILE" "$tmp/zflow.tar.gz"
else
  if [ -z "$VERSION" ]; then
    VERSION="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest" |
      sed -n 's/.*"tag_name": *"v\([0-9][0-9.]*\)".*/\1/p' | head -1)"
    [ -n "$VERSION" ] || die "Couldn't find the latest zflow release on github.com/$REPO"
  fi
  name="zflow-$VERSION.tar.gz"
  base="https://github.com/$REPO/releases/download/v$VERSION"
  info "Downloading zflow $VERSION"
  curl -fsSL -o "$tmp/$name" "$base/$name" || die "Couldn't download zflow $VERSION from $base"
  curl -fsSL -o "$tmp/$name.sha256" "$base/$name.sha256" || die "Couldn't download the checksum of zflow $VERSION"
  (cd "$tmp" && sha256sum -c --quiet "$name.sha256") || die "The download of zflow $VERSION is corrupted. Try again"
  mv "$tmp/$name" "$tmp/zflow.tar.gz"
fi

tar -xzf "$tmp/zflow.tar.gz" -C "$tmp"
[ -f "$tmp/zflow/deploy/update.sh" ] || die "That isn't a zflow release"

ZFLOW_ACTION=install ZFLOW_PORT="${PORT:-4000}" ZFLOW_HOST="${HOST:-0.0.0.0}" \
  bash "$tmp/zflow/deploy/update.sh" --from-dir "$tmp/zflow"

# shellcheck disable=SC1091
. /etc/zflow/zflow.env
address="$HOST"
[ "$address" = 0.0.0.0 ] && address="$(hostname -I 2>/dev/null | awk '{print $1}')"
info "zflow is running. Open the Studio at http://${address:-localhost}:$PORT"
info "Manage it with: zflow status | zflow logs | sudo zflow restart | sudo zflow update"
