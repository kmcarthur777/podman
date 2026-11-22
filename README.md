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
  media/          Jellyfin
  ai/             Ollama + Open WebUI
  gaming/         Minecraft server (on-demand)
  dns/            AdGuard Home (meant for the server)
scripts/
  deploy.sh       install/update a host's stacks
  undeploy.sh     remove everything (keeps data)
  open-firewall.sh  open ports for LAN access
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

Every background container gets `CPUWeight=20` / `IOWeight=20`, so when a game
is running it wins any fight for CPU and disk. Minecraft has a hard 5 GB RAM cap
and Ollama unloads models from VRAM after 5 minutes idle.

**Left for the always-on server**, because they're only useful if they never go
down: AdGuard Home/Pi-hole (DNS), Vaultwarden (passwords), Nextcloud/Immich
(cloud files/photos), Home Assistant, a reverse proxy (Caddy) and Tailscale.

## First-time setup (Fedora / Bazzite / Nobara)

Podman ships with Fedora-based distros. Check you have v5+:

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

## Day to day

```bash
./scripts/deploy.sh gaming-pc            # after editing anything in the repo
./scripts/deploy.sh gaming-pc --check    # validate without changing anything
podman ps                                # what's running
systemctl --user status jellyfin         # one service
journalctl --user -u jellyfin -f         # its logs
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
