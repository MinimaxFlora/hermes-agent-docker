#!/usr/bin/env bash
#
# Stitch the per-architecture image digests into multi-arch manifests and
# publish exactly two user-facing tags per registry:
#   - <TAG>     (upstream release tag, e.g. v0.22.2)
#   - latest    (only when this is the newest upstream release)
#
# The per-architecture images were pushed by digest (no -amd64/-arm64 tags),
# so the registries only ever see the final tags.
#
# Required environment:
#   TAG, ARCHES, COMMIT, DIGEST_DIR, DOCKERHUB_IMAGE, GHCR_IMAGE
# Optional:
#   UPDATE_LATEST (true/false), GITHUB_STEP_SUMMARY

set -Eeuo pipefail

: "${TAG:?TAG is required}"
: "${ARCHES:?ARCHES is required}"
: "${COMMIT:?COMMIT is required}"
: "${DIGEST_DIR:?DIGEST_DIR is required}"
: "${DOCKERHUB_IMAGE:?DOCKERHUB_IMAGE is required}"
: "${GHCR_IMAGE:?GHCR_IMAGE is required}"

readonly UPDATE_LATEST="${UPDATE_LATEST:-false}"
readonly SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

notice() { printf '::notice::%s\n' "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

inspect_digest() {
  # 不要用 exit 提前关闭管道:docker 会收到 SIGPIPE,在 pipefail 下变成 255
  docker buildx imagetools inspect "$1" | awk '$1 == "Digest:" && !seen {d = $2; seen = 1} END {if (d) print d}'
}

inspect_platforms() {
  docker buildx imagetools inspect "$1" |
    awk '$1 == "Platform:" {sub(/^linux\//, "", $2); print $2}' |
    sort -u
}

read -r -a arch_list <<<"${ARCHES}"
[[ "${#arch_list[@]}" -gt 0 ]] || fail "ARCHES is empty"

tag_list=("${TAG}")
if [[ "${UPDATE_LATEST}" == "true" ]]; then
  tag_list+=("latest")
fi

declare -A digests=()

for image in "${DOCKERHUB_IMAGE}" "${GHCR_IMAGE}"; do
  case "$image" in
    "$GHCR_IMAGE") registry_key="ghcr" ;;
    *)             registry_key="dockerhub" ;;
  esac
  sources=()
  for arch in "${arch_list[@]}"; do
    digest_file="${DIGEST_DIR}/${arch}-${registry_key}.txt"
    [[ -f "$digest_file" ]] || fail "Missing ${registry_key} digest for ${arch}: ${digest_file}"
    digest="$(cat "$digest_file")"
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "Invalid ${registry_key} digest for ${arch}: ${digest}"
    sources+=("${image}@${digest}")
  done

  create_args=()
  for tag in "${tag_list[@]}"; do
    create_args+=(-t "${image}:${tag}")
  done

  notice "Creating multi-arch manifest for ${image} (${tag_list[*]})"
  docker buildx imagetools create "${create_args[@]}" "${sources[@]}"

  digest="$(inspect_digest "${image}:${TAG}")"
  [[ -n "${digest}" ]] || fail "Unable to read the manifest digest for ${image}:${TAG}"
  digests["${image}"]="${digest}"

  platforms="$(inspect_platforms "${image}:${TAG}")"
  if [[ "${#arch_list[@]}" -gt 1 ]]; then
    for arch in "${arch_list[@]}"; do
      if ! grep -qx "${arch}" <<<"${platforms}"; then
        fail "${image}:${TAG} is missing the linux/${arch} platform (found: ${platforms:-none})"
      fi
    done
  fi

  if [[ "${UPDATE_LATEST}" == "true" ]]; then
    latest_digest="$(inspect_digest "${image}:latest")"
    if [[ "${latest_digest}" != "${digest}" ]]; then
      fail "${image}:latest (${latest_digest}) does not match ${TAG} (${digest})"
    fi
  fi
done

{
  echo "## Published images"
  echo ""
  echo "| Registry | Tags | Digest |"
  echo "| --- | --- | --- |"
  for image in "${DOCKERHUB_IMAGE}" "${GHCR_IMAGE}"; do
    echo "| \`${image}\` | ${tag_list[*]} | \`${digests[${image}]}\` |"
  done
  echo ""
  echo "Upstream tag: \`${TAG}\`"
  echo "Upstream commit: \`${COMMIT}\`"
} >>"${SUMMARY_FILE}"

notice "Published ${TAG} for ${ARCHES} (tags: ${tag_list[*]})"
