# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

ARG TARGETARCH

# ── Layer 1: System packages (changes rarely) ───────────────────────────
# Using --no-install-recommends to keep the layer small.
# Split from external-repo packages so a NodeSource or Docker version
# bump doesn't invalidate the base apt layer.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    dpkg --add-architecture arm64 \
    && if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
         sed -i '/^Types:/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources; \
       elif [ -f /etc/apt/sources.list ]; then \
         sed -i 's|^deb http|deb [arch=amd64] http|' /etc/apt/sources.list; \
       fi \
    && printf '%s\n' \
         "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse" \
         "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse" \
         "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse" \
         "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-backports main restricted universe multiverse" \
         > /etc/apt/sources.list.d/arm64-ports.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    curl wget git jq ripgrep unzip ca-certificates gnupg xdg-utils \
    build-essential g++ cmake make pkg-config \
    gcc-aarch64-linux-gnu libc6-dev-arm64-cross libstdc++-13-dev-arm64-cross clang mold lld \
    python3 python3-pip python3-venv \
    openjdk-21-jdk-headless \
    libx11-dev libasound2-dev libudev-dev libxkbcommon-x11-0 libssl-dev \
    libssl-dev:arm64 libudev-dev:arm64

# ── Layer 2: External apt repos + packages (NodeSource, Docker, GH CLI) ─
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_25.x | bash - \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs docker-ce-cli gh

# ── Layer 3: npm globals ─────────────────────────────────────────────────
RUN npm install -g yarn esbuild

# ── Layer 4: GitLab CLI ──────────────────────────────────────────────────
ARG GLAB_VERSION=1.89.0
RUN GLAB_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") \
    && curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${GLAB_ARCH}.tar.gz" | tar -xz -C /tmp \
    && mv /tmp/bin/glab /usr/local/bin/ \
    && rm -rf /tmp/bin

# ── Layer 5: sccache ─────────────────────────────────────────────────────
# renovate: datasource=github-releases depName=mozilla/sccache
ARG SCCACHE_VERSION=0.14.0
RUN SCCACHE_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}-unknown-linux-musl.tar.gz" | tar -xz -C /tmp \
    && mv /tmp/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}-unknown-linux-musl/sccache /usr/local/bin/ \
    && rm -rf /tmp/sccache-*
ENV PATH="/usr/local/bin:${PATH}"

# ── Layer 6: Go ──────────────────────────────────────────────────────────
ARG GO_VERSION=1.26.0
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Layer 7: Rust toolchains + wasm targets ──────────────────────────────
ENV RUSTUP_HOME="/usr/local/rustup" \
    CARGO_HOME="/usr/local/cargo"
ENV PATH="/usr/local/cargo/bin:${PATH}"

ENV CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++ \
    AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar

RUN mkdir -p /usr/local/cargo \
    && printf '[target.x86_64-unknown-linux-gnu]\nlinker = "clang"\nrustflags = ["-C", "link-arg=-fuse-ld=mold"]\n\n[target.aarch64-unknown-linux-gnu]\nlinker = "aarch64-linux-gnu-gcc"\nrustflags = ["-C", "link-arg=-fuse-ld=mold"]\n' > /usr/local/cargo/config.toml

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
    && rustup toolchain install nightly \
    && rustup component add rust-src --toolchain nightly \
    && rustup target add wasm32-unknown-unknown \
    && rustup target add wasm32-unknown-unknown --toolchain nightly \
    && rustup target add aarch64-unknown-linux-gnu

# pkg-config wrapper for aarch64 cross-compilation
RUN printf '#!/bin/sh\nexec env PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig PKG_CONFIG_SYSROOT_DIR=/ pkg-config "$@"\n' \
        > /usr/local/bin/aarch64-linux-gnu-pkg-config \
    && chmod +x /usr/local/bin/aarch64-linux-gnu-pkg-config
ENV PKG_CONFIG_AARCH64_UNKNOWN_LINUX_GNU=aarch64-linux-gnu-pkg-config

# ── Stage: build Rust CLI tools in an isolated layer ─────────────────────
# cargo install leaves behind build trees in $CARGO_HOME/registry and
# target dirs.  Building in a throwaway stage and copying only the
# binaries keeps the final image much smaller.
FROM base AS rust-tools

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    cargo install wasm-bindgen-cli wasm-pack twiggy wasm-opt \
    && mkdir /cargo-bin \
    && cp /usr/local/cargo/bin/wasm-bindgen /cargo-bin/ \
    && cp /usr/local/cargo/bin/wasm-bindgen-test-runner /cargo-bin/ \
    && cp /usr/local/cargo/bin/wasm-pack /cargo-bin/ \
    && cp /usr/local/cargo/bin/twiggy /cargo-bin/ \
    && cp /usr/local/cargo/bin/wasm-opt /cargo-bin/

# ── Final stage ──────────────────────────────────────────────────────────
FROM base

COPY --from=rust-tools /cargo-bin/* /usr/local/cargo/bin/

# ── Layer 8: AWS CLI ─────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip
