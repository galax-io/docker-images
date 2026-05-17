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

buildkit_runner="${BUILDKIT_RUNNER:-/usr/local/bin/buildctl-daemonless.sh}"
"${buildkit_runner}" "${buildctl_args[@]}"
