# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG SBT_VERSION=1.11.3
ARG GATLING_VERSION=3.13.5
ARG GATLING_SBT_VERSION=4.18.1
ARG PICATINNY_VERSION=1.12.3
ARG GALAXIO_CLI_VERSION=0.6.1

# Warmup: official sbt image (has JDK + sbt + scala + bash + curl)
# Uses `galaxio template init` with all plugins (kafka, jdbc, amqp) enabled
# to warm the real dependency graph into Coursier cache
FROM sbtscala/scala-sbt:eclipse-temurin-21.0.7_6_${SBT_VERSION}_2.13.16 AS warmup

ARG SBT_VERSION
ARG GATLING_VERSION
ARG GATLING_SBT_VERSION
ARG PICATINNY_VERSION
ARG GALAXIO_CLI_VERSION

ENV HOME=/home/sbtuser \
    SBT_HOME=/home/sbtuser/.sbt \
    COURSIER_CACHE=/home/sbtuser/.cache/coursier/v1 \
    SBT_OPTS="-Dsbt.ci=true \
              -Dfile.encoding=UTF-8 \
              -Dsbt.boot.directory=/home/sbtuser/.sbt/boot \
              -Dsbt.global.base=/home/sbtuser/.sbt \
              -Dcoursier.cache=/home/sbtuser/.cache/coursier/v1"

USER root
RUN curl -fsSL \
      "https://github.com/galax-io/galaxio-cli/releases/download/v${GALAXIO_CLI_VERSION}/galaxio_${GALAXIO_CLI_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin galaxio && \
    chmod 0755 /usr/local/bin/galaxio

USER sbtuser
WORKDIR /home/sbtuser

COPY --chown=sbtuser:sbtuser resources/sbt-warmup.sh /home/sbtuser/sbt-warmup.sh

RUN chmod +x /home/sbtuser/sbt-warmup.sh && \
    /home/sbtuser/sbt-warmup.sh \
      "${SBT_VERSION}" \
      "${GATLING_VERSION}" \
      "${PICATINNY_VERSION}" \
      "${GATLING_SBT_VERSION}" && \
    find /home/sbtuser/.sbt/ -name "*.lock" -type f -delete && \
    find /home/sbtuser/.cache/ -name "*.lock" -type f -delete


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
