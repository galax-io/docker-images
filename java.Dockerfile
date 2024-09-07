ARG JAVA_VERSION=21
ARG BASE_VERSION=master

FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy as fat

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"

FROM galaxioteam/base:${BASE_VERSION}

COPY --from=fat /opt/java/openjdk/ /opt/java/openjdk/

# Env variables
ENV PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV JAVA_HOME=/opt/java/openjdk

RUN /bin/sh -c set -eux; echo "Verifying install ..."; fileEncoding="$(echo 'System.out.println(System.getProperty("file.encoding"))' | jshell -s -)"; [ "$fileEncoding" = 'UTF-8' ]; rm -rf ~/.java; echo "javac --version"; javac --version; echo "java --version"; java --version; echo "Complete."

ARG JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8"
