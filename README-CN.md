# phantun-runtime

phantun-runtime 是一个仅用于运行官方 phantun 二进制程序的最小化运行时容器，严格遵守最小职责与最小权限原则。

## 项目概述

phantun-runtime 是围绕上游 phantun 二进制构建的轻量级执行封装。容器本身不修改系统配置、不管理网络策略，也不理解或重写 phantun 的参数，其唯一职责是根据明确指定的运行模式启动 phantun 程序。本项目适用于对可预测性、可审计性以及职责边界有严格要求的运行环境。

完整的设计理念与安全模型请参阅 DESIGN.md 与 DESIGN-CN.md。

## 设计原则

本项目遵循以下核心原则：最小职责、最小权限、无隐式系统行为、完全兼容上游以及行为可预测。容器本身不是管理平台，也不会替用户做任何系统层面的决策。

## 运行模式

phantun-runtime 仅支持两种运行模式：client 与 server。运行模式通过环境变量 MODE 明确指定。容器不会解析、校验或修改 phantun 参数。

## 使用方法

运行容器时必须提供 TUN 设备访问权限以及 NET_ADMIN capability。所有运行参数都会被完整、原样地传递给上游 phantun 程序。

客户端模式示例（后台运行）：

docker run -d --name phantun-client --restart unless-stopped \
  --network host \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=client \
  -e RUST_LOG=info \
  phantun-runtime \
  <phantun 客户端参数>

服务端模式示例（后台运行）：

docker run -d --name phantun-server --restart unless-stopped \
  --network host \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=server \
  -e RUST_LOG=info \
  phantun-runtime \
  <phantun 服务端参数>

所有参数都会不经任何处理直接转发给 phantun。

## 权限与安全模型

容器仅需要访问 /dev/net/tun 并具备 NET_ADMIN 权限。容器不应以 privileged 模式运行。容器不会修改 sysctl 参数、路由表、防火墙规则、iptables 或 nftables 配置，也不会执行任何形式的 NAT。所有系统级网络策略必须由宿主系统或平台管理员显式配置。

## Linux 宿主机配置（iptables/nftables）

Phantun 仅支持 Linux。建议使用 `--network host` 运行容器，以便 TUN 接口出现在宿主机网络命名空间中并由宿主机配置防火墙/NAT。容器不会修改宿主机网络。以下步骤基于上游 phantun 官方文档整理：https://github.com/dndx/phantun#usage。

### 1) 启用内核转发

```sh
sudo sysctl -w net.ipv4.ip_forward=1
```

如需 IPv6：

```sh
sudo sysctl -w net.ipv6.conf.all.forwarding=1
```

### 2) 添加防火墙/NAT 规则

将 `TUN_IF`、`WAN_IF` 和端口替换为你的实际配置。如果你修改了 phantun 的 TUN 地址，请同步更新 DNAT 目标地址。

#### 客户端（SNAT/masquerade）

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

#### 服务端（DNAT TCP 监听端口到 TUN 地址）

phantun 服务端默认使用 `192.168.201.2` 和 `fcc9::2` 作为 TUN 地址（如未在 phantun 参数中更改）。

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

说明：
- 如果不需要 IPv6，请省略 IPv6 规则。
- 若使用 UFW/firewalld 等上层防火墙，请在其配置中集成这些规则，避免直接使用底层命令。

## 构建镜像

可以通过标准的 Docker 构建流程在本地构建镜像。

docker build -t phantun-runtime .

默认构建方式为开发友好的 `git clone` + `cargo build`，拉取上游默认分支的最新提交。供应链校验为可选项：当提供 `PHANTUN_TARBALL_SHA256` 时，构建会下载源码压缩包并校验 SHA256；若同时提供 `PHANTUN_COMMIT`，则使用该提交；否则使用默认分支当前 HEAD。

### 构建教程（更详细）

基础构建（默认分支 HEAD，无校验）：

```sh
docker build -t phantun-runtime:dev .
```

指定提交构建（无校验）：

```sh
docker build \
  --build-arg PHANTUN_COMMIT=<commit> \
  -t phantun-runtime:commit .
```

启用 tarball 校验的构建：

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

说明：
- 若只设置 `PHANTUN_TARBALL_SHA256` 未设置 `PHANTUN_COMMIT`，构建时会解析默认分支的当前 HEAD。为避免漂移，建议同时提供两者。
- 如需从 fork 构建，可通过 `PHANTUN_OWNER` 和 `PHANTUN_REPO` 覆盖上游来源。

### 跨平台构建

该 Dockerfile 默认按“构建机平台”进行构建。需要其他平台镜像时，建议使用 Docker Buildx（QEMU 模拟）：

```sh
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t phantun-runtime:multiarch --push .
```

仅构建单一非本机平台且不推送时：

```sh
docker buildx build --platform linux/arm64 \
  -t phantun-runtime:arm64 --load .
```

导出单平台镜像为 tar 包：

```sh
docker buildx build --platform linux/arm64 \
  --output type=docker,dest=phantun-runtime-arm64.tar .
```

如果希望在构建器内部“真交叉编译”（不依赖 QEMU），需要自行安装 Rust 目标与对应系统工具链（默认未配置）。

## 版本策略

容器版本仅反映运行时封装层的变化。phantun 的功能、参数和行为完全由上游定义。上游参数变更不会要求修改本容器实现。

## 范围与非目标

本项目不试图简化 phantun 的使用流程，不提供编排或管理能力，也不作为 VPN 管理工具，更不会引入自动化或隐式默认行为。这些需求应由更高层系统负责。

## 许可与上游关系

phantun-runtime 不修改、不 fork phantun 源码。所有与 phantun 相关的功能与行为均遵循其原始上游许可与归属。
