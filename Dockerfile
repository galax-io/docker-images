# syntax=docker/dockerfile:1
ARG GALAXIO_CLI_VERSION=0.6.1

FROM debian:bookworm-slim AS tools

ARG GALAXIO_CLI_VERSION

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://github.com/galax-io/galaxio-cli/releases/download/v${GALAXIO_CLI_VERSION}/galaxio_${GALAXIO_CLI_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin galaxio && \
    chmod 0555 /usr/local/bin/galaxio && \
    galaxio version


FROM debian:bookworm-slim

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/galaxio-cli"
LABEL org.opencontainers.image.description="Minimal stripped Debian base with bash, curl, ca-certificates, and galaxio-cli."

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

COPY --from=tools --link /usr/local/bin/galaxio /usr/local/bin/galaxio

RUN groupadd --gid 65532 nonroot && \
    useradd --uid 65532 --gid 65532 --no-create-home --shell /usr/sbin/nologin nonroot

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

WORKDIR /workspace
USER nonroot:nonroot

RUN galaxio version
