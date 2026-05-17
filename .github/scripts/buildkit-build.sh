#!/usr/bin/env bash

set -euo pipefail

: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${IMAGE_TAGS:?IMAGE_TAGS is required}"
: "${DOCKERFILE_PATH:?DOCKERFILE_PATH is required}"
: "${CACHE_REF:?CACHE_REF is required}"

CONTEXT_DIR="${CONTEXT_DIR:-.}"
PUSH_IMAGE="${PUSH_IMAGE:-true}"
OUTPUT_FLAGS="${OUTPUT_FLAGS:-oci-mediatypes=true,name-canonical=true,push=${PUSH_IMAGE}}"

mapfile -t tag_lines < <(printf '%s\n' "${IMAGE_TAGS}" | sed '/^[[:space:]]*$/d')

if [[ "${#tag_lines[@]}" -eq 0 ]]; then
  echo "No image tags provided" >&2
  exit 1
fi

image_refs=()
for tag in "${tag_lines[@]}"; do
  image_refs+=("${IMAGE_NAME}:${tag}")
done

image_names_csv="$(IFS=,; echo "${image_refs[*]}")"

buildctl_args=(
  build
  --addr "${BUILDKIT_ADDR:-tcp://127.0.0.1:1234}"
  --frontend=dockerfile.v0
  --local "context=${CONTEXT_DIR}"
  --local "dockerfile=${CONTEXT_DIR}"
  --opt "filename=${DOCKERFILE_PATH}"
  --import-cache "type=registry,ref=${CACHE_REF}"
  --export-cache "type=registry,ref=${CACHE_REF},mode=max,image-manifest=true,oci-mediatypes=true"
  --output "type=image,name=${image_names_csv},${OUTPUT_FLAGS}"
)

if [[ -n "${BUILD_ARGS:-}" ]]; then
  while IFS= read -r build_arg; do
    [[ -z "${build_arg}" ]] && continue
    buildctl_args+=(--opt "build-arg:${build_arg}")
  done <<< "${BUILD_ARGS}"
fi

echo "Building ${IMAGE_NAME} from ${DOCKERFILE_PATH}"
printf 'Tags:\n%s\n' "${IMAGE_TAGS}"
printf 'Cache ref: %s\n' "${CACHE_REF}"

buildkitd_bin="${BUILDKITD_BIN:-/usr/local/bin/buildkitd}"
buildkit_addr="${BUILDKIT_ADDR:-tcp://127.0.0.1:1234}"
buildkit_log="$(mktemp)"
buildkitd_cmd=("${buildkitd_bin}" --addr "${buildkit_addr}")

if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  buildkitd_cmd=(sudo -E "${buildkitd_cmd[@]}")
fi

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

for _ in $(seq 1 30); do
  if buildctl --addr "${buildkit_addr}" debug workers >/dev/null 2>&1; then
    buildctl "${buildctl_args[@]}"
    exit 0
  fi
  sleep 1
done

cat "${buildkit_log}" >&2
echo "BuildKit daemon did not become ready" >&2
exit 1
