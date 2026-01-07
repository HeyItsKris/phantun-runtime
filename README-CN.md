# phantun-runtime

phantun-runtime 是一个仅用于运行官方 phantun 二进制程序的最小化运行时容器，严格遵守最小职责与最小权限原则。

## 项目概述

phantun-runtime 是围绕上游 phantun 二进制构建的轻量级执行封装。容器本身不修改系统配置、不管理网络策略，也不理解或重写 phantun 的参数，其唯一职责是根据明确指定的运行模式启动 phantun 程序，并可选地写入接口名文件以便审计。本项目适用于对可预测性、可审计性以及职责边界有严格要求的运行环境。

完整的设计理念与安全模型请参阅 DESIGN.md 与 DESIGN-CN.md。

## 设计原则

本项目遵循以下核心原则：最小职责、最小权限、无隐式系统行为、完全兼容上游以及行为可预测。容器本身不是管理平台，也不会替用户做任何系统层面的决策。

## 运行模式

phantun-runtime 仅支持两种运行模式：client 与 server。运行模式通过环境变量 MODE 明确指定。容器不会解析、校验或修改 phantun 参数；接口名文件写入是独立的可选约定。

## 使用方法

运行容器时必须提供 TUN 设备访问权限以及 NET_ADMIN capability。所有运行参数都会被完整、原样地传递给上游 phantun 程序。

客户端模式示例：

docker run --rm \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=client \
  phantun-runtime \
  -- <phantun 客户端参数>

服务端模式示例：

docker run --rm \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=server \
  phantun-runtime \
  -- <phantun 服务端参数>

双横线之后的所有参数都会不经任何处理直接转发给 phantun。

## 接口名写入（可选）

当外部自动化需要稳定、可审计地获取 TUN 接口名时，容器可以将接口名写入文件。

- 设置 `IFACE_NAME` 为你计划使用的接口名（例如 `ptun0`）。
- 设置 `IFACE_FILE` 为容器内路径（例如 `/run/phantun/iface`）。
- 将宿主机文件映射到该路径（例如 `-v ./state/iface:/run/phantun/iface`）。

容器会在启动 phantun 之前把 `IFACE_NAME` 写入 `IFACE_FILE`，文件内容仅包含接口名本身（不带结尾换行）。如果曾写入该文件，容器关闭时会将其清空为一个空字符串。容器不解析或校验 phantun 参数，你必须自行把同一个接口名通过 phantun 的参数传入。如果设置了 `IFACE_FILE` 但写入失败，容器会直接退出并输出明确错误，避免外部读取到旧值。

文件写入示例：

docker run --rm \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  -e MODE=client \
  -e IFACE_NAME=ptun0 \
  -e IFACE_FILE=/run/phantun/iface \
  -v "$(pwd)/state/iface:/run/phantun/iface" \
  phantun-runtime \
  -- <phantun 参数，需指定接口名为 ptun0>

## 权限与安全模型

容器仅需要访问 /dev/net/tun 并具备 NET_ADMIN 权限。容器不应以 privileged 模式运行。容器不会修改 sysctl 参数、路由表、防火墙规则、iptables 或 nftables 配置，也不会执行任何形式的 NAT。所有系统级网络策略必须由宿主系统或平台管理员显式配置。

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

## 版本策略

容器版本仅反映运行时封装层的变化。phantun 的功能、参数和行为完全由上游定义。上游参数变更不会要求修改本容器实现。

## 范围与非目标

本项目不试图简化 phantun 的使用流程，不提供编排或管理能力，也不作为 VPN 管理工具，更不会引入自动化或隐式默认行为。这些需求应由更高层系统负责。

## 许可与上游关系

phantun-runtime 不修改、不 fork phantun 源码。所有与 phantun 相关的功能与行为均遵循其原始上游许可与归属。
