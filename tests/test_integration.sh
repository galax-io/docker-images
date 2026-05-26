#!/usr/bin/env bash
# Integration tests for Galaxio Docker images.
# Pulls the specified image and asserts:
#   1. The image can be pulled
#   2. The container runs as UID 65532 (nonroot)
#   3. The entrypoint works (docker run echo ok)
#   4. The relevant build tool responds (java/sbt/mvn/gradle --version)
#
# Usage (positional):
#   bash tests/test_integration.sh <IMAGE_REF> [IMAGE_TYPE]
#
# Usage (env vars):
#   IMAGE_REF=galaxioteam/base-jdk:21-abc1234 IMAGE_TYPE=jdk bash tests/test_integration.sh
#
# IMAGE_TYPE values: jdk | sbt-builder | maven-builder | gradle-builder |
#                    sbt-runtime | maven-runtime | gradle-runtime
#
# Exit codes: 0 = all assertions passed, non-zero = one or more failures.

set -uo pipefail

IMAGE_REF="${1:-${IMAGE_REF:-}}"
IMAGE_TYPE="${2:-${IMAGE_TYPE:-jdk}}"

if [[ -z "${IMAGE_REF}" ]]; then
  printf 'ERROR: IMAGE_REF (or $1) is required — full image:tag to test\n' >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "${desc}"
  else
    fail "${desc}"
  fi
}

printf '=== Integration test: %s  (type=%s) ===\n\n' "${IMAGE_REF}" "${IMAGE_TYPE}"

# ---------------------------------------------------------------------------
# Test 1: pull image
# ---------------------------------------------------------------------------
printf '--- Test: docker pull ---\n'
check "docker pull ${IMAGE_REF}" docker pull "${IMAGE_REF}"

# ---------------------------------------------------------------------------
# Test 2: non-root UID = 65532
# Runtime images use ENTRYPOINT ["/bin/bash", "-c"], pass command as string.
# Other images have no custom ENTRYPOINT — pass command directly.
# ---------------------------------------------------------------------------
printf '--- Test: non-root UID ---\n'
case "${IMAGE_TYPE}" in
  *-runtime)
    uid_output="$(docker run --rm "${IMAGE_REF}" "id -u" 2>&1 || echo "error")" ;;
  *)
    uid_output="$(docker run --rm "${IMAGE_REF}" id -u 2>&1 || echo "error")" ;;
esac
uid_output="$(printf '%s' "${uid_output}" | tr -d '[:space:]')"
if [[ "${uid_output}" == "65532" ]]; then
  pass "UID is 65532 (nonroot)"
else
  fail "UID is '${uid_output}', expected 65532"
fi

# ---------------------------------------------------------------------------
# Test 3: entrypoint echo
# ---------------------------------------------------------------------------
printf '--- Test: entrypoint ---\n'
case "${IMAGE_TYPE}" in
  *-runtime)
    check "entrypoint echo ok" docker run --rm "${IMAGE_REF}" "echo ok" ;;
  *)
    check "entrypoint echo ok" docker run --rm "${IMAGE_REF}" echo ok ;;
esac

# ---------------------------------------------------------------------------
# Test 4: build tool version check
# ---------------------------------------------------------------------------
printf '--- Test: build tool ---\n'
case "${IMAGE_TYPE}" in
  *sbt*)
    check "sbt --version" docker run --rm "${IMAGE_REF}" sbt --version ;;
  *maven*)
    check "mvn --version" docker run --rm "${IMAGE_REF}" mvn --version ;;
  *gradle*)
    check "gradle --version" docker run --rm "${IMAGE_REF}" gradle --version ;;
  *)
    check "java -version" docker run --rm "${IMAGE_REF}" java -version ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=== Results: %d passed, %d failed ===\n' "${PASS_COUNT}" "${FAIL_COUNT}"

[ "${FAIL_COUNT}" -eq 0 ]
