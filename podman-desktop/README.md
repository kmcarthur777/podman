# Using this repo with Podman Desktop

Podman Desktop is a window onto the same rootless Podman that `deploy.sh` uses.
Anything you start either way shows up in Podman Desktop: logs, a terminal
inside each container, stats, and start/stop/restart.

On Fedora, Podman Desktop is usually installed as a Flatpak and talks to the
system's Podman through its socket. If Podman Desktop says it can't connect, run:

```bash
systemctl --user enable --now podman.socket
```

## Option A (recommended): deploy once, manage in Podman Desktop

```bash
./scripts/deploy.sh gaming-pc
```

That's the only terminal step. After it, every service appears under
**Containers** and **Pods** in Podman Desktop. Compared with importing by hand, you also get:

- start at login/boot (systemd)
- automatic image updates (`podman auto-update` timer)
- dependency ordering (Open WebUI waits for Ollama, and in the Gluetun stack the apps wait for the VPN)

> Restarting a container from Podman Desktop works. To *remove* one for good, take
> its stack out of `hosts/gaming-pc.conf` and re-run `deploy.sh`. Otherwise systemd
> recreates it at the next login.

For a Quadlet view in the GUI, look for the **Podman Quadlet** extension under
*Extensions -> Catalog*. It lists the services this repo installed and can start or stop them.

## Option B: import the download stack in the GUI

`arr-hostvpn.kube.yaml` contains Radarr, Sonarr, Prowlarr, Bazarr, FlareSolverr and
qBittorrent (the same design as `stacks/arr-hostvpn`: it relies on the ProtonVPN app).

1. One-time prep in a terminal: create the folders and let containers read them (SELinux).
   ```bash
   mkdir -p ~/data/{torrents,media}/{movies,tv}
   ```
   ```bash
   chcon -R -t container_file_t ~/data
   ```
2. Find your home folder path:
   ```bash
   echo $HOME
   ```
   Then open `arr-hostvpn.kube.yaml` and replace both `/var/home/CHANGE_ME` with it.
   Bazzite and other atomic Fedora systems use `/var/home/you`, while regular Fedora uses `/home/you`.
3. In Podman Desktop go to **Pods -> Play Kubernetes YAML**, pick the file, and click **Play**.
4. Two pods appear: `arr` (Radarr, Sonarr, Prowlarr, Bazarr, FlareSolverr) and `qbittorrent`.

Differences from Option A:
- **Addresses.** Inside the `arr` pod the apps reach each other on `localhost`. In Prowlarr,
  use `http://localhost:7878` for Radarr, `http://localhost:8989` for Sonarr and
  `http://localhost:8191` for FlareSolverr. In Radarr and Sonarr, qBittorrent's host is `host.containers.internal`, port 8080.
- **No automatic start at boot.** To get it, enable Podman's restart service once:
  ```bash
  systemctl --user enable podman-restart.service
  ```
- **No automatic image updates.** To update, remove the pods in Podman Desktop and play the YAML again. Your settings live in named volumes and are kept.
- **Don't run both.** Don't also deploy `arr-hostvpn` with `deploy.sh`, because the ports would clash.
  Both use the same volumes, so you can switch between A and B without losing settings.

The VPN safety settings from the main README still apply: turn on the kill switch in
the ProtonVPN app, and bind qBittorrent to the VPN interface (`proton0`).
