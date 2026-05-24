# syntax=docker/dockerfile:1
ARG JAVA_VERSION=21
ARG BASE_VERSION=latest
ARG MAVEN_VERSION=3.9.9
ARG GATLING_VERSION=3.13.5

# Warmup: official maven image (has JDK + maven + bash)
# Runs as root — Maven cache lands in /root/.m2
FROM maven:${MAVEN_VERSION}-eclipse-temurin-${JAVA_VERSION} AS warmup

ARG JAVA_VERSION
ARG GATLING_VERSION

ENV MAVEN_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

WORKDIR /root

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
    mvn -q -DskipTests test-compile gatling:help && \
    cd .. && rm -rf project && \
    find /root/.m2 -name "*.lastUpdated" -type f -delete


FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-maven-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Maven projects with warmed local repository."

# Maven binaries from warmup stage
COPY --from=warmup --link /usr/share/maven/ /usr/share/maven/

# Warmed local repository
COPY --from=warmup --link --chown=65532:65532 /root/.m2/ /home/nonroot/.m2/

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
