#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-${REPO_ROOT}/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-${REPO_ROOT}}"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

strip_prefix() {
  local value="$1"
  local prefix="$2"
  echo "${value#"${prefix}"}"
}

github_latest_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name'
}

gitlab_latest_tag() {
  local project_path="$1"
  local encoded
  encoded="$(printf '%s' "${project_path}" | jq -sRr @uri)"
  curl -fsSL "https://gitlab.com/api/v4/projects/${encoded}/releases/permalink/latest" | jq -r '.tag_name'
}

require_cmd curl
require_cmd jq
require_cmd docker

DOCKER_BUILD_USE_BUILDX="${DOCKER_BUILD_USE_BUILDX:-0}"

echo "Resolving latest tool versions..."

NODE_MAJOR="$(curl -fsSL "https://nodejs.org/dist/index.json" | jq -r '.[0].version' | sed -E 's/^v([0-9]+).*/\1/')"
GO_VERSION="$(curl -fsSL "https://go.dev/dl/?mode=json" | jq -r '[.[] | select(.stable == true)][0].version' | sed -E 's/^go//')"
GLAB_VERSION="$(strip_prefix "$(gitlab_latest_tag "gitlab-org/cli")" "v")"
SCCACHE_VERSION="$(strip_prefix "$(github_latest_tag "mozilla/sccache")" "v")"
RUST_STABLE_VERSION="$(curl -fsSL "https://static.rust-lang.org/dist/channel-rust-stable.toml" | sed -nE 's/^version = "([0-9]+\.[0-9]+\.[0-9]+).*/\1/p; q')"
ZIG_VERSION="$(strip_prefix "$(github_latest_tag "ziglang/zig")" "v")"
WASM_BINDGEN_VERSION="$(strip_prefix "$(github_latest_tag "rustwasm/wasm-bindgen")" "v")"
WASM_PACK_VERSION="$(strip_prefix "$(github_latest_tag "rustwasm/wasm-pack")" "v")"
BINARYEN_VERSION="$(strip_prefix "$(github_latest_tag "WebAssembly/binaryen")" "version_")"
CARGO_ZIGBUILD_VERSION="$(strip_prefix "$(github_latest_tag "rust-cross/cargo-zigbuild")" "v")"

for value in \
  "${NODE_MAJOR}" \
  "${GO_VERSION}" \
  "${GLAB_VERSION}" \
  "${SCCACHE_VERSION}" \
  "${RUST_STABLE_VERSION}" \
  "${ZIG_VERSION}" \
  "${WASM_BINDGEN_VERSION}" \
  "${WASM_PACK_VERSION}" \
  "${BINARYEN_VERSION}" \
  "${CARGO_ZIGBUILD_VERSION}"; do
  if [ -z "${value}" ] || [ "${value}" = "null" ]; then
    echo "failed to resolve one or more versions" >&2
    exit 1
  fi
done

echo "Using:"
echo "  NODE_MAJOR=${NODE_MAJOR}"
echo "  GO_VERSION=${GO_VERSION}"
echo "  GLAB_VERSION=${GLAB_VERSION}"
echo "  SCCACHE_VERSION=${SCCACHE_VERSION}"
echo "  RUST_STABLE_VERSION=${RUST_STABLE_VERSION}"
echo "  ZIG_VERSION=${ZIG_VERSION}"
echo "  WASM_BINDGEN_VERSION=${WASM_BINDGEN_VERSION}"
echo "  WASM_PACK_VERSION=${WASM_PACK_VERSION}"
echo "  BINARYEN_VERSION=${BINARYEN_VERSION}"
echo "  CARGO_ZIGBUILD_VERSION=${CARGO_ZIGBUILD_VERSION}"

if [ "${DOCKER_BUILD_USE_BUILDX}" = "1" ]; then
  docker buildx build \
    --file "${DOCKERFILE_PATH}" \
    --build-arg "NODE_MAJOR=${NODE_MAJOR}" \
    --build-arg "GO_VERSION=${GO_VERSION}" \
    --build-arg "GLAB_VERSION=${GLAB_VERSION}" \
    --build-arg "SCCACHE_VERSION=${SCCACHE_VERSION}" \
    --build-arg "RUST_STABLE_VERSION=${RUST_STABLE_VERSION}" \
    --build-arg "ZIG_VERSION=${ZIG_VERSION}" \
    --build-arg "WASM_BINDGEN_VERSION=${WASM_BINDGEN_VERSION}" \
    --build-arg "WASM_PACK_VERSION=${WASM_PACK_VERSION}" \
    --build-arg "BINARYEN_VERSION=${BINARYEN_VERSION}" \
    --build-arg "CARGO_ZIGBUILD_VERSION=${CARGO_ZIGBUILD_VERSION}" \
    "$@" \
    "${BUILD_CONTEXT}"
else
  docker build \
  --file "${DOCKERFILE_PATH}" \
  --build-arg "NODE_MAJOR=${NODE_MAJOR}" \
  --build-arg "GO_VERSION=${GO_VERSION}" \
  --build-arg "GLAB_VERSION=${GLAB_VERSION}" \
  --build-arg "SCCACHE_VERSION=${SCCACHE_VERSION}" \
  --build-arg "RUST_STABLE_VERSION=${RUST_STABLE_VERSION}" \
  --build-arg "ZIG_VERSION=${ZIG_VERSION}" \
  --build-arg "WASM_BINDGEN_VERSION=${WASM_BINDGEN_VERSION}" \
  --build-arg "WASM_PACK_VERSION=${WASM_PACK_VERSION}" \
  --build-arg "BINARYEN_VERSION=${BINARYEN_VERSION}" \
  --build-arg "CARGO_ZIGBUILD_VERSION=${CARGO_ZIGBUILD_VERSION}" \
  "$@" \
  "${BUILD_CONTEXT}"
fi
