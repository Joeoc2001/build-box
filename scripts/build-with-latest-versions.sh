#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRINT_ENV_ONLY=0

if [ "${1:-}" = "--print-env" ]; then
  PRINT_ENV_ONLY=1
  shift
fi

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
  # Unauthenticated GitHub API calls are limited to 60/hour per IP, which
  # shared CI runners regularly exhaust. Use a token when one is available.
  local auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name'
}

npm_latest_version() {
  local package="$1"
  curl -fsSL "https://registry.npmjs.org/${package}/latest" | jq -r '.version'
}

# Zig development moved to Codeberg and the GitHub mirror no longer gets
# releases, so read the official download index instead.
zig_latest_version() {
  curl -fsSL "https://ziglang.org/download/index.json" |
    jq -r '[keys[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))]
      | sort_by(split(".") | map(tonumber))
      | last'
}

# AWS CLI v2 doesn't publish GitHub releases, only tags.
aws_cli_latest_version() {
  git ls-remote --tags --refs "https://github.com/aws/aws-cli.git" '2.*' |
    sed -E 's|.*refs/tags/||' |
    grep -E '^2\.[0-9]+\.[0-9]+$' |
    sort -V |
    tail -n1
}

# nodejs.org lists pre-releases (e.g. v27.0.0-alpha) which NodeSource
# doesn't ship, so pick the newest non-prerelease major.
node_latest_major() {
  curl -fsSL "https://nodejs.org/dist/index.json" |
    jq -r '[.[] | select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0].version' |
    sed -E 's/^v([0-9]+).*/\1/'
}

crates_latest_version() {
  local crate="$1"
  curl -fsSL -A "build-box (https://github.com/joeoc2001/build-box)" "https://crates.io/api/v1/crates/${crate}" | jq -r '.crate.max_stable_version'
}

nvidia_latest_cuda_series() {
  curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/Packages.gz" |
    gzip -dc |
    awk '/^Package: cuda-toolkit-[0-9]+-[0-9]+$/ { print $2 }' |
    sed -E 's/^cuda-toolkit-//' |
    sort -V |
    tail -n1
}

gitlab_latest_tag() {
  local project_path="$1"
  local encoded
  encoded="$(printf '%s' "${project_path}" | jq -sRr @uri)"
  curl -fsSL "https://gitlab.com/api/v4/projects/${encoded}/releases/permalink/latest" | jq -r '.tag_name'
}

mcr_latest_playwright_noble_version() {
  curl -fsSL "https://mcr.microsoft.com/v2/playwright/tags/list" |
    jq -r '[
      .tags[]
      | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+-noble$"))
      | capture("^v(?<version>[0-9]+\\.[0-9]+\\.[0-9]+)-noble$").version
    ]
    | sort_by(split(".") | map(tonumber))
    | last'
}

require_cmd curl
require_cmd jq
require_cmd gzip
require_cmd git
if [ "${PRINT_ENV_ONLY}" -ne 1 ]; then
  require_cmd docker
fi

if [ "${PRINT_ENV_ONLY}" -ne 1 ]; then
  echo "Resolving latest tool versions..."
fi

NODE_MAJOR="$(node_latest_major)"
GO_VERSION="$(curl -fsSL "https://go.dev/dl/?mode=json" | jq -r '[.[] | select(.stable == true)][0].version' | sed -E 's/^go//')"
GLAB_VERSION="$(strip_prefix "$(gitlab_latest_tag "gitlab-org/cli")" "v")"
SCCACHE_VERSION="$(strip_prefix "$(github_latest_tag "mozilla/sccache")" "v")"
CRANE_VERSION="$(strip_prefix "$(github_latest_tag "google/go-containerregistry")" "v")"
RUST_STABLE_VERSION="$(
  curl -fsSL "https://static.rust-lang.org/dist/channel-rust-stable.toml" |
    awk '
      /^\[pkg\.rust\]$/ { in_rust = 1; next }
      in_rust && /^version = "/ && !found {
        line = $0
        sub(/^version = "/, "", line)
        sub(/ .*/, "", line)
        sub(/".*/, "", line)
        print line
        found = 1
      }
    '
)"
ZIG_VERSION="$(zig_latest_version)"
WASM_PACK_VERSION="$(strip_prefix "$(github_latest_tag "wasm-bindgen/wasm-pack")" "v")"
BINARYEN_VERSION="$(strip_prefix "$(github_latest_tag "WebAssembly/binaryen")" "version_")"
CARGO_ZIGBUILD_VERSION="$(strip_prefix "$(github_latest_tag "rust-cross/cargo-zigbuild")" "v")"
CARGO_NEXTEST_VERSION="$(crates_latest_version "cargo-nextest")"
CUDA_VERSION="$(nvidia_latest_cuda_series)"
PLAYWRIGHT_VERSION="$(mcr_latest_playwright_noble_version)"
TWIGGY_VERSION="$(crates_latest_version "twiggy")"
CARGO_SWEEP_VERSION="$(crates_latest_version "cargo-sweep")"
WASM_BINDGEN_VERSION="$(crates_latest_version "wasm-bindgen-cli")"
CARGO_INSTA_VERSION="$(crates_latest_version "cargo-insta")"
AWS_CLI_VERSION="$(aws_cli_latest_version)"
YARN_VERSION="$(npm_latest_version "yarn")"
ESBUILD_VERSION="$(npm_latest_version "esbuild")"
TYPESCRIPT_VERSION="$(npm_latest_version "typescript")"
PRETTIER_VERSION="$(npm_latest_version "prettier")"
PATCH_DATE="$(date -u +%Y-%m-%d)"

for value in \
  "${NODE_MAJOR}" \
  "${GO_VERSION}" \
  "${GLAB_VERSION}" \
  "${SCCACHE_VERSION}" \
  "${CRANE_VERSION}" \
  "${RUST_STABLE_VERSION}" \
  "${ZIG_VERSION}" \
  "${WASM_PACK_VERSION}" \
  "${BINARYEN_VERSION}" \
  "${CARGO_ZIGBUILD_VERSION}" \
  "${CARGO_NEXTEST_VERSION}" \
  "${CUDA_VERSION}" \
  "${PLAYWRIGHT_VERSION}" \
  "${TWIGGY_VERSION}" \
  "${CARGO_SWEEP_VERSION}" \
  "${WASM_BINDGEN_VERSION}" \
  "${CARGO_INSTA_VERSION}" \
  "${AWS_CLI_VERSION}" \
  "${YARN_VERSION}" \
  "${ESBUILD_VERSION}" \
  "${TYPESCRIPT_VERSION}" \
  "${PRETTIER_VERSION}" \
  "${PATCH_DATE}"; do
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
echo "  CRANE_VERSION=${CRANE_VERSION}"
echo "  RUST_STABLE_VERSION=${RUST_STABLE_VERSION}"
echo "  ZIG_VERSION=${ZIG_VERSION}"
echo "  WASM_PACK_VERSION=${WASM_PACK_VERSION}"
echo "  BINARYEN_VERSION=${BINARYEN_VERSION}"
echo "  CARGO_ZIGBUILD_VERSION=${CARGO_ZIGBUILD_VERSION}"
echo "  CARGO_NEXTEST_VERSION=${CARGO_NEXTEST_VERSION}"
echo "  CUDA_VERSION=${CUDA_VERSION}"
echo "  PLAYWRIGHT_VERSION=${PLAYWRIGHT_VERSION}"
echo "  TWIGGY_VERSION=${TWIGGY_VERSION}"
echo "  CARGO_SWEEP_VERSION=${CARGO_SWEEP_VERSION}"
echo "  WASM_BINDGEN_VERSION=${WASM_BINDGEN_VERSION}"
echo "  CARGO_INSTA_VERSION=${CARGO_INSTA_VERSION}"
echo "  AWS_CLI_VERSION=${AWS_CLI_VERSION}"
echo "  YARN_VERSION=${YARN_VERSION}"
echo "  ESBUILD_VERSION=${ESBUILD_VERSION}"
echo "  TYPESCRIPT_VERSION=${TYPESCRIPT_VERSION}"
echo "  PRETTIER_VERSION=${PRETTIER_VERSION}"
echo "  PATCH_DATE=${PATCH_DATE}"

if [ "${PRINT_ENV_ONLY}" -eq 1 ]; then
  exit 0
fi

docker buildx build \
  --file "${REPO_ROOT}/Dockerfile" \
  --build-arg "NODE_MAJOR=${NODE_MAJOR}" \
  --build-arg "GO_VERSION=${GO_VERSION}" \
  --build-arg "GLAB_VERSION=${GLAB_VERSION}" \
  --build-arg "SCCACHE_VERSION=${SCCACHE_VERSION}" \
  --build-arg "CRANE_VERSION=${CRANE_VERSION}" \
  --build-arg "RUST_STABLE_VERSION=${RUST_STABLE_VERSION}" \
  --build-arg "ZIG_VERSION=${ZIG_VERSION}" \
  --build-arg "WASM_PACK_VERSION=${WASM_PACK_VERSION}" \
  --build-arg "BINARYEN_VERSION=${BINARYEN_VERSION}" \
  --build-arg "CARGO_ZIGBUILD_VERSION=${CARGO_ZIGBUILD_VERSION}" \
  --build-arg "CARGO_NEXTEST_VERSION=${CARGO_NEXTEST_VERSION}" \
  --build-arg "CUDA_VERSION=${CUDA_VERSION}" \
  --build-arg "PLAYWRIGHT_VERSION=${PLAYWRIGHT_VERSION}" \
  --build-arg "TWIGGY_VERSION=${TWIGGY_VERSION}" \
  --build-arg "CARGO_SWEEP_VERSION=${CARGO_SWEEP_VERSION}" \
  --build-arg "WASM_BINDGEN_VERSION=${WASM_BINDGEN_VERSION}" \
  --build-arg "CARGO_INSTA_VERSION=${CARGO_INSTA_VERSION}" \
  --build-arg "AWS_CLI_VERSION=${AWS_CLI_VERSION}" \
  --build-arg "YARN_VERSION=${YARN_VERSION}" \
  --build-arg "ESBUILD_VERSION=${ESBUILD_VERSION}" \
  --build-arg "TYPESCRIPT_VERSION=${TYPESCRIPT_VERSION}" \
  --build-arg "PRETTIER_VERSION=${PRETTIER_VERSION}" \
  --build-arg "PATCH_DATE=${PATCH_DATE}" \
  "$@" \
  "${REPO_ROOT}"
