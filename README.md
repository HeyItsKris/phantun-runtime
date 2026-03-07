# phantun-runtime

A minimal, runtime-only container for executing phantun binaries from a selected source repo with strict responsibility and privilege boundaries.

## Overview

phantun-runtime is a thin execution wrapper around phantun binaries. The container itself does not modify system configuration, does not manage networking policy, and does not interpret phantun parameters. Its sole responsibility is to select execution mode and execute phantun as-is. This project is designed for environments where predictability, auditability, and clear separation of responsibility are required.

For detailed design rationale, see DESIGN.md and DESIGN-CN.md.

## Design Principles

This project follows a small set of explicit principles: least responsibility, least privilege, no implicit system-side behavior, full upstream compatibility, and predictable runtime behavior. The container is intentionally not a management or orchestration layer.

## Execution Mode

phantun-runtime supports exactly two execution modes: client and server. The execution mode is selected via the MODE environment variable. No phantun parameters are interpreted, validated, or modified by the container.

## Usage

The container must be provided access to a TUN device and minimal capabilities (`--cap-drop ALL --cap-add NET_ADMIN`). All runtime parameters are passed verbatim to the phantun binary.

Client mode example (detached):

docker run -d --name phantun-client --restart unless-stopped \
  --network host \
  --device /dev/net/tun \
  --cap-drop ALL \
  --cap-add NET_ADMIN \
  -e MODE=client \
  -e RUST_LOG=info \
  phantun-runtime \
  <phantun client arguments>

Server mode example (detached):

docker run -d --name phantun-server --restart unless-stopped \
  --network host \
  --device /dev/net/tun \
  --cap-drop ALL \
  --cap-add NET_ADMIN \
  -e MODE=server \
  -e RUST_LOG=info \
  phantun-runtime \
  <phantun server arguments>

All arguments are forwarded unchanged to phantun.

## Optional Control-Plane Passthrough

If your phantun build supports control-plane flags (for example `--control-target`), pass them directly as normal phantun arguments. The container does not parse, validate, or synchronize control-plane behavior.

Example (server with UDS target):

```sh
docker run -d --name phantun-server --restart unless-stopped \
  --network host \
  --device /dev/net/tun \
  --cap-drop ALL \
  --cap-add NET_ADMIN \
  -e MODE=server \
  -e RUST_LOG=info \
  -v /run/phantun-cp:/run/phantun-cp \
  phantun-runtime \
  --local 4567 --remote 127.0.0.1:1234 --tun ptun0 \
  --control-target /run/phantun-cp/agent.sock
```

Notes:
- Start the control-plane consumer before starting the container.
- The UDS path passed to phantun must exist in the container namespace (use bind mounts as needed).

## Shutdown Semantics

`docker stop` sends `SIGTERM` first, then `SIGKILL` after the container stop timeout. If your phantun build uses graceful control-plane shutdown, provide enough stop timeout so it can complete before a forced kill.

Recommended:

```sh
docker run -d --name phantun-server --restart unless-stopped \
  --stop-timeout 5 \
  --network host \
  --device /dev/net/tun \
  --cap-drop ALL \
  --cap-add NET_ADMIN \
  -e MODE=server \
  -e RUST_LOG=info \
  phantun-runtime \
  <phantun server arguments>
```

## Permissions and Security

The container requires access to /dev/net/tun and the NET_ADMIN Linux capability. Recommended runtime flags are `--cap-drop ALL --cap-add NET_ADMIN`; it must not be run in privileged mode. The container does not modify sysctl parameters, routing tables, firewall rules, NAT configuration, or any other system-level networking state. All such configuration must be handled externally by the host system or platform administrator.

## Linux Host Setup (iptables/nftables)

Phantun is Linux-only. Run the container with `--network host` so the TUN interface exists in the host namespace where firewall/NAT rules are applied. The container never changes host networking. The steps below are adapted from the phantun guide in the default source repo: https://github.com/HeyItsKris/phantun#usage.

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

By default, the build uses a dev-friendly `git clone` + `cargo build` from the default source repo (`PHANTUN_OWNER=HeyItsKris`, `PHANTUN_REPO=phantun`). Integrity verification is opt-in: if you provide `PHANTUN_TARBALL_SHA256`, the build downloads a tarball and verifies its SHA256 before building. If `PHANTUN_COMMIT` is also provided, that commit is used; otherwise the current default-branch HEAD is used.

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
git ls-remote https://github.com/HeyItsKris/phantun HEAD
curl -fsSL -o phantun.tar.gz \
  https://github.com/HeyItsKris/phantun/archive/<commit>.tar.gz
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
- You can override the default source repo with `PHANTUN_OWNER` and `PHANTUN_REPO`.

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

Container versions reflect changes to the runtime wrapper only. All phantun functionality, parameters, and behavior are defined exclusively by the selected phantun source repository. Updating phantun parameters or features does not require changes to this container.

## Scope and Non-Goals

This project does not aim to simplify phantun configuration, provide orchestration or management features, act as a VPN manager, or introduce automation or hidden defaults. These concerns are intentionally left to higher-level systems.

## License and Source

phantun-runtime does not patch phantun source. All phantun-related functionality remains under the source repository's original license and ownership.
