# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG GRADLE_VERSION=8.10.2
ARG GATLING_VERSION=3.13.5

FROM gradle:${GRADLE_VERSION}-jdk${JAVA_VERSION} AS tool-src


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION} AS jdk-src


FROM debian:bookworm-slim AS warmup

ARG JAVA_VERSION
ARG GRADLE_VERSION
ARG GATLING_VERSION

ENV JAVA_HOME=/opt/java/openjdk \
    PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/gradle \
    GRADLE_USER_HOME=/home/gradle/.gradle \
    GRADLE_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl

COPY --from=jdk-src --link /opt/java/openjdk/ /opt/java/openjdk/
COPY --from=tool-src --link /opt/gradle/ /opt/gradle/

RUN groupadd --gid 10001 gradle && \
    useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash gradle && \
    mkdir -p /home/gradle/.gradle && \
    chown -R gradle:gradle /home/gradle

USER gradle
WORKDIR /home/gradle

# Create warmup project
RUN mkdir -p project/src/gatling/java/computerdatabase && \
    mkdir -p project/src/gatling/resources && \
    cat > project/settings.gradle <<'EOF'
rootProject.name = 'gatling-gradle-builder-warmup'
EOF

RUN cat > project/build.gradle <<EOF
plugins {
  id 'java'
  id 'io.gatling.gradle' version '3.13.5.4'
}

repositories {
  mavenCentral()
}

dependencies {
  gatling "io.gatling.highcharts:gatling-charts-highcharts:${GATLING_VERSION}"
}
EOF

RUN cat > project/src/gatling/java/computerdatabase/BasicSimulation.java <<'JAVA'
package computerdatabase;

import static io.gatling.javaapi.core.CoreDsl.atOnceUsers;
import static io.gatling.javaapi.core.CoreDsl.scenario;
import static io.gatling.javaapi.http.HttpDsl.http;
import static io.gatling.javaapi.http.HttpDsl.status;

import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;
import io.gatling.javaapi.http.HttpProtocolBuilder;

public class BasicSimulation extends Simulation {
  HttpProtocolBuilder httpProtocol =
      http.baseUrl("https://computer-database.gatling.io")
          .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");

  ScenarioBuilder scn =
      scenario("basic")
          .exec(http("home").get("/").check(status().is(200)));

  {
    setUp(scn.injectOpen(atOnceUsers(1))).protocols(httpProtocol);
  }
}
JAVA

RUN cd project && \
    /opt/gradle/bin/gradle --no-daemon gatlingClasses && \
    rm -rf /home/gradle/project /home/gradle/.gradle/daemon


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-gradle-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Gradle projects with warmed Gradle caches."

COPY --from=tool-src --link /opt/gradle/ /opt/gradle/
COPY --from=warmup --link --chown=nonroot:nonroot /home/gradle/.gradle/ /home/nonroot/.gradle/

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    GRADLE_HOME=/opt/gradle \
    GRADLE_USER_HOME=/home/nonroot/.gradle \
    GRADLE_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    PATH=/opt/java/openjdk/bin:/opt/gradle/bin:/usr/local/bin:/usr/bin:/bin

WORKDIR /home/nonroot
USER nonroot:nonroot

RUN gradle --version && galaxio version
