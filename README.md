# podman-homelab

Rootless Podman containers for my machines, managed as **Quadlets** (systemd
units generated from `.container` files). No docker-compose, no root daemon:
each container is a normal `systemctl --user` service that starts on login,
restarts on failure and updates itself.

```
hosts/            which stacks run on which machine
  gaming-pc.conf
  server.conf     (future always-on box)
stacks/           one folder per group of related containers
  network/        shared "homelab" network (always deployed)
  dashboard/      Homepage + Uptime Kuma
  sync/           Syncthing
  media/          Jellyfin + Jellyseerr
  arr/            VPN pod: Gluetun + Radarr, Sonarr, Prowlarr, qBittorrent, Bazarr, FlareSolverr
  ai/             Ollama + Open WebUI
  gaming/         Minecraft server (on-demand)
  dns/            AdGuard Home (meant for the server)
scripts/
  deploy.sh       install/update a host's stacks
  undeploy.sh     remove everything (keeps data)
  open-firewall.sh  open ports for LAN access
  vpn-check.sh    prove the VPN pod isn't leaking your real IP
```

## What runs on the gaming PC

| Service | Port | Why it's on the gaming PC |
|---|---|---|
| Homepage | 3000 | One page with links + CPU/RAM stats for everything |
| Uptime Kuma | 3001 | Monitors services, alerts you when something dies |
| Syncthing | 8384 | Sync game saves/screenshots between devices; later, mirror data to the server |
| Jellyfin | 8096 | Stream your own movies/TV to TV/phone; can use the GPU to transcode |
| Ollama + Open WebUI | 3080 | Local AI chat on your GPU, uses the spare RAM |
| Minecraft (Paper) | 25565 | Game server for friends, started only when you want it |
| Jellyseerr | 5055 | "Request a movie/show" page; sends requests to Radarr/Sonarr |
| Radarr / Sonarr | 7878 / 8989 | Find, download, rename and file movies / TV (via VPN) |
| Prowlarr | 9696 | Add indexers once; syncs them to Radarr + Sonarr (via VPN) |
| qBittorrent | 8080 | Download client (via VPN only) |
| Bazarr | 6767 | Automatic subtitles (via VPN) |
| FlareSolverr | internal | Gets Prowlarr past Cloudflare checks on some indexers (via VPN) |

Every background container gets `CPUWeight=20` / `IOWeight=20`, so when a game
is running it wins any fight for CPU and disk. Minecraft has a hard 5 GB RAM cap
and Ollama unloads models from VRAM after 5 minutes idle.

**Left for the always-on server**, because they're only useful if they never go
down: AdGuard Home/Pi-hole (DNS), Vaultwarden (passwords), Nextcloud/Immich
(cloud files/photos), Home Assistant, a reverse proxy (Caddy) and Tailscale.

## First-time setup (Fedora / Bazzite / Nobara)

Podman ships with Fedora-based distros. **Podman 5+ is required** (the VPN
stack uses Quadlet pods). Check with:

```bash
podman --version
```

Clone the repo and deploy:

```bash
git clone <your-repo-url> ~/podman-homelab
cd ~/podman-homelab
./scripts/deploy.sh gaming-pc
```

Then open http://localhost:3000.

### Before you deploy, edit these

- **Minecraft:** set `EULA=TRUE` in `stacks/gaming/minecraft.container` (you're accepting Mojang's EULA). Start it with `systemctl --user start minecraft`.
- **Jellyfin:** change `%h/Videos` to wherever your media lives.
- **GPU:** uncomment the right lines in `stacks/media/jellyfin.container` and `stacks/ai/ollama.container`.
  - *AMD/Intel:* the `/dev/dri` lines; for Ollama on AMD also switch the image tag to `:rocm` and add `/dev/kfd`.
  - *NVIDIA:* install `nvidia-container-toolkit` (Bazzite's NVIDIA images already have it), then generate the CDI spec:
    ```bash
    sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
    ```

### Optional

Keep services running even when you're logged out (and start them at boot):

```bash
sudo loginctl enable-linger $USER
```

Reach services from your phone or other PCs:

```bash
./scripts/open-firewall.sh
```

## VPN download stack (`stacks/arr`)

```
            internet
               ^
               | encrypted WireGuard/OpenVPN tunnel only
   +-----------+-------------------------------------------+
   | pod "vpn" (one shared network namespace)              |
   |  gluetun: VPN + kill-switch firewall + DNS-over-TLS   |
   |  qbittorrent  radarr  sonarr  prowlarr  bazarr        |
   |  flaresolverr        (talk to each other on localhost)|
   +-----------+-------------------------------------------+
               | web UIs only (7878 8989 9696 8080 6767)
          your PC / LAN  <-- Jellyfin, Jellyseerr, Homepage
```

How it protects you:

- **Kill switch.** Gluetun's firewall drops all traffic that isn't going through the tunnel. If the VPN drops, the apps go offline. They never fall back to your home IP.
- **Fail-closed startup.** Gluetun only reports "started" once the VPN is healthy, and every app is `BindsTo=gluetun`. So the apps never start before the tunnel is up, they stop if Gluetun dies, and they come back with it.
- **No DNS leaks.** The pod's DNS is `127.0.0.1` (Gluetun), which resolves over encrypted DNS inside the tunnel. Your ISP's resolver is never used.
- **No incoming torrent port on your home IP.** Only the web UIs are published on your PC. Peers reach qBittorrent through the VPN's forwarded port.
- **Secrets stay out of git.** VPN keys live in `~/homelab/gluetun/vpn.env` (mode 600), not in this repo.
- **Rootless containers.** If one is compromised, the attacker gets your unprivileged user, not root.

A VPN hides your traffic from your ISP and hides your IP from peers. It does not
make it legal to download content you don't have the rights to.

### Setup

1. **ProtonVPN Plus (or higher)** is required. P2P servers and port forwarding
   aren't on the free plan.
2. Run `./scripts/deploy.sh gaming-pc` once. It creates `~/homelab/gluetun/vpn.env`
   and the `~/data` folders, and holds the VPN apps back until the VPN is configured.
3. Make a WireGuard key: [account.protonvpn.com](https://account.protonvpn.com) ->
   *Downloads* -> *WireGuard configuration*. Choose platform *Router*, turn
   **NAT-PMP (Port Forwarding) ON**, leave Moderate NAT off, and set NetShield off.
   Pick any P2P server and click *Create*. Copy only the `PrivateKey = ...` value
   into `WIREGUARD_PRIVATE_KEY` in `~/homelab/gluetun/vpn.env`. Optionally set
   `SERVER_COUNTRIES` to the country nearest you.
4. Run `./scripts/deploy.sh gaming-pc` again, then check for leaks:
   ```bash
   ./scripts/vpn-check.sh
   ```
   Every container should show an IP that is **not** your home IP, along with a forwarded port.
5. Connect the apps (all inside the pod, so the host is always `localhost`):
   - **qBittorrent** (http://localhost:8080). Get the temporary password with
     `journalctl --user -u qbittorrent | grep -i password`, then change it.
     Under *Options -> Downloads*, set the default save path to `/data/torrents`.
     Under *Options -> Web UI*, turn on **Bypass authentication for clients on
     localhost**. Gluetun then sets the listening port (Proton changes it on every
     reconnect) and pins qBittorrent to the VPN interface automatically. Restart
     Gluetun once so it pushes the port: `systemctl --user restart gluetun`.
   - **Prowlarr** (http://localhost:9696). Add your indexers. Under *Settings -> Indexers*,
     add FlareSolverr at `http://localhost:8191`. Under *Settings -> Apps*, add Radarr
     (`http://localhost:7878`) and Sonarr (`http://localhost:8989`) with their API keys
     (found in each app under *Settings -> General*).
   - **Radarr / Sonarr.** Add qBittorrent as the download client (`localhost`, port 8080)
     with category `movies` / `tv`. Set the root folder to `/data/media/movies` / `/data/media/tv`.
   - **Bazarr** (http://localhost:6767). Connect Radarr and Sonarr (`localhost`), then pick subtitle providers.
   - **Jellyfin.** Add libraries `/data/media/movies` and `/data/media/tv`.
   - **Jellyseerr** (http://localhost:5055). It sits outside the pod, so use Jellyfin
     at `http://jellyfin:8096`, and Radarr/Sonarr at host `host.containers.internal`
     ports 7878 / 8989.

### Folder layout

Everything uses one tree, `~/data`. Radarr and Sonarr can then *hardlink* finished
downloads into the library: imports are instant, take no extra space, and seeding continues.

```
~/data
├── torrents/{movies,tv}   <- qBittorrent downloads here
└── media/{movies,tv}      <- Radarr/Sonarr file things here; Jellyfin reads it
```

To keep it on a bigger drive, mount the drive at `~/data` (or replace `%h/data`
in the `.container` files). `torrents` and `media` must be on the **same drive**
for hardlinks to work.

### Troubleshooting

- `journalctl --user -u gluetun -f` shows the VPN connecting and any auth errors.
- If a web UI won't load but the VPN is up, check `systemctl --user status vpn-pod`.
- Gluetun restarting in a loop usually means a bad key, or a country with no Proton P2P servers. Remove `SERVER_COUNTRIES` to test.
- No forwarded port means the WireGuard key was made without NAT-PMP. Make a new key with it ON.
- qBittorrent's port not updating: check *Bypass authentication for clients on localhost* is on, then look for `setPreferences` in `journalctl --user -u gluetun`.

## Day to day

```bash
./scripts/deploy.sh gaming-pc            # after editing anything in the repo
./scripts/deploy.sh gaming-pc --check    # validate without changing anything
podman ps                                # what's running
systemctl --user status jellyfin         # one service
journalctl --user -u jellyfin -f         # its logs
./scripts/vpn-check.sh                   # confirm the VPN pod isn't leaking
systemctl --user start minecraft         # on-demand services
podman auto-update                       # update images now (a timer also runs this daily)
```

Data lives in named Podman volumes (`podman volume ls`) and in `~/homelab/`
(Homepage config, Syncthing). Back those up; the repo itself holds no data.

## Adding a service

1. Create `stacks/<stack>/<name>.container` (copy an existing one).
2. Use a full image name (`docker.io/...`, `ghcr.io/...`) so auto-update works.
3. Add the stack to `hosts/<host>.conf` if it's new.
4. Run `./scripts/deploy.sh <host>`.

Leave out the `[Install]` section for services that should only start when you
start them. All keys are documented in
[podman-systemd.unit(5)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).

## Adding the server later

Fill in `hosts/server.conf`, clone the repo on that machine and run
`./scripts/deploy.sh server`. The same stack files work on both machines.
