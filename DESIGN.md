# phantun-runtime Design Document

## 1. Project Background

phantun is a high-performance tunnel program focused on reliable packet delivery under adverse network conditions.  
While phantun itself is intentionally minimal and low-level, many existing deployment methods blur the boundary between application responsibility and system responsibility, especially in containerized environments.

This project, **phantun-runtime**, exists to explicitly define and enforce that boundary.

phantun-runtime is **not** a fork of phantun, **not** a feature extension, and **not** an orchestration layer.  
It is a strictly minimal runtime container whose sole purpose is to execute official phantun binaries under a clearly defined security and responsibility model.

---

## 2. Design Goals

The primary design goals of this project are:

- Enforce **least responsibility**
- Enforce **least privilege**
- Preserve **full upstream compatibility**
- Maintain **long-term operational stability**
- Avoid hidden or implicit system-side behavior

The container must behave as a transparent execution shell, not an opinionated platform.

---

## 3. Responsibility Boundaries

### 3.1 What This Project Does

phantun-runtime is responsible for:

- Selecting execution mode (`client` or `server`) explicitly via a single environment variable
- Executing the corresponding official phantun binary
- Passing all runtime parameters verbatim to phantun
- Running as PID 1 and forwarding signals correctly
- Operating with minimal container capabilities required for TUN usage

---

### 3.2 What This Project Explicitly Does NOT Do

phantun-runtime **does not**:

- Modify sysctl parameters (e.g. IP forwarding)
- Configure routing tables
- Insert or delete iptables / nftables rules
- Perform NAT (SNAT / DNAT)
- Manage firewall policies
- Allocate or auto-generate IP addresses
- Interpret, validate, or rewrite phantun parameters
- Run privileged containers

All system-level networking policy is considered the responsibility of the host operating system or platform administrator.

---

## 4. Runtime-Only Philosophy

This project intentionally separates **build responsibility** from **runtime responsibility**.

- phantun upstream is the single source of truth for:
  - Source code
  - Build logic
  - Binary behavior

- phantun-runtime only consumes official build artifacts
- No patches, forks, or behavioral changes are introduced

This separation ensures:

- Zero behavioral drift from upstream
- Simplified upgrades when phantun releases new versions
- Clear auditability of responsibility

### 4.1 Build Inputs and Optional Verification

The build process consumes upstream source without modification:

- Default behavior is a dev-friendly `git clone` of the upstream default branch.
- If `PHANTUN_COMMIT` is provided, that commit is checked out.
- If `PHANTUN_TARBALL_SHA256` is provided, the build downloads the tarball for the resolved commit (or default-branch HEAD), verifies the SHA256, and builds from that verified source.

Verification is opt-in to keep the default workflow lightweight, while allowing deterministic, auditable builds when needed.

---

## 5. Parameter Transparency

The container runtime recognizes exactly one control parameter for execution:

- `MODE=client | server`

All other arguments are passed verbatim to the underlying phantun binary. Optional interface-name handoff (via `IFACE_NAME`/`IFACE_FILE`) is out-of-band and does not alter phantun arguments.

This guarantees that:

- New phantun parameters require **no container changes**
- Existing deployments do not break on upstream updates
- The container never becomes a compatibility bottleneck

---

## 6. Interface Name Handoff (Optional)

Some deployments need a stable, auditable way to learn the TUN interface name without parsing phantun parameters. To preserve the "no parameter interpretation" rule, the container supports a simple file handoff:

- `IFACE_NAME` is provided externally (for example `ptun0`).
- `IFACE_FILE` is a path mounted into the container.
- If both are set, the container writes `IFACE_NAME` to `IFACE_FILE` before starting phantun.
- If the file was written, it is cleared to an empty string on shutdown.
- The container does not parse or validate phantun arguments, and it does not infer the interface name from them.
- If `IFACE_FILE` is set but the write fails, the container exits with a clear error to avoid stale reads.

This mechanism avoids any background helpers, polling, or netlink discovery.

## 7. Security Model

### 7.1 Container Privileges

The container requires only:

- Access to `/dev/net/tun`
- Capability: `NET_ADMIN`

The container must not be run in `--privileged` mode.

For host-side firewall/NAT configuration, the container should run with `--network host` so the TUN interface is created in the host network namespace.

No additional Linux capabilities are required or assumed.

---

### 7.2 Predictability and Auditability

The runtime behavior is fully deterministic:

- No implicit side effects
- No runtime system modification
- No background helper scripts
- No dynamic configuration changes

Every system-level effect is externally visible and externally controlled.

---

## 8. Operational Rationale

This design intentionally prioritizes:

- Operational clarity over convenience
- Explicit configuration over automation
- Predictability over abstraction

In infrastructure environments such as OpenWrt, Kubernetes, or hardened Linux hosts, this approach aligns with established platform security practices and simplifies long-term maintenance.

---

## 9. Non-Goals

This project explicitly does not aim to:

- Simplify phantun usage for beginners
- Replace orchestration systems
- Act as a VPN manager
- Provide UI or management APIs

Those concerns are deliberately left to higher-level systems.

---

## 10. Conclusion

phantun-runtime treats phantun as a **pure tunnel primitive** and the operating system as the **sole authority over networking policy**.

This strict separation of concerns is the foundation for secure, auditable, and long-lived deployments, especially in professional and regulated environments.
