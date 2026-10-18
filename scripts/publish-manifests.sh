#!/usr/bin/env bash
#
# Stitch the per-architecture images into multi-arch manifests and publish the
# user-facing tags on both registries.
#
# Required environment variables:
#   VERSION, COMMIT, ARCHES
#   DOCKERHUB_IMAGE, GHCR_IMAGE
# Optional:
#   UPDATE_LATEST (true/false), GITHUB_STEP_SUMMARY
#
# The per-architecture images must already be pushed as
# <image>:<VERSION>-<arch> by the build job.

set -Eeuo pipefail

: "${VERSION:?VERSION is required}"
: "${COMMIT:?COMMIT is required}"
: "${ARCHES:?ARCHES is required}"
: "${DOCKERHUB_IMAGE:?DOCKERHUB_IMAGE is required}"
: "${GHCR_IMAGE:?GHCR_IMAGE is required}"

readonly UPDATE_LATEST="${UPDATE_LATEST:-false}"
readonly SHORT_SHA="${COMMIT:0:7}"
readonly SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

notice() { printf '::notice::%s\n' "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

inspect_digest() {
  docker buildx imagetools inspect "$1" | awk '$1 == "Digest:" {print $2; exit}'
}

inspect_platforms() {
  docker buildx imagetools inspect "$1" |
    awk '$1 == "Platform:" {sub(/^linux\//, "", $2); print $2}' |
    sort -u
}

read -r -a arch_list <<<"${ARCHES}"
readonly tag_list=("${VERSION}" "v${VERSION}" "sha-${SHORT_SHA}")
if [[ "${UPDATE_LATEST}" == "true" ]]; then
  readonly -a publish_tags=("${tag_list[@]}" "latest")
else
  readonly -a publish_tags=("${tag_list[@]}")
fi

[[ "${#arch_list[@]}" -gt 0 ]] || fail "ARCHES is empty"

declare -A digests=()

for image in "${DOCKERHUB_IMAGE}" "${GHCR_IMAGE}"; do
  sources=()
  for arch in "${arch_list[@]}"; do
    source_ref="${image}:${VERSION}-${arch}"
    if ! docker buildx imagetools inspect "${source_ref}" >/dev/null 2>&1; then
      fail "Missing source image ${source_ref}; the ${arch} build did not publish"
    fi
    sources+=("${source_ref}")
  done

  create_args=()
  for tag in "${publish_tags[@]}"; do
    create_args+=(-t "${image}:${tag}")
  done

  notice "Creating multi-arch manifest for ${image} (${publish_tags[*]})"
  docker buildx imagetools create "${create_args[@]}" "${sources[@]}"

  digest="$(inspect_digest "${image}:${VERSION}")"
  [[ -n "${digest}" ]] || fail "Unable to read the manifest digest for ${image}"
  digests["${image}"]="${digest}"

  platforms="$(inspect_platforms "${image}:${VERSION}")"
  if [[ "${#arch_list[@]}" -gt 1 ]]; then
    for arch in "${arch_list[@]}"; do
      if ! grep -qx "${arch}" <<<"${platforms}"; then
        fail "${image}:${VERSION} is missing the linux/${arch} platform (found: ${platforms:-none})"
      fi
    done
  fi

  if [[ "${UPDATE_LATEST}" == "true" ]]; then
    latest_digest="$(inspect_digest "${image}:latest")"
    if [[ "${latest_digest}" != "${digest}" ]]; then
      fail "${image}:latest (${latest_digest}) does not match ${VERSION} (${digest})"
    fi
  fi
done

{
  echo "## Published images"
  echo ""
  echo "| Registry | Tags | Digest |"
  echo "| --- | --- | --- |"
  for image in "${DOCKERHUB_IMAGE}" "${GHCR_IMAGE}"; do
    echo "| \`${image}\` | ${publish_tags[*]} | \`${digests[${image}]}\` |"
  done
  echo ""
  echo "Upstream commit: \`${COMMIT}\`"
} >>"${SUMMARY_FILE}"

notice "Published ${VERSION} for ${ARCHES}"
