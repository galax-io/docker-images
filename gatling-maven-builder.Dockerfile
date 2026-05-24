# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG MAVEN_VERSION=3.9.9
ARG GATLING_VERSION=3.13.5

FROM maven:${MAVEN_VERSION}-eclipse-temurin-${JAVA_VERSION} AS tool-src


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION} AS jdk-src


FROM debian:bookworm-slim AS warmup

ARG JAVA_VERSION
ARG MAVEN_VERSION
ARG GATLING_VERSION

ENV JAVA_HOME=/opt/java/openjdk \
    PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/gatling \
    MAVEN_CONFIG=/home/gatling/.m2 \
    MAVEN_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
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
COPY --from=tool-src --link /usr/share/maven/ /usr/share/maven/

RUN groupadd --gid 10001 gatling && \
    useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash gatling && \
    mkdir -p /home/gatling/.m2 && \
    chown -R gatling:gatling /home/gatling

USER gatling
WORKDIR /home/gatling

# Create warmup project
RUN mkdir -p project/src/test/java/computerdatabase && \
    mkdir -p project/src/test/resources && \
    cat > project/pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.galaxio</groupId>
  <artifactId>gatling-maven-builder-warmup</artifactId>
  <version>1.0.0</version>
  <properties>
    <maven.compiler.release>11</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <gatling.version>${GATLING_VERSION}</gatling.version>
    <gatling-maven-plugin.version>4.16.3</gatling-maven-plugin.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>io.gatling.highcharts</groupId>
      <artifactId>gatling-charts-highcharts</artifactId>
      <version>\${gatling.version}</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>io.gatling</groupId>
        <artifactId>gatling-maven-plugin</artifactId>
        <version>\${gatling-maven-plugin.version}</version>
      </plugin>
    </plugins>
  </build>
</project>
EOF

RUN cat > project/src/test/java/computerdatabase/BasicSimulation.java <<'JAVA'
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
    /usr/share/maven/bin/mvn -q -DskipTests test-compile gatling:help && \
    find /home/gatling/.m2 -name "*.lastUpdated" -type f -delete && \
    rm -rf /home/gatling/project


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-maven-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Maven projects with warmed local repository."

COPY --from=tool-src --link /usr/share/maven/ /usr/share/maven/
COPY --from=warmup --link --chown=nonroot:nonroot /home/gatling/.m2/ /home/nonroot/.m2/

ENV HOME=/home/nonroot \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    MAVEN_HOME=/usr/share/maven \
    MAVEN_CONFIG=/home/nonroot/.m2 \
    MAVEN_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    PATH=/opt/java/openjdk/bin:/usr/share/maven/bin:/usr/local/bin:/usr/bin:/bin

WORKDIR /home/nonroot
USER nonroot:nonroot

RUN mvn --version && galaxio version
