# syntax=docker/dockerfile:1
# Parameterized runtime image built from a builder image.
# Pass BUILDER_IMAGE and BUILDER_TOOL to customize per build tool chain.
#
# Build examples:
#   docker build --build-arg BUILDER_IMAGE=galaxioteam/gatling-sbt-builder --build-arg BUILDER_TOOL=sbt -f gatling-runtime.Dockerfile .
#   docker build --build-arg BUILDER_IMAGE=galaxioteam/gatling-maven-builder --build-arg BUILDER_TOOL=maven -f gatling-runtime.Dockerfile .
#   docker build --build-arg BUILDER_IMAGE=galaxioteam/gatling-gradle-builder --build-arg BUILDER_TOOL=gradle -f gatling-runtime.Dockerfile .

ARG BUILDER_IMAGE=galaxioteam/gatling-sbt-builder
ARG BUILDER_TOOL=sbt
ARG BUILDER_VERSION=latest

FROM ${BUILDER_IMAGE}:${BUILDER_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.description="Gatling runtime image. Inherits warmed build tool caches from builder."

ARG BUILDER_TOOL

ENV BUILDER_TOOL=${BUILDER_TOOL}

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["echo \"Run: docker run <image> -c '<build-tool> gatling:test'\""]
