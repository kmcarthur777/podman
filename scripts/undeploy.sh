#!/usr/bin/env bash
# Stop and remove all homelab Quadlets from this machine. Data volumes and
# ~/homelab are kept; delete those manually if you really want them gone.
set -euo pipefail
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd/homelab"
[[ -d "$QUADLET_DIR" ]] || { echo "Nothing deployed."; exit 0; }
for f in "$QUADLET_DIR"/*.container; do
  systemctl --user stop "$(basename "$f" .container).service" || true
done
rm -rf "$QUADLET_DIR"
systemctl --user daemon-reload
echo "Removed. Volumes kept (podman volume ls)."
