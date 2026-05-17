ARG MAVEN_VERSION=3.9.9
ARG JAVA_VERSION=21
ARG GATLING_VERSION=3.11.5

FROM maven:${MAVEN_VERSION}-eclipse-temurin-${JAVA_VERSION}

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"
LABEL org.opencontainers.image.title="galaxioteam/gatling-maven-builder"
LABEL org.opencontainers.image.description="Builder image for Gatling Maven projects with warmed local repository."

ARG GATLING_VERSION

ENV HOME=/home/gatling \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    MAVEN_CONFIG=/home/gatling/.m2 \
    MAVEN_OPTS="-Djava.awt.headless=true -Dfile.encoding=UTF-8" \
    USER=gatling

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
WORKDIR /home/gatling

RUN useradd --create-home --home-dir /home/gatling --shell /bin/bash --uid 10001 gatling

RUN mkdir -p /home/gatling/project && \
    chown -R gatling:gatling /home/gatling

USER gatling

RUN mkdir -p /home/gatling/project/src/test/java/computerdatabase && \
    mkdir -p /home/gatling/project/src/test/resources && \
    cat > /home/gatling/project/pom.xml <<EOF
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
    <gatling-maven-plugin.version>4.9.5</gatling-maven-plugin.version>
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

RUN cat > /home/gatling/project/src/test/java/computerdatabase/BasicSimulation.java <<'EOF'
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

RUN cd /home/gatling/project && \
    mvn -q -DskipTests test-compile gatling:help && \
    find /home/gatling/.m2 -name "*.lastUpdated" -type f -delete && \
    rm -rf /home/gatling/project
