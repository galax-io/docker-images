# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG SBT_VERSION=1.11.3
ARG GATLING_VERSION=3.13.5
ARG GATLING_SBT_VERSION=4.18.1
ARG PICATINNY_VERSION=1.12.3
ARG SCALAFMT_VERSION=2.6.1

# Warmup: official sbt image (has JDK + sbt + scala + bash + curl)
# Creates an inline Gatling project to pre-download all dependencies into Coursier cache
FROM sbtscala/scala-sbt:eclipse-temurin-21.0.7_6_${SBT_VERSION}_2.13.16 AS warmup

ARG SBT_VERSION
ARG GATLING_VERSION
ARG GATLING_SBT_VERSION
ARG PICATINNY_VERSION
ARG SCALAFMT_VERSION

ENV HOME=/home/sbtuser \
    SBT_HOME=/home/sbtuser/.sbt \
    COURSIER_CACHE=/home/sbtuser/.cache/coursier/v1 \
    SBT_OPTS="-Dsbt.ci=true \
              -Dfile.encoding=UTF-8 \
              -Dsbt.boot.directory=/home/sbtuser/.sbt/boot \
              -Dsbt.global.base=/home/sbtuser/.sbt \
              -Dcoursier.cache=/home/sbtuser/.cache/coursier/v1"

USER sbtuser
WORKDIR /home/sbtuser

RUN mkdir -p warmup/project warmup/src/test/scala && \
    printf 'addSbtPlugin("io.gatling" %% "gatling-sbt" %% "%s")\n' "${GATLING_SBT_VERSION}" \
      > warmup/project/plugins.sbt && \
    printf 'addSbtPlugin("org.scalameta" %% "sbt-scalafmt" %% "%s")\n' "${SCALAFMT_VERSION}" \
      >> warmup/project/plugins.sbt

# Mirrors the real galaxio template (templates-gatling scala-sbt) dependency graph.
# gatling-test-framework excluded — gatling-sbt uses Gatling/test, not sbt test.
# janino excluded — optional Logback runtime, not a build dependency.
RUN cat > warmup/build.sbt <<EOF
scalaVersion := "2.13.16"
enablePlugins(GatlingPlugin)
libraryDependencies ++= Seq(
  "io.gatling.highcharts" % "gatling-charts-highcharts" % "${GATLING_VERSION}" % Test,
  "org.galaxio"          %% "gatling-picatinny"         % "${PICATINNY_VERSION}" % Test
)
EOF

RUN cat > warmup/src/test/scala/WarmupSimulation.scala <<'EOF'
import io.gatling.core.Predef._
class WarmupSimulation extends Simulation
EOF

RUN cd warmup && \
    sbt "Gatling / compile" && \
    cd .. && rm -rf warmup && \
    find /home/sbtuser/.sbt/ -name "*.lock" -delete 2>/dev/null || true && \
    find /home/sbtuser/.cache/ -name "*.lock" -delete 2>/dev/null || true


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-sbt-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Scala/SBT projects with warmed Coursier and SBT caches."

# sbt + scala binaries from warmup stage
COPY --from=warmup --link /usr/share/sbt/ /usr/share/sbt/
COPY --from=warmup --link /usr/share/scala/ /usr/share/scala/
COPY --from=warmup --link /usr/local/bin/sbt /usr/local/bin/sbt

# Warmed dependency caches
COPY --from=warmup --link --chown=65532:65532 /home/sbtuser/.sbt/ /home/nonroot/.sbt/
COPY --from=warmup --link --chown=65532:65532 /home/sbtuser/.cache/ /home/nonroot/.cache/

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    SBT_HOME=/home/nonroot/.sbt \
    COURSIER_CACHE=/home/nonroot/.cache/coursier/v1 \
    SCALA_HOME=/usr/share/scala \
    JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8" \
    SBT_OPTS="-Dconfig.override_with_env_vars=true \
              -Dfile.encoding=UTF-8 \
              -Dsbt.rootdir=true \
              -Dsbt.ci=true \
              -Dsbt.boot.directory=/home/nonroot/.sbt/boot \
              -Dsbt.global.base=/home/nonroot/.sbt \
              -Dcoursier.cache=/home/nonroot/.cache/coursier/v1" \
    GATLING_JAVA_OPTS="-Dconfig.override_with_env_vars=true \
                       -Dfile.encoding=UTF-8 \
                       -XX:+HeapDumpOnOutOfMemoryError \
                       -XX:InitialRAMPercentage=50.0 \
                       -XX:MaxRAMPercentage=80.0 \
                       -XX:+UseG1GC" \
    PATH=/opt/java/openjdk/bin:/usr/local/bin:/usr/share/scala/bin:/usr/bin:/bin

WORKDIR /home/nonroot
USER nonroot:nonroot

RUN sbt --version && scala --version && galaxio version
