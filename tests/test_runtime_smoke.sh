#!/usr/bin/env bash
# Smoke test for gatling-runtime container images.
# Usage: tests/test_runtime_smoke.sh <image>
# Verifies: non-root UID (65532), build tool reachability, entrypoint resolution.

set -euo pipefail

IMAGE="${1:-${IMAGE:-}}"
if [[ -z "$IMAGE" ]]; then
  echo "Usage: $0 <image>" >&2
  exit 1
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "Smoke-testing image: $IMAGE"
echo ""

# Pull image once so docker run output is not mixed into captured variables.
docker pull "$IMAGE" >/dev/null 2>&1

# Test 1: container runs as non-root user (UID 65532 = nonroot)
UID_OUTPUT=$(docker run --rm "$IMAGE" "id -u")
if [[ "$UID_OUTPUT" == "65532" ]]; then
  pass "non-root UID (65532)"
else
  fail "expected UID 65532, got: ${UID_OUTPUT}"
fi

# Test 2: build tool reachable (auto-detect sbt / mvn / gradle)
BUILD_TOOL_OK=false
if docker run --rm "$IMAGE" "sbt --version" >/dev/null 2>&1; then
  pass "sbt reachable"
  BUILD_TOOL_OK=true
elif docker run --rm "$IMAGE" "mvn --version" >/dev/null 2>&1; then
  pass "mvn reachable"
  BUILD_TOOL_OK=true
elif docker run --rm "$IMAGE" "gradle --version" >/dev/null 2>&1; then
  pass "gradle reachable"
  BUILD_TOOL_OK=true
fi
if ! $BUILD_TOOL_OK; then
  fail "no build tool (sbt/mvn/gradle) reachable"
fi

# Test 3: entrypoint resolves cleanly (container exits 0)
if docker run --rm "$IMAGE" "exit 0" >/dev/null 2>&1; then
  pass "entrypoint resolves"
else
  fail "entrypoint did not resolve cleanly"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
