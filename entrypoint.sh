#!/bin/sh
set -eu

MODE="${MODE:-}"

usage() {
  cat >&2 <<'EOF'
Usage:
  docker run [docker options] \
    --device /dev/net/tun \
    --cap-add NET_ADMIN \
    -e MODE=client|server \
    phantun-runtime \
    -- <phantun arguments>

Examples:

  Client mode:
    docker run --rm \
      --device /dev/net/tun \
      --cap-add NET_ADMIN \
      -e MODE=client \
      phantun-runtime \
      -- --local 127.0.0.1:1234 --remote 10.0.0.1:4567

  Server mode:
    docker run --rm \
      --device /dev/net/tun \
      --cap-add NET_ADMIN \
      -e MODE=server \
      phantun-runtime \
      -- --local 4567 --remote 127.0.0.1:1234

Notes:
  - The container only interprets MODE.
  - All args after '--' are passed verbatim to phantun.
  - No sysctl/routing/firewall/NAT modifications are performed by this container.
EOF
}

case "$MODE" in
  client) exec /usr/local/bin/phantun-client "$@" ;;
  server) exec /usr/local/bin/phantun-server "$@" ;;
  *) echo "ERROR: MODE must be 'client' or 'server'." >&2; usage; exit 2 ;;
esac
