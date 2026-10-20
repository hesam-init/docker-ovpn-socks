# Docker Host Setup: Debian-Based Distros

This guide installs Docker Engine, the Compose v2 plugin and Buildx on Debian, Ubuntu and their derivatives (Linux Mint, LMDE, Pop!_OS and others), enables the Docker service, and prepares the host to run this project's VPN containers.

> [!NOTE]
> The commands below use bash syntax (`$(...)`, heredocs). If your login shell is fish or zsh with unusual options, run `bash` first.

---

## 1. Install Packages

Pick one option. **Option A** gives current Docker releases and is recommended. **Option B** uses the distro's own packages (Debian 12/13 `main` or Ubuntu's archive), which helps when `download.docker.com` is unreachable from your network.

### Option A: Docker's Official apt Repository (recommended)

**1. Remove conflicting packages** that may come from the distro:

```bash
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg"
done
```

**2. Add Docker's signing key.** Set `DISTRO` to `debian` on Debian/LMDE, or `ubuntu` on Ubuntu/Mint/Pop!_OS:

```bash
DISTRO=debian   # or: ubuntu

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

**3. Add the repository.** The suite must be the codename of the *upstream* release. Derivatives such as Mint report their own codename in `VERSION_CODENAME`, so the line below prefers `UBUNTU_CODENAME` / `DEBIAN_CODENAME` when they are set:

```bash
. /etc/os-release
SUITE="${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-$VERSION_CODENAME}}"

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${DISTRO}
Suites: ${SUITE}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

**4. Install Docker:**

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin make git
```

| Package                 | Why it is needed                                                                  |
| ----------------------- | --------------------------------------------------------------------------------- |
| `docker-ce`, `docker-ce-cli`, `containerd.io` | Docker Engine, the `docker` CLI and the container runtime   |
| `docker-compose-plugin` | Compose v2, used as `docker compose`                                              |
| `docker-buildx-plugin`  | Buildx. `make` runs `docker buildx bake --allow=network.host ...` to build images |
| `make`, `git`           | Clone the repo and run the `Makefile` targets                                     |

### Option B: Distro Packages

Use these when Docker's repository is blocked or you prefer distro-maintained packages.

**Ubuntu 24.04+ (and derivatives based on it):**

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 docker-buildx make git
```

**Debian 12 (bookworm) and 13 (trixie): Debian's `main` repo**

Debian ships Docker in its own `main` repository, so you don't need any extra apt source. The versions differ a lot between releases:

| Package          | Debian 12 (bookworm)       | Debian 13 (trixie)               |
| ---------------- | -------------------------- | -------------------------------- |
| `docker.io`      | 20.10.24                   | 26.1.5                           |
| `docker-compose` | 1.29.2 (legacy v1, Python) | 2.26.1 (v2, `docker compose`)    |
| `docker-buildx`  | not packaged               | 0.13.1                           |

*Debian 13:*

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose docker-buildx make git
```

Here `docker-compose` and `docker-buildx` install as CLI plugins in `/usr/libexec/docker/cli-plugins/`, so `docker compose` and `docker buildx` both work. However, Buildx 0.13 has no `bake --allow` flag (it was added in Buildx 0.18), so **plain `make` fails. Build with `make raw` instead**, which builds the same images with `docker build --network host`.

*Debian 12:*

```bash
sudo apt-get update
sudo apt-get install -y docker.io make git
```

Skip Debian 12's `docker-compose` package: it is the legacy v1 `docker-compose` tool and doesn't provide the `docker compose` command used throughout this project. Instead, install the Compose v2 plugin binary by hand. Pin a 2.x release, because newer major versions may require a newer engine than 20.10:

```bash
COMPOSE_VERSION=v2.29.7
ARCH=$(uname -m)   # x86_64 or aarch64

sudo install -d /usr/local/lib/docker/cli-plugins
sudo curl -fSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
```

Buildx isn't packaged for Debian 12, so **build with `make raw`**, which works with Engine 20.10's built-in builder.

> [!NOTE]
> On Ubuntu 22.04 and older, the distro's `docker-compose` is also the legacy v1 tool. Use Option A there. Do not mix Option A and Option B packages on the same host.

---

## 2. Enable the Docker Service

The packages usually start Docker on install. Make sure it is enabled at boot:

```bash
sudo systemctl enable --now docker.service containerd.service
systemctl status docker.service --no-pager
```

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

---

## 5. Verify the Installation

```bash
docker version
docker compose version
docker buildx version   # not available on Debian 12 main-repo installs
```

Run a test container. On networks where Docker Hub is unreachable, pull the same mirror the project's `Dockerfile` uses:

```bash
docker run --rm hello-world
# or, on restricted networks:
docker run --rm docker.arvancloud.ir/alpine:3.24 echo ok
```

Then build the project images from the repo root:

```bash
cd docker-ovpn-socks
make        # Option A, or Ubuntu 24.04+ packages
make raw    # Debian 12/13 main-repo packages (Buildx missing or too old for bake --allow)
```

---

## 6. Troubleshooting

| Symptom | Cause / Fix |
| ------- | ----------- |
| `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock` | Your session predates the group change. Log out and back in, or run `newgrp docker`. |
| `Cannot connect to the Docker daemon ... Is the docker daemon running?` | Run `sudo systemctl enable --now docker.service` and check `journalctl -u docker.service -b`. |
| `apt-get update` fails with `NO_PUBKEY` or `Signed-By` errors | The keyring path in `docker.sources` doesn't match `/etc/apt/keyrings/docker.asc`, or the key wasn't downloaded. Redo step 2 of Option A. |
| `apt-get update` 404s on `download.docker.com` | `Suites:` is set to a derivative's codename (e.g. a Mint release name). Set it to the upstream Ubuntu/Debian codename. |
| `docker: 'compose' is not a docker command` | Install `docker-compose-plugin` (Option A), `docker-compose-v2` (Ubuntu) or `docker-compose` (Debian 13). On Debian 12, install the Compose v2 plugin binary by hand (Option B). |
| `make` fails with `unknown flag: --allow` or `docker: 'buildx' is not a docker command` | Buildx is missing (Debian 12) or older than 0.18 (Debian 13's 0.13.1). Use `make raw`, or switch to Option A for a current `docker-buildx-plugin`. |
| Container exits with `Cannot open TUN/TAP dev /dev/net/tun` | Load the `tun` module (step 4). |
