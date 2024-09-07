ARG JAVA_VERSION=21

FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy as fat

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"

FROM galaxioteam/base:master

COPY --from=fat /opt/java/openjdk/ /opt/java/openjdk/

# Env variables
ENV PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV JAVA_HOME=/opt/java/openjdk

RUN java --version

ARG JAVA_OPTS_COMMON="-Dconfig.override_with_env_vars=true -Dfile.encoding=UTF-8"