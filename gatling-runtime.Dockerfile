ARG JAVA_VERSION=21
ARG GATLING_VERSION=3.11.5

FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy AS bundle

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"

ARG GATLING_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    GATLING_HOME=/opt/gatling \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MAVEN_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    TZ=UTC

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
WORKDIR /opt

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/gatling.zip \
      "https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/${GATLING_VERSION}/gatling-charts-highcharts-bundle-${GATLING_VERSION}.zip" && \
    unzip -q /tmp/gatling.zip -d /opt && \
    mv "/opt/gatling-charts-highcharts-bundle-${GATLING_VERSION}" "${GATLING_HOME}" && \
    rm -f /tmp/gatling.zip

RUN cd "${GATLING_HOME}" && \
    ./mvnw -q -DskipTests test-compile gatling:help && \
    find "${GATLING_HOME}/.m2" -name "*.lastUpdated" -type f -delete

RUN cat > /usr/local/bin/gatling-entrypoint.sh <<'EOF'
#!/bin/sh
set -eu

cd "${GATLING_HOME}"
exec /bin/sh "${GATLING_HOME}/mvnw" -o "$@"
EOF

RUN chmod 0555 /usr/local/bin/gatling-entrypoint.sh && \
    chmod -R go-w "${GATLING_HOME}" /usr/local/bin/gatling-entrypoint.sh

FROM busybox:1.36.1-musl AS busybox

RUN mkdir -p /busybox-root/bin && \
    cp /bin/busybox /busybox-root/bin/busybox && \
    for app in ash basename cat chmod cp dirname env expr ls mkdir mv pwd readlink rm sh sleep test touch tr true uname which; do \
      ln -s /bin/busybox "/busybox-root/bin/${app}"; \
    done

FROM gcr.io/distroless/cc-debian12:nonroot

LABEL org.opencontainers.image.title="galaxioteam/gatling-runtime"
LABEL org.opencontainers.image.description="Hardened Gatling 3.11 runtime image with offline Maven wrapper and minimal BusyBox userspace."

COPY --from=busybox /busybox-root/bin/ /bin/
COPY --from=bundle --chown=nonroot:nonroot /opt/java/openjdk/ /opt/java/openjdk/
COPY --from=bundle --chown=nonroot:nonroot /opt/gatling/ /opt/gatling/
COPY --from=bundle --chown=nonroot:nonroot /usr/local/bin/gatling-entrypoint.sh /usr/local/bin/gatling-entrypoint.sh

ENV GATLING_HOME=/opt/gatling \
    HOME=/home/nonroot \
    JAVA_HOME=/opt/java/openjdk \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MAVEN_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    PATH=/opt/java/openjdk/bin:/usr/local/bin:/bin \
    TZ=UTC

WORKDIR /opt/gatling
USER nonroot:nonroot

ENTRYPOINT ["/bin/sh", "/usr/local/bin/gatling-entrypoint.sh"]
CMD ["test", "gatling:test"]
