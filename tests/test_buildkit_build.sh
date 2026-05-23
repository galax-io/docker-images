#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/buildkit-build.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null 2>&1 || fail "expected '$pattern' in $file"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

mockbin="${tmpdir}/mockbin"
log_file="${tmpdir}/commands.log"
args_file="${tmpdir}/build.args"
mkdir -p "${mockbin}"

cat > "${mockbin}/buildctl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${log_file}"
if [[ "\${1:-}" == "--addr" && "\${3:-}" == "debug" && "\${4:-}" == "workers" ]]; then
  exit 0
fi
printf '%s\n' "\$@" > "${args_file}"
EOF
chmod +x "${mockbin}/buildctl"

cat > "${mockbin}/buildkitd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 30
EOF
chmod +x "${mockbin}/buildkitd"

(
  cd "${REPO_ROOT}"
  PATH="${mockbin}:/usr/bin:/bin" \
  IMAGE_NAME='docker.io/example/app' \
  IMAGE_TAGS=$'latest\n0.1.0\nv0.1.0' \
  DOCKERFILE_PATH='Dockerfile' \
  CACHE_REF='docker.io/example/cache:app' \
  BUILDKITD_BIN="${mockbin}/buildkitd" \
  BUILDKIT_ADDR='tcp://127.0.0.1:1234' \
  bash "${SCRIPT}"
)

assert_file_contains "${log_file}" "--addr tcp://127.0.0.1:1234 debug workers"
assert_file_contains "${args_file}" "--addr"
assert_file_contains "${args_file}" "build"
assert_file_contains "${args_file}" "type=image,\"name=docker.io/example/app:latest,docker.io/example/app:0.1.0,docker.io/example/app:v0.1.0\",oci-mediatypes=true,name-canonical=true,push=true"

printf 'PASS: buildkit helper multi-tag output\n'

: > "${log_file}"
: > "${args_file}"

(
  cd "${REPO_ROOT}"
  PATH="${mockbin}:/usr/bin:/bin" \
  IMAGE_NAME='docker.io/example/app' \
  IMAGE_TAGS='latest' \
  DOCKERFILE_PATH='Dockerfile' \
  CACHE_REF='docker.io/example/cache:app' \
  BUILDKITD_BIN="${mockbin}/buildkitd" \
  BUILDKIT_ADDR='tcp://127.0.0.1:1234' \
  PUSH_IMAGE='false' \
  bash "${SCRIPT}"
)

assert_file_contains "${args_file}" "push=false"

printf 'PASS: buildkit helper respects PUSH_IMAGE=false\n'
