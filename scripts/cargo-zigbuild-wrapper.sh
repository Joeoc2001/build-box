#!/usr/bin/env bash
set -euo pipefail

glibc_suffix="${CARGO_ZIGBUILD_GLIBC_SUFFIX:-.2.39}"
args=()
expect_target=0

for arg in "$@"; do
  if [ "$expect_target" -eq 1 ]; then
    case "$arg" in
      aarch64-unknown-linux-gnu|x86_64-unknown-linux-gnu)
        args+=("${arg}${glibc_suffix}")
        ;;
      *)
        args+=("$arg")
        ;;
    esac
    expect_target=0
    continue
  fi

  case "$arg" in
    --target)
      expect_target=1
      args+=("$arg")
      ;;
    --target=aarch64-unknown-linux-gnu)
      args+=("--target=aarch64-unknown-linux-gnu${glibc_suffix}")
      ;;
    --target=x86_64-unknown-linux-gnu)
      args+=("--target=x86_64-unknown-linux-gnu${glibc_suffix}")
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

exec /usr/local/cargo/bin/cargo-zigbuild-bin "${args[@]}"
