#!/bin/sh
set -eu

MODE="${MODE:-}"
IFACE_NAME="${IFACE_NAME:-}"
IFACE_FILE="${IFACE_FILE:-}"
IFACE_WRITTEN=0
child_pid=""

write_iface_file() {
  if ! printf '%s' "$1" > "$IFACE_FILE"; then
    echo "ERROR: Failed to write IFACE_NAME to IFACE_FILE: $IFACE_FILE" >&2
    exit 3
  fi
}

clear_iface_file() {
  if [ "$IFACE_WRITTEN" -eq 1 ]; then
    if ! printf '%s' '' > "$IFACE_FILE"; then
      echo "ERROR: Failed to clear IFACE_FILE: $IFACE_FILE" >&2
      CLEANUP_FAILED=1
    fi
  fi
}

forward_signal() {
  if [ -n "$child_pid" ]; then
    kill "-$1" "$child_pid" 2>/dev/null || true
  fi
}

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
  - If IFACE_NAME and IFACE_FILE are set, IFACE_NAME is written to IFACE_FILE.
  - If IFACE_FILE was written, it is cleared (emptied) on shutdown.
  - The container does not validate or synchronize phantun parameters.
  - No sysctl/routing/firewall/NAT modifications are performed by this container.
EOF
}

case "$MODE" in
  client) PHANTUN_BIN=/usr/local/bin/phantun-client ;;
  server) PHANTUN_BIN=/usr/local/bin/phantun-server ;;
  *) echo "ERROR: MODE must be 'client' or 'server'." >&2; usage; exit 2 ;;
esac

if [ -n "$IFACE_NAME" ] && [ -n "$IFACE_FILE" ]; then
  write_iface_file "$IFACE_NAME"
  IFACE_WRITTEN=1
fi

"$PHANTUN_BIN" "$@" &
child_pid=$!

trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT
trap 'forward_signal HUP' HUP

status=0
while :; do
  if wait "$child_pid"; then
    status=0
  else
    status=$?
  fi
  if kill -0 "$child_pid" 2>/dev/null; then
    continue
  fi
  break
done

CLEANUP_FAILED=0
clear_iface_file
if [ "$CLEANUP_FAILED" -eq 1 ] && [ "$status" -eq 0 ]; then
  status=4
fi

exit "$status"
