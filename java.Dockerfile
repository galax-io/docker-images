# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest

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


# Collect bash + libtinfo for distroless base
FROM debian:bookworm-slim AS bash-src

RUN mkdir -p /bash-root/usr/bin /bash-root/usr/lib/x86_64-linux-gnu && \
    cp -L /usr/bin/bash /bash-root/usr/bin/bash && \
    ln -sf bash /bash-root/usr/bin/sh && \
    cp -L /usr/lib/x86_64-linux-gnu/libtinfo.so.6 /bash-root/usr/lib/x86_64-linux-gnu/libtinfo.so.6


FROM galaxioteam/galaxio-cli:${BASE_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/base-jdk"
LABEL org.opencontainers.image.description="Galaxio CLI base with JDK and bash. Foundation for all Gatling builder images."

# Add bash (required by downstream build tool scripts: sbt, mvn, gradle)
COPY --from=bash-src /bash-root/ /

# Add JDK
COPY --from=jdk --link /opt/java/openjdk/ /opt/java/openjdk/

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/java/openjdk/bin:/usr/local/bin:/usr/bin:/bin \
    TZ=UTC

WORKDIR /home/nonroot
USER nonroot:nonroot

RUN java --version && javac --version && galaxio version
