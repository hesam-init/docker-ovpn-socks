# Docker Host Setup: Arch Linux

This guide installs Docker Engine, the Compose v2 plugin and Buildx on Arch Linux (and Arch-based distros such as EndeavourOS, Manjaro or CachyOS), enables the Docker service, and prepares the host to run this project's VPN containers.

---

## 1. Install Packages

```bash
sudo pacman -Syu --needed docker docker-compose docker-buildx make git
```

| Package          | Why it is needed                                                                 |
| ---------------- | -------------------------------------------------------------------------------- |
| `docker`         | Docker Engine (`dockerd`), the `docker` CLI and containerd                        |
| `docker-compose` | Compose v2, installed as the `docker compose` CLI plugin                          |
| `docker-buildx`  | Buildx. `make` runs `docker buildx bake --allow=network.host ...` to build images |
| `make`, `git`    | Clone the repo and run the `Makefile` targets                                    |

> [!NOTE]
> Without `docker-buildx`, Docker falls back to the legacy builder and `make` fails. `make build-raw` (plain `docker build`) still works, but the default build path needs Buildx.

---

## 2. Enable the Docker Service

Start Docker now and enable it at boot:

```bash
sudo systemctl enable --now docker.service
```

Check that it is running:

```bash
systemctl status docker.service --no-pager
```

> [!NOTE]
> **Socket activation instead**: to start `dockerd` only when something first talks to the socket, enable `docker.socket` instead of `docker.service`: `sudo systemctl enable --now docker.socket`. Containers with `restart: unless-stopped` only come back after a reboot once the daemon starts, so for an always-on proxy host, enable `docker.service`.

---

## 3. Add Your User to the `docker` Group

The `docker` group is created by the package. Membership lets you run `docker` without `sudo`:

```bash
sudo usermod -aG docker "$USER"
```

Group changes apply only to new login sessions. Log out and back in, or reboot. To use the new group in the current shell only:

```bash
newgrp docker
```

Confirm membership:

```bash
id -nG | grep -qw docker && echo "in docker group"
```

> [!WARNING]
> Members of the `docker` group effectively have root access to the host, since they can start a privileged container with the host filesystem mounted. Only add trusted users.

---

## 4. Host Kernel Prerequisites

The containers need `/dev/net/tun` (mounted from the host) and `NET_ADMIN`. Make sure the `tun` module is loaded:

```bash
sudo modprobe tun
ls -l /dev/net/tun
```

Load it at every boot:

```bash
echo tun | sudo tee /etc/modules-load.d/tun.conf
```

If you use the macvlan setup in [bridge.md](bridge.md), the `macvlan` module is loaded automatically when the network is created. You can check with `lsmod | grep macvlan`.

> [!NOTE]
> If `modprobe` fails with `Module tun not found` right after a kernel upgrade, the running kernel no longer matches the installed modules. Reboot into the new kernel.

---

## 5. Verify the Installation

```bash
docker version
docker compose version
docker buildx version
```

Run a test container. On networks where Docker Hub is unreachable, pull the same mirror the project's `docker/Dockerfile` uses:

```bash
docker run --rm hello-world
# or, on restricted networks:
docker run --rm docker.arvancloud.ir/alpine:3.24 echo ok
```

Then build the project images from the repo root:

```bash
cd docker-ovpn-socks
make
```

---

## 6. Troubleshooting

| Symptom | Cause / Fix |
| ------- | ----------- |
| `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock` | Your session predates the group change. Log out and back in, or run `newgrp docker`. |
| `Cannot connect to the Docker daemon ... Is the docker daemon running?` | Run `sudo systemctl enable --now docker.service` and check `journalctl -u docker.service -b`. |
| `docker: 'compose' is not a docker command` | Install `docker-compose` (it provides the CLI plugin in `/usr/lib/docker/cli-plugins/`). |
| `make` fails with `unknown flag: --allow` or `docker: 'buildx' is not a docker command` | Buildx is missing or too old. Install or update `docker-buildx`, or use `make build-raw`. |
| Container exits with `Cannot open TUN/TAP dev /dev/net/tun` | Load the `tun` module (step 4). |
