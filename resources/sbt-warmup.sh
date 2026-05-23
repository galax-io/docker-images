#!/usr/bin/env sh

set -eu

sbtVersion="${1}"
gatlingVersion="${2}"
picatinnyVersion="${3}"
gatlingSbt="${4}"

SBT_HOME="${SBT_HOME:-/home/sbtuser/.sbt}"
COURSIER_CACHE="${COURSIER_CACHE:-${SBT_HOME}/.cache/coursier/v1}"
GALAXIO_TEMPLATE_REGISTRY="${GALAXIO_TEMPLATE_REGISTRY:-}"
GALAXIO_TEMPLATE_NAME="${GALAXIO_TEMPLATE_NAME:-gatling/scala-sbt}"
GALAXIO_WARMUP_DIR="${GALAXIO_WARMUP_DIR:-warmup}"
GALAXIO_WARMUP_VALUES_FILE="${GALAXIO_WARMUP_VALUES_FILE:-warmup-values.yaml}"
GALAXIO_TEMPLATE_REGISTRY_DIR="${GALAXIO_TEMPLATE_REGISTRY_DIR:-galaxio-template-registry}"
GALAXIO_TEMPLATES_DIR="${GALAXIO_TEMPLATES_DIR:-templates-gatling-source}"
GALAXIO_TEMPLATES_REPOSITORY="${GALAXIO_TEMPLATES_REPOSITORY:-galax-io/templates-gatling}"
GALAXIO_TEMPLATES_REF="${GALAXIO_TEMPLATES_REF:-}"
GALAXIO_TEMPLATES_ARCHIVE_URL="${GALAXIO_TEMPLATES_ARCHIVE_URL:-}"
GALAXIO_TEMPLATES_CURL_RETRY_COUNT="${GALAXIO_TEMPLATES_CURL_RETRY_COUNT:-5}"
GALAXIO_TEMPLATES_CURL_RETRY_DELAY_SECONDS="${GALAXIO_TEMPLATES_CURL_RETRY_DELAY_SECONDS:-2}"
GALAXIO_TEMPLATES_CURL_CONNECT_TIMEOUT_SECONDS="${GALAXIO_TEMPLATES_CURL_CONNECT_TIMEOUT_SECONDS:-15}"
GALAXIO_TEMPLATES_CURL_MAX_TIME_SECONDS="${GALAXIO_TEMPLATES_CURL_MAX_TIME_SECONDS:-300}"
template_archive_tmp=""

cleanup_targets=""

validate_managed_path() {
  path="$1"

  case "${path}" in
    ""|/|.|..|-*)
      printf 'Refusing unsafe managed path: %s\n' "${path}" >&2
      exit 1
      ;;
  esac
}

remember_cleanup_target() {
  path="$1"

  validate_managed_path "${path}"

  if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
    cleanup_targets="${cleanup_targets}${cleanup_targets:+
}${path}"
  fi
}

cleanup() {
  [ -n "${cleanup_targets}" ] || return 0

  rm -f "${template_archive_tmp}"

  old_ifs="${IFS}"
  IFS='
'
  for path in ${cleanup_targets}; do
    rm -rf -- "${path}"
  done
  IFS="${old_ifs}"
}

remember_cleanup_target "${GALAXIO_WARMUP_DIR}"
remember_cleanup_target "${GALAXIO_WARMUP_VALUES_FILE}"
remember_cleanup_target "${GALAXIO_TEMPLATE_REGISTRY_DIR}"
remember_cleanup_target "${GALAXIO_TEMPLATES_DIR}"

trap cleanup EXIT

default_templates_ref() {
  case "${1}" in
    3.12.*)
      printf '%s\n' "v0.13.0"
      ;;
    *)
      printf '%s\n' "main"
      ;;
  esac
}

prepare_local_registry() {
  templates_ref="${GALAXIO_TEMPLATES_REF}"
  if [ -z "${templates_ref}" ]; then
    templates_ref="$(default_templates_ref "${gatlingVersion}")"
  fi

  if [ -n "${GALAXIO_TEMPLATES_ARCHIVE_URL}" ]; then
    archive_url="${GALAXIO_TEMPLATES_ARCHIVE_URL}"
  else
    archive_scope="heads"
    case "${templates_ref}" in
      v*)
        archive_scope="tags"
        ;;
    esac
    archive_url="https://github.com/${GALAXIO_TEMPLATES_REPOSITORY}/archive/refs/${archive_scope}/${templates_ref}.tar.gz"
  fi

  mkdir -p "${GALAXIO_TEMPLATES_DIR}" "${GALAXIO_TEMPLATE_REGISTRY_DIR}"
  template_archive_tmp="$(mktemp)"
  curl -fsSL \
    --retry "${GALAXIO_TEMPLATES_CURL_RETRY_COUNT}" \
    --retry-all-errors \
    --retry-delay "${GALAXIO_TEMPLATES_CURL_RETRY_DELAY_SECONDS}" \
    --connect-timeout "${GALAXIO_TEMPLATES_CURL_CONNECT_TIMEOUT_SECONDS}" \
    --max-time "${GALAXIO_TEMPLATES_CURL_MAX_TIME_SECONDS}" \
    -o "${template_archive_tmp}" \
    "${archive_url}"
  tar -xz -C "${GALAXIO_TEMPLATES_DIR}" --strip-components=1 < "${template_archive_tmp}"
  rm -f "${template_archive_tmp}"
  template_archive_tmp=""

  cat > "${GALAXIO_TEMPLATE_REGISTRY_DIR}/galaxio-registry.yaml" <<EOF
apiVersion: galaxio.io/v1
kind: TemplateRegistry
packs:
  - name: gatling
    source: local:./${GALAXIO_TEMPLATES_DIR}
EOF

  printf '%s\n' "local:./${GALAXIO_TEMPLATE_REGISTRY_DIR}"
}

export SBT_HOME
export COURSIER_CACHE

effective_values_file="${GALAXIO_WARMUP_VALUES_FILE}"
if [ -e "${GALAXIO_WARMUP_VALUES_FILE}" ] || [ -L "${GALAXIO_WARMUP_VALUES_FILE}" ]; then
  effective_values_file="$(mktemp "${GALAXIO_WARMUP_VALUES_FILE}.tmp.XXXXXX")"
  remember_cleanup_target "${effective_values_file}"
fi

mkdir -p "${COURSIER_CACHE}" "${SBT_HOME}/boot"
cat > "${effective_values_file}" <<EOF
Name: warmup
NameWord: warmup
Package: org.galaxio.performance
PackagePath: org/galaxio/performance
ScalaVersion: 2.13.18
SbtVersion: ${sbtVersion}
GatlingVersion: ${gatlingVersion}
SbtGatlingVersion: ${gatlingSbt}
GatlingPicatinnyVersion: ${picatinnyVersion}
BaseUrl: https://computer-database.gatling.io
BaseAuthUrl: https://computer-database.gatling.io/auth
WsBaseUrl: wss://computer-database.gatling.io/ws
ScenarioName: Warmup flow
KafkaPluginEnabled: "false"
JdbcPluginEnabled: "false"
AmqpPluginEnabled: "false"
StartupBannerEnabled: "false"
DiagnosticsEnabled: "false"
EOF

effective_registry="${GALAXIO_TEMPLATE_REGISTRY}"
if [ -z "${effective_registry}" ]; then
  effective_registry="$(prepare_local_registry)"
fi

galaxio template configure --registry "${effective_registry}"
galaxio template init "${GALAXIO_TEMPLATE_NAME}" \
  --destination "./${GALAXIO_WARMUP_DIR}" \
  --values "./${effective_values_file}"

cd "./${GALAXIO_WARMUP_DIR}"
sbt update compile "Gatling / compile"
cd ..

find "${SBT_HOME}/" -name "*.lock" -type f -delete
