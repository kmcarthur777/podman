#!/usr/bin/env bash
# Open the published ports in firewalld so other devices on your LAN can reach
# the services. Only needed if you want access from phones/other PCs.
set -euo pipefail
PORTS=(
  3000/tcp          # Homepage
  7878/tcp          # Radarr
  8989/tcp          # Sonarr
  9696/tcp          # Prowlarr
  8080/tcp          # qBittorrent
  6767/tcp          # Bazarr
  # Add these if you turn the stacks on:
  # 3001/tcp 3080/tcp 8096/tcp 5055/tcp 8384/tcp 22000/tcp 22000/udp 21027/udp 25565/tcp
)
for p in "${PORTS[@]}"; do sudo firewall-cmd --permanent --add-port="$p"; done
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
