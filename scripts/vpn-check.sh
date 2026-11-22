#!/usr/bin/env bash
# Prove the VPN pod is NOT using your real IP. Run any time, and after setup.
set -uo pipefail
ok=1
home_ip="$(curl -s --max-time 10 https://ipinfo.io/ip)"
echo "Your real (home) IP:      ${home_ip:-unknown}"

for c in gluetun qbittorrent radarr sonarr prowlarr; do
  podman container exists "$c" 2>/dev/null || continue
  ip="$(podman exec "$c" sh -c 'wget -qO- -T 10 https://ipinfo.io/ip 2>/dev/null || curl -s --max-time 10 https://ipinfo.io/ip' 2>/dev/null)"
  if [[ -z "$ip" ]]; then
    printf '%-12s no internet (VPN down? kill switch is blocking - that is safe)\n' "$c"
  elif [[ "$ip" == "$home_ip" ]]; then
    printf '%-12s %-16s !! LEAK: same as your home IP\n' "$c" "$ip"; ok=0
  else
    printf '%-12s %-16s OK (VPN)\n' "$c" "$ip"
  fi
done

echo
echo "DNS servers the pod uses (should be 127.0.0.1 = gluetun):"
podman exec qbittorrent cat /etc/resolv.conf 2>/dev/null | grep nameserver || echo "  (qbittorrent not running)"

if podman container exists gluetun 2>/dev/null; then
  echo
  echo "Forwarded port from ProtonVPN (should match qBittorrent's listening port):"
  podman exec gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null \
    || journalctl --user -u gluetun --no-pager | grep -io 'port forwarded is [0-9]*' | tail -1 \
    || echo "  (none yet - check NAT-PMP was ON when you made the WireGuard key)"
fi
[[ $ok == 1 ]] || exit 1
