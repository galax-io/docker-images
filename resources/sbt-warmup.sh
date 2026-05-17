#!/usr/bin/env sh

set -eu

sbtVersion="${1}"
gatlingVersion="${2}"
picatinnyVersion="${3}"
gatlingSbt="${4}"

SBT_HOME="${SBT_HOME:-/home/sbtuser/.sbt}"
COURSIER_CACHE="${COURSIER_CACHE:-${SBT_HOME}/.cache/coursier/v1}"
GALAXIO_TEMPLATE_REGISTRY="${GALAXIO_TEMPLATE_REGISTRY:-github:galax-io/galaxio-template-registry}"
GALAXIO_TEMPLATE_NAME="${GALAXIO_TEMPLATE_NAME:-gatling/scala-sbt}"
GALAXIO_WARMUP_DIR="${GALAXIO_WARMUP_DIR:-warmup}"
GALAXIO_WARMUP_VALUES_FILE="${GALAXIO_WARMUP_VALUES_FILE:-warmup-values.yaml}"

cleanup() {
  rm -rf "${GALAXIO_WARMUP_DIR}" "${GALAXIO_WARMUP_VALUES_FILE}"
}

trap cleanup EXIT

export SBT_HOME
export COURSIER_CACHE

mkdir -p "${COURSIER_CACHE}" "${SBT_HOME}/boot"
cat > "${GALAXIO_WARMUP_VALUES_FILE}" <<EOF
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

galaxio template configure --registry "${GALAXIO_TEMPLATE_REGISTRY}"
galaxio template init "${GALAXIO_TEMPLATE_NAME}" \
  --destination "./${GALAXIO_WARMUP_DIR}" \
  --values "./${GALAXIO_WARMUP_VALUES_FILE}"

cd "./${GALAXIO_WARMUP_DIR}"
sbt update compile "Gatling / compile"
cd ..

find "${SBT_HOME}/" -name "*.lock" -type f -delete
