#!/usr/bin/env bash
#
# Install a pinned, checksum-verified actionlint binary into .tools/.
#
# Usage: scripts/ci/install-actionlint.sh [destination]
#
# Override the version with ACTIONLINT_VERSION (checksums below must be
# updated together with the version).

set -Eeuo pipefail

readonly VERSION="${ACTIONLINT_VERSION:-1.7.12}"
readonly DEST="${1:-.tools}"

case "$(uname -m)" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *)
    printf '::error::Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

case "${arch}" in
  amd64) checksum="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8" ;;
  arm64) checksum="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6" ;;
esac

workdir="$(mktemp -d)"
readonly workdir
trap 'rm -rf "${workdir}"' EXIT

readonly archive="${workdir}/actionlint.tar.gz"
readonly url="https://github.com/rhysd/actionlint/releases/download/v${VERSION}/actionlint_${VERSION}_linux_${arch}.tar.gz"

curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 -o "${archive}" "${url}"
printf '%s  %s\n' "${checksum}" "${archive}" | sha256sum -c -

mkdir -p "${DEST}"
tar -xzf "${archive}" -C "${DEST}" actionlint
chmod +x "${DEST}/actionlint"
"${DEST}/actionlint" --version
