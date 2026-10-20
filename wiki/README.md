# Wiki

Guides for setting up the Docker host and advanced networking. See the [main README](../README.md) for usage.

- [Docker Host Setup: Arch Linux](install-arch.md): install Docker, Compose and Buildx with pacman, enable the service, add your user to the `docker` group, and load the `tun` module.
- [Docker Host Setup: Debian-Based Distros](install-debian.md): the same for Debian, Ubuntu and derivatives, using Docker's apt repository or the distro packages (including Debian 12/13's `main` repo).
- [Macvlan & Bridge Networking](bridge.md): give each VPN container its own LAN IP, set up the host shim, and how the table 128 policy routing works.
