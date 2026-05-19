ARG SBT_VERSION=1.11.3

FROM sbtscala/scala-sbt:eclipse-temurin-21.0.7_6_${SBT_VERSION}_2.13.16

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-sbt-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Scala projects with sbt and warmed caches."

ARG SBT_VERSION
ARG GATLING_VERSION=3.13.5
ARG GATLING_SBT_VERSION=4.18.1
ARG PICATINNY_VERSION=1.12.0
ARG GALAXIO_CLI_VERSION=0.6.1

ENV HOME=/home/sbtuser \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    SBT_HOME=/home/sbtuser/.sbt \
    COURSIER_CACHE=/home/sbtuser/.cache/coursier/v1 \
    JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8" \
    JAVA_HOME=/opt/java/openjdk \
    PATH=/home/sbtuser/.local/bin:/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SCALA_HOME=/usr/share/scala \
    USER=sbtuser

ENV SBT_OPTS="${JAVA_OPTS_COMMON} -Dsbt.rootdir=true -Dsbt.ci=true" \
    GATLING_JAVA_OPTS="${JAVA_OPTS_COMMON} -XX:+HeapDumpOnOutOfMemoryError -XX:InitialRAMPercentage=50.0 -XX:MaxRAMPercentage=80.0 -XX:+UseG1GC"

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
WORKDIR /home/sbtuser

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl tar && \
    rm -rf /var/lib/apt/lists/*

COPY --chown=sbtuser:sbtuser resources/.sbtopts resources/sbt-warmup.sh /home/sbtuser/

USER sbtuser

RUN mkdir -p "${COURSIER_CACHE}" "${SBT_HOME}/boot" && \
    mkdir -p /home/sbtuser/.local/bin && \
    curl -fsSL "https://github.com/galax-io/galaxio-cli/releases/download/v${GALAXIO_CLI_VERSION}/galaxio_${GALAXIO_CLI_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /home/sbtuser/.local/bin galaxio && \
    chmod 0555 /home/sbtuser/.local/bin/galaxio && \
    chmod 0555 ./sbt-warmup.sh && \
    galaxio version && \
    java --version && \
    scala --version && \
    sbt --version && \
    ./sbt-warmup.sh "${SBT_VERSION}" "${GATLING_VERSION}" "${PICATINNY_VERSION}" "${GATLING_SBT_VERSION}" && \
    rm -f ./sbt-warmup.sh
