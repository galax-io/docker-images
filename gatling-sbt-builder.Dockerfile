# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG SBT_VERSION=1.11.3
ARG GATLING_VERSION=3.13.5
ARG GATLING_SBT_VERSION=4.18.1
ARG PICATINNY_VERSION=1.10.4

FROM sbtscala/scala-sbt:eclipse-temurin-21.0.7_6_${SBT_VERSION}_2.13.16 AS tool-src


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION} AS jdk-src


FROM debian:bookworm-slim AS warmup

ARG SBT_VERSION
ARG GATLING_VERSION
ARG GATLING_SBT_VERSION
ARG PICATINNY_VERSION

ENV JAVA_HOME=/opt/java/openjdk \
    PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/sbtuser \
    SBT_HOME=/home/sbtuser/.sbt \
    COURSIER_CACHE=/home/sbtuser/.cache/coursier/v1 \
    SBT_OPTS="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8 -Dsbt.rootdir=true -Dsbt.ci=true" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl

# Copy JDK from published base-jdk
COPY --from=jdk-src --link /opt/java/openjdk/ /opt/java/openjdk/

# Copy sbt + scala from official sbt image
COPY --from=tool-src --link /usr/share/sbt/ /usr/share/sbt/
COPY --from=tool-src --link /usr/share/scala/ /usr/share/scala/
COPY --from=tool-src --link /usr/local/bin/sbt /usr/local/bin/sbt

# Copy galaxio-cli
COPY --from=jdk-src --link /usr/local/bin/galaxio /usr/local/bin/galaxio

RUN groupadd --gid 10001 sbtuser && \
    useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash sbtuser

RUN mkdir -p "${COURSIER_CACHE}" "${SBT_HOME}/boot" && \
    chown -R sbtuser:sbtuser /home/sbtuser

USER sbtuser
WORKDIR /home/sbtuser

COPY --chown=sbtuser:sbtuser resources/.sbtopts resources/sbt-warmup.sh /home/sbtuser/

RUN chmod 0555 ./sbt-warmup.sh && \
    ./sbt-warmup.sh "${SBT_VERSION}" "${GATLING_VERSION}" "${PICATINNY_VERSION}" "${GATLING_SBT_VERSION}" && \
    find "${SBT_HOME}/" -name "*.lock" -type f -delete && \
    rm -f ./sbt-warmup.sh


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-sbt-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Scala/SBT projects with warmed Coursier and SBT caches."

ARG SBT_VERSION

# sbt + scala binaries
COPY --from=tool-src --link /usr/share/sbt/ /usr/share/sbt/
COPY --from=tool-src --link /usr/share/scala/ /usr/share/scala/
COPY --from=tool-src --link /usr/local/bin/sbt /usr/local/bin/sbt

# Warmed caches from warmup stage
COPY --from=warmup --link --chown=nonroot:nonroot /home/sbtuser/.sbt/ /home/nonroot/.sbt/
COPY --from=warmup --link --chown=nonroot:nonroot /home/sbtuser/.cache/ /home/nonroot/.cache/

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    SBT_HOME=/home/nonroot/.sbt \
    COURSIER_CACHE=/home/nonroot/.cache/coursier/v1 \
    SCALA_HOME=/usr/share/scala \
    JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8" \
    SBT_OPTS="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8 -Dsbt.rootdir=true -Dsbt.ci=true" \
    GATLING_JAVA_OPTS="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8 -XX:+HeapDumpOnOutOfMemoryError -XX:InitialRAMPercentage=50.0 -XX:MaxRAMPercentage=80.0 -XX:+UseG1GC"

WORKDIR /home/nonroot
USER nonroot:nonroot

RUN sbt --version && scala --version && galaxio version
