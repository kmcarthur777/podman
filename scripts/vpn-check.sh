#!/usr/bin/env bash
# Prove the VPN pod is NOT using your real IP. Run any time, and after setup.
set -uo pipefail
ok=1

if ! podman container exists gluetun 2>/dev/null; then
  # Host-VPN mode (stacks/arr-hostvpn): every container shares the PC's VPN,
  # so compare against the VPN interface instead of a "home IP".
  echo "Host-VPN mode (no gluetun)."
  vpn_if="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(proton|pvpn|tun|wg)' | head -1)"
  if [[ -n "$vpn_if" ]]; then echo "VPN interface on host:    $vpn_if (up)"
  else echo "!! No VPN interface found (proton*/tun*/wg*). Is the VPN connected?"; ok=0; fi
  echo "Public IP seen by the PC: $(curl -s --max-time 10 https://ipinfo.io/ip)  (should be a Proton IP)"
  for c in radarr sonarr prowlarr qbittorrent; do
    podman container exists "$c" 2>/dev/null || continue
    printf '%-12s %s\n' "$c" "$(podman exec "$c" curl -s --max-time 10 https://ipinfo.io/ip)"
  done
  bound="$(podman exec qbittorrent sh -c "grep -E '^Session\\\\Interface=' /config/qBittorrent/qBittorrent.conf" 2>/dev/null | cut -d= -f2)"
  echo
  if [[ -n "$bound" ]]; then echo "qBittorrent bound to interface: $bound (good - it stops if the VPN drops)"
  else echo "!! qBittorrent is NOT bound to the VPN interface (Options -> Advanced -> Network interface)"; ok=0; fi
  [[ $ok == 1 ]] || exit 1
  exit 0
fi

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
