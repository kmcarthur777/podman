#!/usr/bin/env bash
# Deploy the stacks listed in hosts/<host>.conf as rootless Podman Quadlets.
#
#   ./scripts/deploy.sh gaming-pc            # install + start
#   ./scripts/deploy.sh gaming-pc --check    # only validate, change nothing
#
# Quadlet files are copied into ~/.config/containers/systemd/homelab/, which
# this script fully owns (it's wiped and rewritten on every run, so removing a
# stack from the host file removes it from the machine on the next deploy).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:?usage: deploy.sh <host> [--check]}"
MODE="${2:-}"
HOST_FILE="$REPO/hosts/$HOST.conf"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd/homelab"
DATA_DIR="$HOME/homelab"
QUADLET_BIN=/usr/libexec/podman/quadlet

[[ -f "$HOST_FILE" ]] || { echo "No host file: $HOST_FILE" >&2; exit 1; }
command -v podman >/dev/null || { echo "podman is not installed" >&2; exit 1; }

# Stack list: strip comments/blank lines, always include the shared network.
mapfile -t STACKS < <(sed 's/#.*//' "$HOST_FILE" | awk 'NF{print $1}')
STACKS=(network "${STACKS[@]}")

for s in "${STACKS[@]}"; do
  [[ -d "$REPO/stacks/$s" ]] || { echo "Unknown stack '$s' in $HOST_FILE" >&2; exit 1; }
done

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
for s in "${STACKS[@]}"; do
  find "$REPO/stacks/$s" -maxdepth 1 -type f \
    \( -name '*.container' -o -name '*.network' -o -name '*.volume' -o -name '*.pod' \) \
    -exec cp {} "$STAGE/" \;
done

echo "Validating Quadlets for host '$HOST': ${STACKS[*]}"
if [[ -x "$QUADLET_BIN" ]]; then
  QUADLET_UNIT_DIRS="$STAGE" "$QUADLET_BIN" -dryrun -user >/dev/null
  echo "  OK"
else
  echo "  (quadlet generator not found, skipping validation)"
fi
[[ "$MODE" == "--check" ]] && exit 0

# Seed config + data directories (never overwrites existing config).
mkdir -p "$DATA_DIR"
for s in "${STACKS[@]}"; do
  case "$s" in
    dashboard)
      mkdir -p "$DATA_DIR/homepage/config"
      cp -rn "$REPO/stacks/dashboard/config/." "$DATA_DIR/homepage/config/" ;;
    sync)
      mkdir -p "$DATA_DIR/syncthing" ;;
  esac
done

# Install.
rm -rf "$QUADLET_DIR"
mkdir -p "$QUADLET_DIR"
cp "$STAGE"/* "$QUADLET_DIR/"
systemctl --user daemon-reload

# Start everything that has an [Install] section (on-demand ones are skipped).
for f in "$QUADLET_DIR"/*.container; do
  name="$(basename "$f" .container)"
  if grep -q '^\[Install\]' "$f"; then
    echo "Starting $name"
    systemctl --user restart "$name.service" || echo "  !! $name failed: journalctl --user -u $name -e"
  else
    echo "Installed $name (on-demand: systemctl --user start $name)"
  fi
done

# Keep images fresh (containers marked AutoUpdate=registry).
systemctl --user enable --now podman-auto-update.timer >/dev/null 2>&1 || true

echo
echo "Done. Status:  systemctl --user list-units 'homepage*' 'uptime-kuma*' 'syncthing*' 'jellyfin*' 'ollama*' 'open-webui*' 'minecraft*'"
echo "Containers:    podman ps"
