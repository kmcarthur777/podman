#!/usr/bin/env bash
# Open the published ports in firewalld so other devices on your LAN can reach
# the services. Only needed if you want access from phones/other PCs.
set -euo pipefail
PORTS=(
  3000/tcp          # Homepage
  3001/tcp          # Uptime Kuma
  3080/tcp          # Open WebUI
  8096/tcp          # Jellyfin
  8384/tcp          # Syncthing UI
  22000/tcp 22000/udp 21027/udp  # Syncthing sync + discovery
  25565/tcp         # Minecraft
  5055/tcp          # Jellyseerr
  7878/tcp 8989/tcp 9696/tcp 8080/tcp 6767/tcp  # Radarr Sonarr Prowlarr qBittorrent Bazarr
)
for p in "${PORTS[@]}"; do sudo firewall-cmd --permanent --add-port="$p"; done
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
