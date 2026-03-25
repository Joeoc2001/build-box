# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

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
    build-essential g++ cmake make pkg-config clang mold lld \
    python3 python3-pip python3-venv \
    openjdk-21-jdk-headless \
    libx11-dev libasound2-dev libudev-dev libxkbcommon-x11-0 libssl-dev \
    libssl-dev:arm64 libudev-dev:arm64

# ── Layer 2: External apt repos + packages (NodeSource, Docker, GH CLI) ─
ARG NODE_MAJOR
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs docker-ce-cli gh

# ── Layer 3: npm globals ─────────────────────────────────────────────────
RUN npm install -g yarn esbuild

# ── Layer 4: GitLab CLI ──────────────────────────────────────────────────
ARG GLAB_VERSION
RUN curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz" | tar -xz -C /tmp \
    && mv /tmp/bin/glab /usr/local/bin/ \
    && rm -rf /tmp/bin

# ── Layer 5: sccache ─────────────────────────────────────────────────────
ARG SCCACHE_VERSION
RUN curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp \
    && mv /tmp/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl/sccache /usr/local/bin/ \
    && rm -rf /tmp/sccache-*
ENV PATH="/usr/local/bin:${PATH}"

# ── Layer 6: Go ──────────────────────────────────────────────────────────
ARG GO_VERSION
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Layer 7: Rust toolchains + wasm targets ──────────────────────────────
ARG RUST_STABLE_VERSION

ENV RUSTUP_HOME="/usr/local/rustup" \
    CARGO_HOME="/usr/local/cargo"
ENV PATH="/usr/local/cargo/bin:${PATH}"

RUN mkdir -p /usr/local/cargo \
    && printf '[target.x86_64-unknown-linux-gnu]\nlinker = "clang"\nrustflags = ["-C", "link-arg=-fuse-ld=mold"]\n' > /usr/local/cargo/config.toml

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "${RUST_STABLE_VERSION}" \
    && rustup set auto-self-update disable \
    && RUST_STABLE_DATE="$(curl -fsSL "https://static.rust-lang.org/dist/channel-rust-${RUST_STABLE_VERSION}.toml" | sed -n 's/^date = "\([0-9-]*\)"$/\1/p')" \
    && test -n "${RUST_STABLE_DATE}" \
    && RUST_NIGHTLY_TOOLCHAIN="nightly-${RUST_STABLE_DATE}" \
    && RUST_HOST_TRIPLE="$(rustc +"${RUST_STABLE_VERSION}" -vV | sed -n 's/^host: //p')" \
    && rustup toolchain install "${RUST_NIGHTLY_TOOLCHAIN}" \
    && rustup component add rust-src --toolchain "${RUST_NIGHTLY_TOOLCHAIN}" \
    && rustup target add wasm32-unknown-unknown \
    && rustup target add wasm32-unknown-unknown --toolchain "${RUST_NIGHTLY_TOOLCHAIN}" \
    && rustup toolchain link pinned-nightly "${RUSTUP_HOME}/toolchains/${RUST_NIGHTLY_TOOLCHAIN}-${RUST_HOST_TRIPLE}" \
    && rustup target add aarch64-unknown-linux-gnu

ENV PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_aarch64_unknown_linux_gnu=pkg-config \
    PKG_CONFIG_PATH_aarch64_unknown_linux_gnu=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig \
    PKG_CONFIG_SYSROOT_DIR_aarch64_unknown_linux_gnu=/ \
    CFLAGS_aarch64_unknown_linux_gnu=-I/usr/include/aarch64-linux-gnu \
    CXXFLAGS_aarch64_unknown_linux_gnu=-I/usr/include/aarch64-linux-gnu \
    BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_gnu=--sysroot=/\ -I/usr/include/aarch64-linux-gnu

# ── Layer 7b: Zig + cargo-zigbuild for arm64 cross-compilation ────────
# Zig bundles the cross-compiler and linker, but crates that probe
# system libraries still need arm64 pkg-config metadata from apt.
ARG ZIG_VERSION
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" | tar -xJ -C /opt \
    && ln -s /opt/zig-x86_64-linux-${ZIG_VERSION}/zig /usr/local/bin/zig

# ── Stage: build Rust CLI tools that lack pre-built binaries ─────────────
FROM base AS rust-tools

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    cargo install twiggy \
    && mkdir /cargo-bin \
    && cp /usr/local/cargo/bin/twiggy /cargo-bin/

# ── Final stage ──────────────────────────────────────────────────────────
FROM base

ENV RUSTUP_TOOLCHAIN="pinned-nightly"

COPY --from=rust-tools /cargo-bin/* /usr/local/cargo/bin/

# ── Pre-built Rust CLI tools (avoids slow cargo install under QEMU) ──────
ARG WASM_BINDGEN_VERSION
RUN curl -fsSL "https://github.com/rustwasm/wasm-bindgen/releases/download/${WASM_BINDGEN_VERSION}/wasm-bindgen-${WASM_BINDGEN_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
       | tar -xz --strip-components=1 -C /usr/local/cargo/bin/ \
         "wasm-bindgen-${WASM_BINDGEN_VERSION}-x86_64-unknown-linux-musl/wasm-bindgen" \
         "wasm-bindgen-${WASM_BINDGEN_VERSION}-x86_64-unknown-linux-musl/wasm-bindgen-test-runner"

ARG WASM_PACK_VERSION
RUN curl -fsSL "https://github.com/rustwasm/wasm-pack/releases/download/v${WASM_PACK_VERSION}/wasm-pack-v${WASM_PACK_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
       | tar -xz --strip-components=1 -C /usr/local/cargo/bin/ \
         "wasm-pack-v${WASM_PACK_VERSION}-x86_64-unknown-linux-musl/wasm-pack"

ARG BINARYEN_VERSION
RUN curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-x86_64-linux.tar.gz" \
       | tar -xz --strip-components=1 -C /usr/local/ \
          "binaryen-version_${BINARYEN_VERSION}/bin/wasm-opt"

COPY scripts/cargo-zigbuild-wrapper.sh /tmp/cargo-zigbuild-wrapper.sh

ARG CARGO_ZIGBUILD_VERSION
RUN curl -fsSL "https://github.com/rust-cross/cargo-zigbuild/releases/download/v${CARGO_ZIGBUILD_VERSION}/cargo-zigbuild-x86_64-unknown-linux-gnu.tar.xz" \
       | tar -xJ --strip-components=1 -C /usr/local/cargo/bin/ \
         "cargo-zigbuild-x86_64-unknown-linux-gnu/cargo-zigbuild" \
    && mv /usr/local/cargo/bin/cargo-zigbuild /usr/local/cargo/bin/cargo-zigbuild-bin \
    && install -m 0755 /tmp/cargo-zigbuild-wrapper.sh /usr/local/cargo/bin/cargo-zigbuild

# ── Layer 8: AWS CLI ─────────────────────────────────────────────────────
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip
