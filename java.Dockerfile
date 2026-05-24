# syntax=docker/dockerfile:1
# base-jdk: stripped Debian base with JDK and galaxio-cli.
# Inherits from galaxioteam/galaxio-cli conceptually (galaxio binary included),
# but uses debian:bookworm-slim as its root — required because build tool scripts
# (sbt, mvn, gradle launcher scripts) need coreutils (uname, dirname, basename, etc.)
# that are absent in distroless images.
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG GALAXIO_CLI_VERSION=0.6.1

FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy AS jdk

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

RUN bash -euxo pipefail -c '\
  file_encoding="$(echo "System.out.println(System.getProperty(\"file.encoding\"))" | jshell -s -)"; \
  [ "${file_encoding}" = "UTF-8" ]; \
  javac --version; \
  java --version \
'

# Strip unnecessary JDK parts to reduce layer size
RUN rm -rf \
      /opt/java/openjdk/lib/src.zip \
      /opt/java/openjdk/demo \
      /opt/java/openjdk/man


FROM debian:bookworm-slim AS downloader

ARG GALAXIO_CLI_VERSION

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://github.com/galax-io/galaxio-cli/releases/download/v${GALAXIO_CLI_VERSION}/galaxio_${GALAXIO_CLI_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin galaxio && \
    chmod 0555 /usr/local/bin/galaxio && \
    /usr/local/bin/galaxio version


FROM debian:bookworm-slim

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/base-jdk"
LABEL org.opencontainers.image.description="Stripped Debian base with JDK and galaxio-cli. Foundation for all Gatling builder images."

ARG GALAXIO_CLI_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl && \
    rm -rf \
      /usr/share/doc \
      /usr/share/man \
      /usr/share/info \
      /usr/share/locale \
      /usr/share/i18n \
      /var/log/* \
      /tmp/*

COPY --from=downloader /usr/local/bin/galaxio /usr/local/bin/galaxio
COPY --from=jdk --link /opt/java/openjdk/ /opt/java/openjdk/

RUN groupadd --gid 65532 nonroot && \
    useradd --uid 65532 --gid 65532 --create-home --home-dir /home/nonroot --shell /usr/sbin/nologin nonroot

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/java/openjdk/bin:/usr/local/bin:/usr/bin:/bin \
    TZ=UTC

WORKDIR /home/nonroot
USER nonroot:nonroot

RUN java --version && javac --version && galaxio version
