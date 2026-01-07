# syntax=docker/dockerfile:1.7
#
# phantun-runtime (minimal runtime, opt-in source verification)
# Goals:
# - Dev-friendly default build (git clone/cargo build)
# - Optional source integrity verification (tarball sha256)
# - Produce minimal runtime (no iptables/procps/sysctl tooling)
# - MODE-only entrypoint; args passthrough
#
# Build with:
#   docker buildx build --provenance=true --sbom=true \
#     --build-arg PHANTUN_COMMIT=<40-hex-sha> \
#     --build-arg PHANTUN_TARBALL_SHA256=<sha256> \
#     -t phantun-runtime:<ver> .

############################
# Builder stage
############################
FROM rust:latest AS builder

ARG PHANTUN_OWNER=dndx
ARG PHANTUN_REPO=phantun

ARG PHANTUN_COMMIT
ARG PHANTUN_TARBALL_SHA256

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git xz-utils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# If PHANTUN_TARBALL_SHA256 is provided, verify an immutable archive.
# Otherwise, default to a dev-friendly git clone (optionally checking out PHANTUN_COMMIT).
RUN set -eu; \
  if [ -n "${PHANTUN_TARBALL_SHA256:-}" ]; then \
    ref="${PHANTUN_COMMIT:-}"; \
    if [ -z "$ref" ]; then \
      ref="$(git ls-remote --symref "https://github.com/${PHANTUN_OWNER}/${PHANTUN_REPO}.git" HEAD | awk 'END {print $1}')"; \
    fi; \
    if [ -z "$ref" ]; then \
      echo "ERROR: Unable to resolve upstream HEAD for ${PHANTUN_OWNER}/${PHANTUN_REPO}." >&2; \
      exit 1; \
    fi; \
    curl -fsSL -o phantun.tar.gz \
      "https://github.com/${PHANTUN_OWNER}/${PHANTUN_REPO}/archive/${ref}.tar.gz"; \
    echo "${PHANTUN_TARBALL_SHA256}  phantun.tar.gz" | sha256sum -c -; \
    tar -xzf phantun.tar.gz --strip-components=1; \
    rm -f phantun.tar.gz; \
  else \
    git clone --depth 1 "https://github.com/${PHANTUN_OWNER}/${PHANTUN_REPO}.git" .; \
    if [ -n "${PHANTUN_COMMIT:-}" ]; then \
      git fetch --depth 1 origin "$PHANTUN_COMMIT"; \
      git checkout "$PHANTUN_COMMIT"; \
    fi; \
  fi

# Build
RUN cargo build --release \
 && strip target/release/server target/release/client \
 && install -m 0755 target/release/server /usr/local/bin/phantun-server \
 && install -m 0755 target/release/client /usr/local/bin/phantun-client

############################
# Runtime stage (ours)
############################
FROM debian:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/phantun-server /usr/local/bin/phantun-server
COPY --from=builder /usr/local/bin/phantun-client /usr/local/bin/phantun-client

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
