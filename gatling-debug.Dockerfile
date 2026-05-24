# syntax=docker/dockerfile:1
# Parameterized debug image built from a runtime image.
# Adds curl, git, jq, netcat, procps for troubleshooting.
#
# Build examples:
#   docker build --build-arg RUNTIME_IMAGE=galaxioteam/gatling-sbt-runtime -f gatling-debug.Dockerfile .
#   docker build --build-arg RUNTIME_IMAGE=galaxioteam/gatling-maven-runtime -f gatling-debug.Dockerfile .
#   docker build --build-arg RUNTIME_IMAGE=galaxioteam/gatling-gradle-runtime -f gatling-debug.Dockerfile .

ARG RUNTIME_IMAGE=galaxioteam/gatling-sbt-runtime
ARG RUNTIME_VERSION=latest


FROM debian:bookworm-slim AS debug-tools

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      git \
      jq \
      netcat-openbsd \
      procps

# Collect binaries and their shared library dependencies.
# Everything under /debug-root/usr/ — avoids conflict with /lib -> usr/lib symlink in target image.
RUN mkdir -p /debug-root/usr/bin /debug-root/usr/lib/x86_64-linux-gnu && \
    cp -L /usr/bin/curl /debug-root/usr/bin/curl && \
    cp -L /usr/bin/git  /debug-root/usr/bin/git  && \
    cp -L /usr/bin/jq   /debug-root/usr/bin/jq   && \
    cp -L /usr/bin/nc   /debug-root/usr/bin/nc   && \
    ln -sf nc /debug-root/usr/bin/netcat          && \
    cp -L /usr/bin/ps   /debug-root/usr/bin/ps   && \
    cp -rL /usr/lib/git-core/ /debug-root/usr/lib/git-core/ && \
    cp -rL /usr/share/git-core/ /debug-root/usr/share/ || true && \
    for bin in /debug-root/usr/bin/curl /debug-root/usr/bin/jq \
               /debug-root/usr/bin/nc   /debug-root/usr/bin/ps \
               /debug-root/usr/bin/git; do \
      ldd "${bin}" 2>/dev/null \
        | awk '/=>[[:space:]]\// { print $3 }' \
        | while read -r lib; do \
            [ -f "${lib}" ] && \
              cp -L "${lib}" /debug-root/usr/lib/x86_64-linux-gnu/ 2>/dev/null || true; \
          done; \
    done


FROM ${RUNTIME_IMAGE}:${RUNTIME_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.description="Gatling debug image. Adds curl, git, jq, netcat, procps for troubleshooting."

USER root

COPY --from=debug-tools --link /debug-root/usr/bin/ /usr/bin/
COPY --from=debug-tools --link /debug-root/usr/lib/ /usr/lib/

USER nonroot:nonroot

RUN curl --version && git --version && jq --version && galaxio version
