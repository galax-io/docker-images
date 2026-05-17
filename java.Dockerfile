ARG JAVA_VERSION=21
ARG BASE_VERSION=master

FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy AS jdk

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

RUN bash -euxo pipefail -c '\
  file_encoding="$(echo "System.out.println(System.getProperty(\"file.encoding\"))" | jshell -s -)"; \
  [ "${file_encoding}" = "UTF-8" ]; \
  javac --version; \
  java --version \
'

FROM galaxioteam/base:${BASE_VERSION}

COPY --from=jdk /opt/java/openjdk/ /opt/java/openjdk/

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/java/openjdk/bin:/usr/local/bin:/usr/bin:/bin \
    TZ=UTC

WORKDIR /workspace
USER nonroot:nonroot
