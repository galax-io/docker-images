ARG GRADLE_VERSION=8.10.2
ARG JAVA_VERSION=21
ARG GATLING_VERSION=3.13.5

FROM gradle:${GRADLE_VERSION}-jdk${JAVA_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-gradle-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Gradle projects with warmed Gradle caches."

ARG GATLING_VERSION

ENV HOME=/home/gradle \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    GRADLE_USER_HOME=/home/gradle/.gradle \
    JAVA_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    USER=gradle

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
WORKDIR /home/gradle

USER gradle

RUN mkdir -p /home/gradle/project/src/gatling/java/computerdatabase && \
    mkdir -p /home/gradle/project/src/gatling/resources && \
    cat > /home/gradle/project/settings.gradle <<'EOF'
rootProject.name = 'gatling-gradle-builder-warmup'
EOF

RUN cat > /home/gradle/project/build.gradle <<EOF
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

RUN cat > /home/gradle/project/src/gatling/java/computerdatabase/BasicSimulation.java <<'EOF'
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
EOF

RUN cd /home/gradle/project && \
    gradle --no-daemon gatlingClasses && \
    rm -rf /home/gradle/project
