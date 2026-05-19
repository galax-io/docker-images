#!/usr/bin/env sh

set -eu

REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/resources/sbt-warmup.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  file="$1"
  pattern="$2"
  grep -F "$pattern" "$file" >/dev/null 2>&1 || fail "expected '$pattern' in $file"
}

assert_not_exists() {
  path="$1"
  [ ! -e "$path" ] || fail "expected $path to be removed"
}

assert_exists() {
  path="$1"
  [ -e "$path" ] || fail "expected $path to exist"
}

run_case() {
  case_name="$1"
  registry="$2"
  template_name="$3"
  archive_url="$4"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  mockbin="${tmpdir}/mockbin"
  workdir="${tmpdir}/work"
  sbt_home="${tmpdir}/sbt-home"
  log_file="${tmpdir}/commands.log"
  values_snapshot="${tmpdir}/warmup-values.snapshot"

  mkdir -p "${mockbin}" "${workdir}" "${sbt_home}"

  archive_root="${tmpdir}/archive-root"
  archive_payload="${tmpdir}/templates.tar.gz"
  mkdir -p "${archive_root}/galaxio-pack/scala-sbt/files"
  cat > "${archive_root}/galaxio-pack/galaxio-pack.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: TemplatePack
name: gatling
version: 0.0.0
templates:
  - name: scala-sbt
    version: 0.0.0
    path: scala-sbt
EOF
  cat > "${archive_root}/galaxio-pack/scala-sbt/galaxio-template.yaml" <<'EOF'
apiVersion: galaxio.io/v1
kind: Template
name: scala-sbt
engine: go-template
inputs: {}
files:
  - from: files
    to: .
EOF
  printf 'warmup\n' > "${archive_root}/galaxio-pack/scala-sbt/files/README.md"
  tar -C "${archive_root}" -czf "${archive_payload}" galaxio-pack

  cat > "${mockbin}/galaxio" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'galaxio|pwd=%s|%s\n' "$(pwd)" "$*" >> "${TEST_LOG_FILE}"
if [ "${1:-}" = "template" ] && [ "${2:-}" = "init" ]; then
  dest=""
  values=""
  prev=""
  for arg in "$@"; do
    if [ "${prev}" = "--destination" ]; then
      dest="${arg}"
    fi
    if [ "${prev}" = "--values" ]; then
      values="${arg}"
    fi
    prev="${arg}"
  done
  [ -n "${dest}" ] || exit 91
  mkdir -p "${dest}"
  if [ -n "${values}" ]; then
    cp "${values}" "${TEST_VALUES_SNAPSHOT}"
  fi
fi
EOF
  chmod +x "${mockbin}/galaxio"

  cat > "${mockbin}/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'curl|pwd=%s|%s\n' "$(pwd)" "$*" >> "${TEST_LOG_FILE}"
cat "${TEST_ARCHIVE_FILE}"
EOF
  chmod +x "${mockbin}/curl"

  cat > "${mockbin}/sbt" <<'EOF'
#!/usr/bin/env sh
set -eu
printf 'sbt|pwd=%s|%s\n' "$(pwd)" "$*" >> "${TEST_LOG_FILE}"
EOF
  chmod +x "${mockbin}/sbt"

  mkdir -p "${sbt_home}/boot"
  : > "${sbt_home}/boot/bootstrap.lock"

  (
    cd "${workdir}"
    PATH="${mockbin}:${PATH}" \
    TEST_LOG_FILE="${log_file}" \
    TEST_VALUES_SNAPSHOT="${values_snapshot}" \
    TEST_ARCHIVE_FILE="${archive_payload}" \
    SBT_HOME="${sbt_home}" \
    COURSIER_CACHE="${sbt_home}/coursier-cache" \
    GALAXIO_WARMUP_DIR="warmup-project" \
    GALAXIO_WARMUP_VALUES_FILE="warmup-values.yaml" \
    GALAXIO_TEMPLATE_REGISTRY="${registry}" \
    GALAXIO_TEMPLATE_NAME="${template_name}" \
    GALAXIO_TEMPLATES_ARCHIVE_URL="${archive_url}" \
    GALAXIO_TEMPLATE_REGISTRY_DIR="warmup-registry" \
    GALAXIO_TEMPLATES_DIR="warmup-templates" \
    sh "${SCRIPT}" 1.11.3 3.13.5 1.10.4 4.18.1
  )

  assert_exists "${values_snapshot}"
  assert_file_contains "${values_snapshot}" "SbtVersion: 1.11.3"
  assert_file_contains "${values_snapshot}" "GatlingVersion: 3.13.5"
  assert_file_contains "${values_snapshot}" "GatlingPicatinnyVersion: 1.10.4"
  assert_file_contains "${values_snapshot}" "SbtGatlingVersion: 4.18.1"

  assert_file_contains "${log_file}" "galaxio|pwd=${workdir}|template configure --registry ${registry}"
  assert_file_contains "${log_file}" "galaxio|pwd=${workdir}|template init ${template_name} --destination ./warmup-project --values ./warmup-values.yaml"
  assert_file_contains "${log_file}" "sbt|pwd=${workdir}/warmup-project|update compile Gatling / compile"

  assert_not_exists "${workdir}/warmup-project"
  assert_not_exists "${workdir}/warmup-values.yaml"
  assert_not_exists "${workdir}/warmup-registry"
  assert_not_exists "${workdir}/warmup-templates"
  assert_not_exists "${sbt_home}/boot/bootstrap.lock"

  rm -rf "${tmpdir}"
  trap - EXIT INT TERM
  printf 'PASS: %s\n' "${case_name}"
}

run_case "local bootstrap defaults" "local:./warmup-registry" "gatling/scala-sbt" "https://example.invalid/templates-gatling.tar.gz"
run_case "custom registry and template" "local:/tmp/custom-registry" "custom/scala-sbt" ""
