# syntax=docker/dockerfile:1.7
#
# phantun-runtime (SLSA-ish hardening)
# Goals:
# - No "floating" refs by default (pin commit)
# - Verify source integrity (sha256 of tarball)
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

# PIN THIS (required)
ARG PHANTUN_COMMIT

# Verify this (required)
ARG PHANTUN_TARBALL_SHA256

RUN test -n "$PHANTUN_COMMIT" && test -n "$PHANTUN_TARBALL_SHA256"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Fetch source as an immutable archive for the pinned commit, then verify SHA256.
# (No git, no tags, no branches; avoids ref drift.)
RUN curl -fsSL -o phantun.tar.gz \
      "https://github.com/${PHANTUN_OWNER}/${PHANTUN_REPO}/archive/${PHANTUN_COMMIT}.tar.gz" \
 && echo "${PHANTUN_TARBALL_SHA256}  phantun.tar.gz" | sha256sum -c - \
 && tar -xzf phantun.tar.gz --strip-components=1 \
 && rm -f phantun.tar.gz

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
