#!/usr/bin/env bash

set -euo pipefail

: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${IMAGE_TAGS:?IMAGE_TAGS is required}"
: "${DOCKERFILE_PATH:?DOCKERFILE_PATH is required}"
: "${CACHE_REF:?CACHE_REF is required}"

CONTEXT_DIR="${CONTEXT_DIR:-.}"
PUSH_IMAGE="${PUSH_IMAGE:-true}"
OUTPUT_FLAGS="${OUTPUT_FLAGS:-oci-mediatypes=true,name-canonical=true,push=${PUSH_IMAGE}}"
BUILDKIT_ADDR="${BUILDKIT_ADDR:-tcp://127.0.0.1:1234}"
BUILDKITD_BIN="${BUILDKITD_BIN:-/usr/local/bin/buildkitd}"

non_empty_lines() {
  printf '%s\n' "$1" | sed '/^[[:space:]]*$/d'
}

tag_lines=()
while IFS= read -r tag_line; do
  tag_lines+=("${tag_line}")
done < <(non_empty_lines "${IMAGE_TAGS}")

if [[ "${#tag_lines[@]}" -eq 0 ]]; then
  echo "No image tags provided" >&2
  exit 1
fi

image_refs=()
for tag in "${tag_lines[@]}"; do
  image_refs+=("${IMAGE_NAME}:${tag}")
done

image_names_csv="$(IFS=,; echo "${image_refs[*]}")"
image_output="type=image,\"name=${image_names_csv}\",${OUTPUT_FLAGS}"

buildctl_args=(
  --addr "${BUILDKIT_ADDR}"
  build
  --frontend=dockerfile.v0
  --local "context=${CONTEXT_DIR}"
  --local "dockerfile=${CONTEXT_DIR}"
  --opt "filename=${DOCKERFILE_PATH}"
  --import-cache "type=registry,ref=${CACHE_REF}"
  --export-cache "type=registry,ref=${CACHE_REF},mode=max,image-manifest=true,oci-mediatypes=true"
  --output "${image_output}"
)

if [[ -n "${BUILD_ARGS:-}" ]]; then
  while IFS= read -r build_arg; do
    buildctl_args+=(--opt "build-arg:${build_arg}")
  done < <(non_empty_lines "${BUILD_ARGS}")
fi

echo "Building ${IMAGE_NAME} from ${DOCKERFILE_PATH}"
printf 'Tags:\n%s\n' "${IMAGE_TAGS}"
printf 'Cache ref: %s\n' "${CACHE_REF}"

buildkit_log="$(mktemp)"
buildkitd_cmd=("${BUILDKITD_BIN}" --addr "${BUILDKIT_ADDR}")

if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  buildkitd_cmd=(sudo -E "${buildkitd_cmd[@]}")
fi

# shellcheck disable=SC2329
cleanup() {
  if [[ -n "${buildkitd_pid:-}" ]] && kill -0 "${buildkitd_pid}" 2>/dev/null; then
    kill "${buildkitd_pid}" 2>/dev/null || true
    wait "${buildkitd_pid}" 2>/dev/null || true
  fi
  rm -f "${buildkit_log}"
}

trap cleanup EXIT

"${buildkitd_cmd[@]}" >"${buildkit_log}" 2>&1 &
buildkitd_pid=$!

for ((attempt = 0; attempt < 30; attempt++)); do
  if buildctl --addr "${BUILDKIT_ADDR}" debug workers >/dev/null 2>&1; then
    buildctl "${buildctl_args[@]}"
    exit 0
  fi
  sleep 1
done

cat "${buildkit_log}" >&2
echo "BuildKit daemon did not become ready" >&2
exit 1
