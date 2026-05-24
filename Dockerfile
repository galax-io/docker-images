# syntax=docker/dockerfile:1
ARG GALAXIO_CLI_VERSION=0.6.1

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


FROM gcr.io/distroless/base-debian12:nonroot

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/galaxio-cli"
LABEL org.opencontainers.image.description="Distroless base with galaxio-cli."

ARG GALAXIO_CLI_VERSION

COPY --from=downloader /usr/local/bin/galaxio /usr/local/bin/galaxio

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

WORKDIR /home/nonroot
USER nonroot

RUN ["/usr/local/bin/galaxio", "version"]
