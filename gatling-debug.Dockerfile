ARG JAVA_VERSION=21
ARG GATLING_VERSION=3.13.5

FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-debug"
LABEL org.opencontainers.image.description="Debug-friendly Gatling 3.13 image with shell and network tooling."

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
    apt-get install -y --no-install-recommends ca-certificates curl git jq netcat-openbsd procps unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/gatling.zip \
      "https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/${GATLING_VERSION}/gatling-charts-highcharts-bundle-${GATLING_VERSION}.zip" && \
    unzip -q /tmp/gatling.zip -d /opt && \
    mv "/opt/gatling-charts-highcharts-bundle-${GATLING_VERSION}" "${GATLING_HOME}" && \
    rm -f /tmp/gatling.zip

RUN cd "${GATLING_HOME}" && \
    ./mvnw -q -DskipTests test-compile gatling:help && \
    find "${GATLING_HOME}/.m2" -name "*.lastUpdated" -type f -delete

RUN useradd --create-home --home-dir /home/gatling --shell /bin/bash --uid 10001 gatling && \
    chown -R gatling:gatling /opt/gatling /home/gatling

USER gatling
WORKDIR /opt/gatling

ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["./mvnw -o test gatling:test"]
