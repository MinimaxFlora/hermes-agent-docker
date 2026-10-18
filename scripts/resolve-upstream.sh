#!/usr/bin/env bash
#
# Resolve the upstream Hermes Agent release that should be published and
# decide whether this run actually needs to build anything.
#
# Required environment variables:
#   UPSTREAM_REPO       GitHub repository, e.g. NousResearch/hermes-agent
#   IMAGE_NAME         Image name, e.g. hermes-agent
#   DOCKERHUB_USERNAME Docker Hub account that owns IMAGE_NAME
#   GH_TOKEN           Token for the GitHub REST API
#
# Optional environment variables:
#   EVENT_NAME, PUSH_INPUT, FORCE_INPUT, ARCHES_INPUT, REF_INPUT
#   RUNNER_AMD64, RUNNER_ARM64 (runner labels)
#   GITHUB_REPOSITORY_OWNER, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY
#
# The script writes GitHub Actions outputs and appends a human-readable
# summary to $GITHUB_STEP_SUMMARY.

set -Eeuo pipefail

: "${UPSTREAM_REPO:?UPSTREAM_REPO is required}"
: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

readonly EVENT_NAME="${EVENT_NAME:-schedule}"
readonly PUSH_INPUT="${PUSH_INPUT:-true}"
readonly FORCE="${FORCE_INPUT:-false}"
readonly ARCHES="${ARCHES_INPUT:-both}"
readonly REF_INPUT="${REF_INPUT:-}"
readonly RUNNER_AMD64="${RUNNER_AMD64:-ubuntu-24.04}"
readonly RUNNER_ARM64="${RUNNER_ARM64:-ubuntu-24.04-arm}"
readonly OWNER_LC="${GITHUB_REPOSITORY_OWNER:-minimaxflora}"
readonly DOCKERHUB_IMAGE="docker.io/${DOCKERHUB_USERNAME}/${IMAGE_NAME}"
readonly GHCR_IMAGE="ghcr.io/${OWNER_LC,,}/${IMAGE_NAME}"
readonly API_URL="https://api.github.com/repos/${UPSTREAM_REPO}"
readonly TAG_PATTERN='^v?[0-9]+\.[0-9]+\.[0-9]+([.+_-][0-9A-Za-z.-]+)?$'
readonly OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"
readonly SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

notice() { printf '::notice::%s\n' "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }
set_output() { printf '%s=%s\n' "$1" "$2" >>"${OUTPUT_FILE}"; }

fetch_latest_release() {
  curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
    -H 'Accept: application/vnd.github+json' \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "${API_URL}/releases/latest"
}

resolve_commit() {
  local ref="$1" sha
  sha="$(git ls-remote --tags "https://github.com/${UPSTREAM_REPO}.git" \
    "refs/tags/${ref}^{}" 2>/dev/null | awk 'NR==1 {print $1}')" || true
  if [[ -z "${sha}" ]]; then
    sha="$(git ls-remote --tags "https://github.com/${UPSTREAM_REPO}.git" \
      "refs/tags/${ref}" 2>/dev/null | awk 'NR==1 {print $1}')" || true
  fi
  printf '%s' "${sha}"
}

dockerhub_has_tag() {
  curl -fsS -o /dev/null --max-time 20 --retry 2 --retry-delay 1 \
    "https://hub.docker.com/v2/repositories/${DOCKERHUB_USERNAME}/${IMAGE_NAME}/tags/$1"
}

ghcr_has_tag() {
  docker buildx imagetools inspect "${GHCR_IMAGE}:$1" >/dev/null 2>&1
}

# --- Upstream release -------------------------------------------------------

release_json="$(fetch_latest_release)" || fail "Unable to read ${UPSTREAM_REPO} releases"
latest_tag="$(jq -er '.tag_name' <<<"${release_json}")" ||
  fail "The latest release has no tag_name"
published_at="$(jq -r '.published_at // ""' <<<"${release_json}")"
[[ "${latest_tag}" =~ ${TAG_PATTERN} ]] ||
  fail "Unexpected upstream release tag: ${latest_tag}"

if [[ -n "${REF_INPUT}" ]]; then
  tag="${REF_INPUT}"
  [[ "${tag}" =~ ${TAG_PATTERN} ]] ||
    fail "Unsupported ref '${tag}': pass a release tag such as v0.22.2"
  reason="manual dispatch"
else
  tag="${latest_tag}"
  reason="latest upstream release"
fi

version="${tag#v}"
latest_version="${latest_tag#v}"

# ``latest`` must only follow the newest release. A manual build of an older
# tag stays on its immutable version tags.
update_latest="false"
if [[ "${version}" == "${latest_version}" ]]; then
  update_latest="true"
fi

commit="$(resolve_commit "${tag}")"
[[ "${commit}" =~ ^[0-9a-f]{40}$ ]] ||
  fail "Unable to resolve the commit for tag ${tag}"

notice "Upstream tag ${tag} (${commit})"

# --- Should we build? -------------------------------------------------------

build="true"
if [[ "${FORCE}" == "true" ]]; then
  reason="forced rebuild"
else
  hub_exists="false"
  ghcr_exists="false"
  if dockerhub_has_tag "${tag}"; then
    hub_exists="true"
  fi
  if ghcr_has_tag "${tag}"; then
    ghcr_exists="true"
  fi

  if [[ "${hub_exists}" == "true" && "${ghcr_exists}" == "true" ]]; then
    build="false"
    reason="tag ${tag} already published"
  elif [[ "${hub_exists}" == "false" && "${ghcr_exists}" == "false" ]]; then
    reason="tag ${tag} missing from both registries"
  elif [[ "${hub_exists}" == "false" ]]; then
    reason="tag ${tag} missing from Docker Hub"
  else
    reason="tag ${tag} missing from GHCR"
  fi
fi

push="true"
if [[ "${EVENT_NAME}" == "workflow_dispatch" && "${PUSH_INPUT}" != "true" ]]; then
  push="false"
fi

# --- Build matrix -----------------------------------------------------------

case "${ARCHES}" in
  both | amd64 | arm64) ;;
  *) fail "Invalid ARCHES value: ${ARCHES}" ;;
esac

matrix="$(jq -cn \
  --arg arches "${ARCHES}" \
  --arg amd64_runner "${RUNNER_AMD64}" \
  --arg arm64_runner "${RUNNER_ARM64}" \
  '[
    {arch: "amd64", runner: $amd64_runner, platform: "linux/amd64"},
    {arch: "arm64", runner: $arm64_runner, platform: "linux/arm64"}
  ]
  | if $arches == "both" then . else map(select(.arch == $arches)) end')"
arches="$(jq -r '.[].arch' <<<"${matrix}" | paste -sd ' ' -)"

# --- Outputs ----------------------------------------------------------------

set_output tag "${tag}"
set_output version "${version}"
set_output commit "${commit}"
set_output build "${build}"
set_output push "${push}"
set_output update_latest "${update_latest}"
set_output arches "${arches}"
set_output matrix "${matrix}"
set_output dockerhub_image "${DOCKERHUB_IMAGE}"
set_output ghcr_image "${GHCR_IMAGE}"
set_output reason "${reason}"

# --- Job summary ------------------------------------------------------------

{
  echo "## Hermes Agent Docker"
  echo ""
  echo "| Field | Value |"
  echo "| --- | --- |"
  echo "| Upstream tag | \`${tag}\` |"
  echo "| Upstream commit | \`${commit}\` |"
  echo "| Published at | ${published_at:-unknown} |"
  echo "| Build | ${build} (${reason}) |"
  echo "| Push | ${push} |"
  echo "| Architectures | ${arches} |"
  echo "| Docker Hub | \`${DOCKERHUB_IMAGE}\` |"
  echo "| GHCR | \`${GHCR_IMAGE}\` |"
} >>"${SUMMARY_FILE}"

if [[ "${build}" == "true" ]]; then
  notice "Building ${version} (${reason})"
else
  notice "Skipping build: ${reason}"
fi
