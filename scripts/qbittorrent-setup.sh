#!/usr/bin/env bash
# One-time qBittorrent setup so you never have to log in or click through settings:
#   - no login from your home network or from the other containers
#   - downloads go to /data/torrents, with Radarr/Sonarr categories in subfolders
# deploy.sh runs this automatically; it's safe to run again (does nothing if already set).
set -euo pipefail

VOL="$(podman volume inspect qbittorrent-config --format '{{.Mountpoint}}' 2>/dev/null)" \
  || { echo "qbittorrent-config volume not found - run deploy.sh first" >&2; exit 1; }
CONF="$VOL/qBittorrent/qBittorrent.conf"

# qBittorrent writes its config file on first start.
for _ in $(seq 1 60); do [[ -f "$CONF" ]] && break; sleep 1; done
[[ -f "$CONF" ]] || { echo "qBittorrent hasn't created $CONF yet - is it running?" >&2; exit 1; }

edit() { python3 - "$CONF" "$1" <<'PY'
import configparser, sys
path, mode = sys.argv[1], sys.argv[2]
want = {
    "Preferences": {
        "WebUI\\LocalHostAuth": "false",
        "WebUI\\AuthSubnetWhitelistEnabled": "true",
        # Private/home + container ranges only; the internet can't reach the web UI anyway.
        "WebUI\\AuthSubnetWhitelist": "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16, ::1/128, fc00::/7, fe80::/10",
    },
    "BitTorrent": {
        "Session\\DefaultSavePath": "/data/torrents",
        "Session\\DisableAutoTMMByDefault": "false",
    },
}
cp = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
cp.optionxform = str
cp.read(path, encoding="utf-8")
missing = any(not cp.has_section(s) or cp[s].get(k) != v for s, kv in want.items() for k, v in kv.items())
if mode == "check":
    sys.exit(1 if missing else 0)
for s, kv in want.items():
    if not cp.has_section(s):
        cp.add_section(s)
    for k, v in kv.items():
        cp[s][k] = v
with open(path, "w", encoding="utf-8") as f:
    cp.write(f, space_around_delimiters=False)
PY
}

if edit check; then
  echo "qBittorrent: already set up (no login on your network, saves to /data/torrents)"
  exit 0
fi
# qBittorrent rewrites its config when it exits, so edit it while stopped.
systemctl --user stop qbittorrent.service
edit apply
systemctl --user start qbittorrent.service
echo "qBittorrent: login turned off for your network, downloads go to /data/torrents"
