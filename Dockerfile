ARG DISTROLESS_BASE_IMAGE=gcr.io/distroless/base-debian12:nonroot

FROM ${DISTROLESS_BASE_IMAGE}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/base"
LABEL org.opencontainers.image.description="Minimal non-root distroless base image for production containers."

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

WORKDIR /workspace
USER nonroot:nonroot
