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

# Collect binaries and their shared library dependencies
RUN mkdir -p /debug-root/usr/bin /debug-root/usr/lib /debug-root/lib/x86_64-linux-gnu && \
    for bin in curl git jq nc ps; do \
      bin_path="$(command -v "${bin}" || command -v "nc")" && \
      cp -L "${bin_path}" /debug-root/usr/bin/"${bin}" && \
      ldd "${bin_path}" 2>/dev/null | awk '/=>/{print $3}' | while read -r lib; do \
        [ -f "${lib}" ] && cp -L "${lib}" /debug-root/usr/lib/ || true; \
      done; \
    done && \
    # Copy git and its support programs
    cp -rL /usr/lib/git-core/ /debug-root/usr/lib/git-core/ && \
    cp -rL /usr/share/git-core/ /debug-root/usr/share/ || true && \
    # Copy common shared libs
    cp -L /lib/x86_64-linux-gnu/libz.so.1 /debug-root/lib/x86_64-linux-gnu/ || true && \
    cp -L /usr/lib/x86_64-linux-gnu/libcurl.so.4 /debug-root/usr/lib/ || true && \
    cp -L /usr/lib/x86_64-linux-gnu/libssl.so.3 /debug-root/usr/lib/ || true && \
    cp -L /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /debug-root/usr/lib/ || true && \
    cp -L /usr/lib/x86_64-linux-gnu/libnghttp2.so.14 /debug-root/usr/lib/ || true && \
    cp -L /usr/lib/x86_64-linux-gnu/libidn2.so.0 /debug-root/usr/lib/ || true


FROM ${RUNTIME_IMAGE}:${RUNTIME_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.description="Gatling debug image. Adds curl, git, jq, netcat, procps for troubleshooting."

USER root

COPY --from=debug-tools --link /debug-root/usr/bin/ /usr/bin/
COPY --from=debug-tools --link /debug-root/usr/lib/ /usr/lib/
COPY --from=debug-tools --link /debug-root/lib/ /lib/

RUN ln -sf /usr/bin/nc /usr/bin/netcat || true

USER nonroot:nonroot

RUN curl --version && git --version && jq --version && galaxio version
