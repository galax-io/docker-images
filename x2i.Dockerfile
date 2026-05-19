ARG GO_VERSION=1.22.12
ARG X2I_VERSION=x2i-1.0.0

FROM golang:${GO_VERSION}-bookworm AS builder

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"

ARG X2I_VERSION

ENV CGO_ENABLED=0 \
    GO111MODULE=on

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
WORKDIR /src

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${X2I_VERSION}" https://github.com/perfana/x2i.git /src/x2i

WORKDIR /src/x2i

RUN GOOS=linux GOARCH="$(go env GOARCH)" go build -trimpath -ldflags="-s -w" -o /out/x2i .

FROM gcr.io/distroless/base-debian12:nonroot

ARG X2I_VERSION

LABEL org.opencontainers.image.title="galaxioteam/x2i"
LABEL org.opencontainers.image.description="Minimal x2i runtime image for exporting Gatling, JMeter, or K6 logs directly to InfluxDB."
LABEL org.opencontainers.image.source="https://github.com/galax-io/docker-images"
LABEL org.opencontainers.image.version="${X2I_VERSION}"

COPY --from=builder --chown=nonroot:nonroot /out/x2i /usr/local/bin/x2i

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

WORKDIR /home/nonroot
USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/x2i"]
CMD ["--help"]
