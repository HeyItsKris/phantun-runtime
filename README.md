# phantun-runtime

A minimal, runtime-only container for executing official phantun binaries with strict responsibility and privilege boundaries.

## Overview

phantun-runtime is a thin execution wrapper around upstream phantun binaries. The container itself does not modify system configuration, does not manage networking policy, and does not interpret phantun parameters. Its sole responsibility is to select execution mode and execute phantun as-is. This project is designed for environments where predictability, auditability, and clear separation of responsibility are required.

For detailed design rationale, see DESIGN.md and DESIGN-CN.md.

## Design Principles

This project follows a small set of explicit principles: least responsibility, least privilege, no implicit system-side behavior, full upstream compatibility, and predictable runtime behavior. The container is intentionally not a management or orchestration layer.

## Execution Mode

phantun-runtime supports exactly two execution modes: client and server. The execution mode is selected via the MODE environment variable. No phantun parameters are interpreted, validated, or modified by the container.

## Usage

The container must be provided access to a TUN device and the NET_ADMIN capability. All runtime parameters are passed verbatim to the upstream phantun binary.

Client mode example:

docker run --rm \
  --network host \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=client \
  phantun-runtime \
  <phantun client arguments>

Server mode example:

docker run --rm \
  --network host \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=server \
  phantun-runtime \
  <phantun server arguments>

All arguments are forwarded unchanged to phantun.

## Permissions and Security

The container requires access to /dev/net/tun and the NET_ADMIN Linux capability. It must not be run in privileged mode. The container does not modify sysctl parameters, routing tables, firewall rules, NAT configuration, or any other system-level networking state. All such configuration must be handled externally by the host system or platform administrator.

## Linux Host Setup (iptables/nftables)

Phantun is Linux-only. Run the container with `--network host` so the TUN interface exists in the host namespace where firewall/NAT rules are applied. The container never changes host networking. The steps below are adapted from the upstream phantun guide: https://github.com/dndx/phantun#usage.

### 1) Enable kernel IP forwarding

```sh
sudo sysctl -w net.ipv4.ip_forward=1
```

For IPv6:

```sh
sudo sysctl -w net.ipv6.conf.all.forwarding=1
```

### 2) Add required firewall/NAT rules

Replace `TUN_IF`, `WAN_IF`, and ports to match your setup. If you changed phantun's TUN IPs, update the DNAT targets accordingly.

#### Client (SNAT/masquerade)

**nftables**

```sh
TUN_IF=ptun0
WAN_IF=eth0

sudo nft add table inet nat
sudo nft 'add chain inet nat postrouting { type nat hook postrouting priority srcnat; policy accept; }'
sudo nft add rule inet nat postrouting iifname "$TUN_IF" oifname "$WAN_IF" masquerade
```

**iptables**

```sh
WAN_IF=eth0
sudo iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
sudo ip6tables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
```

#### Server (DNAT TCP listen port to TUN IP)

Phantun server defaults to `192.168.201.2` and `fcc9::2` on the TUN side unless you change them via phantun options.

**nftables**

```sh
WAN_IF=eth0
PORT=4567

sudo nft add table inet nat
sudo nft 'add chain inet nat prerouting { type nat hook prerouting priority dstnat; policy accept; }'
sudo nft add rule inet nat prerouting iifname "$WAN_IF" tcp dport "$PORT" dnat ip to 192.168.201.2
sudo nft add rule inet nat prerouting iifname "$WAN_IF" tcp dport "$PORT" dnat ip6 to fcc9::2
```

**iptables**

```sh
WAN_IF=eth0
PORT=4567

sudo iptables -t nat -A PREROUTING -p tcp -i "$WAN_IF" --dport "$PORT" -j DNAT --to-destination 192.168.201.2
sudo ip6tables -t nat -A PREROUTING -p tcp -i "$WAN_IF" --dport "$PORT" -j DNAT --to-destination fcc9::2
```

Notes:
- If you do not need IPv6, omit the IPv6 rules.
- If you manage firewalling via UFW/firewalld, integrate these rules there instead of using raw commands.

## Building the Image

The image can be built locally using the standard Docker build process.

docker build -t phantun-runtime .

By default, the build uses a dev-friendly `git clone` + `cargo build` from the upstream default branch. Integrity verification is opt-in: if you provide `PHANTUN_TARBALL_SHA256`, the build downloads a tarball and verifies its SHA256 before building. If `PHANTUN_COMMIT` is also provided, that commit is used; otherwise the current default-branch HEAD is used.

### Build Tutorial (Detailed)

Basic build (default branch HEAD, no verification):

```sh
docker build -t phantun-runtime:dev .
```

Build a specific commit (no verification):

```sh
docker build \
  --build-arg PHANTUN_COMMIT=<commit> \
  -t phantun-runtime:commit .
```

Verified build with tarball SHA256:

```sh
git ls-remote https://github.com/dndx/phantun HEAD
curl -fsSL -o phantun.tar.gz \
  https://github.com/dndx/phantun/archive/<commit>.tar.gz
sha256sum phantun.tar.gz
```

```sh
docker build \
  --build-arg PHANTUN_COMMIT=<commit> \
  --build-arg PHANTUN_TARBALL_SHA256=<sha256> \
  -t phantun-runtime:verified .
```

Notes:
- If you set `PHANTUN_TARBALL_SHA256` without `PHANTUN_COMMIT`, the build resolves the default-branch HEAD at build time. To avoid drift, pass both.
- You can override the upstream with `PHANTUN_OWNER` and `PHANTUN_REPO` if you build from a fork.

### Cross-Platform Builds

This Dockerfile builds for the builder's platform by default. For other platforms, use Docker Buildx with QEMU emulation:

```sh
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t phantun-runtime:multiarch --push .
```

For a single non-native platform without pushing:

```sh
docker buildx build --platform linux/arm64 \
  -t phantun-runtime:arm64 --load .
```

Export a single-platform image as a tarball:

```sh
docker buildx build --platform linux/arm64 \
  --output type=docker,dest=phantun-runtime-arm64.tar .
```

If you need true cross-compilation inside the builder (without QEMU), you must add the Rust target and system toolchain yourself (not configured by default).

## Versioning Policy

Container versions reflect changes to the runtime wrapper only. All phantun functionality, parameters, and behavior are defined exclusively by upstream. Updating phantun parameters or features does not require changes to this container.

## Scope and Non-Goals

This project does not aim to simplify phantun configuration, provide orchestration or management features, act as a VPN manager, or introduce automation or hidden defaults. These concerns are intentionally left to higher-level systems.

## License and Upstream

phantun-runtime does not modify or fork phantun. All phantun-related functionality remains under the original upstream license and ownership.
