# docker-images

Production-oriented container images for the Galaxio team.

## Images

### `Dockerfile`

Minimal distroless base image:

- runs as `nonroot`
- no shell, package manager, or debugging tools
- intended as a safe parent for production images

Build:

```bash
docker build -f Dockerfile -t galaxioteam/base:local .
```

### `java.Dockerfile`

Hardened Java 21 JDK image on top of the distroless base:

- full JDK copied from Eclipse Temurin
- non-root by default
- UTF-8 defaults baked in

Build:

```bash
docker build -f java.Dockerfile -t galaxioteam/java:local .
```

### `gatling-sbt-builder.Dockerfile`

Builder image for Scala Gatling projects:

- based on `sbtscala/scala-sbt`
- warms `sbt` and Coursier caches
- installs `galaxio-cli`
- warms dependencies by rendering `gatling/scala-sbt` from the Galaxio template registry
- keeps `gatling-picatinny` in the generated warmup project
- keeps shell tooling because it is a CI/builder image, not a production runtime

Build:

```bash
docker build -f gatling-sbt-builder.Dockerfile -t galaxioteam/gatling-sbt-builder:local .
```

#### Build arguments

| Argument | Default | Description |
|---|---|---|
| `GALAXIO_CLI_VERSION` | `0.6.1` | Version of `galaxio-cli` to download. |
| `GALAXIO_CLI_CHECKSUM` | _(see Dockerfile)_ | SHA256 checksum of the `galaxio-cli` release tarball. Used to verify the download before extraction. |

**`GALAXIO_CLI_CHECKSUM`** — how to find and use it:

1. Open the release page for the target version:
   `https://github.com/galax-io/galaxio-cli/releases/tag/v<VERSION>`
2. Download `checksums.txt` from the release assets and locate the line for
   `galaxio_<VERSION>_linux_amd64.tar.gz`.
3. Pass the hash at build time:

```bash
docker build \
  --build-arg GALAXIO_CLI_VERSION=0.6.1 \
  --build-arg GALAXIO_CLI_CHECKSUM=711075adfa5bd7fc188326ee4200177cfd13d997082ecc27b304e405ae035fea \
  -f gatling-sbt-builder.Dockerfile \
  -t galaxioteam/gatling-sbt-builder:local .
```

If `GALAXIO_CLI_CHECKSUM` does not match the downloaded file, the build will
fail at the `sha256sum -c` step before any binary is extracted.

### `gatling-maven-builder.Dockerfile`

Builder image for Gatling Maven projects:

- based on official Maven + Temurin
- warms the local `.m2` repository with Gatling 3.13 dependencies
- intended for Java/Kotlin/Scala Maven projects

Build:

```bash
docker build -f gatling-maven-builder.Dockerfile -t galaxioteam/gatling-maven-builder:local .
```

### `gatling-gradle-builder.Dockerfile`

Builder image for Gatling Gradle projects:

- based on official Gradle + JDK 21
- warms the Gradle cache with Gatling 3.13 dependencies
- intended for Java/Kotlin/Scala Gradle projects

Build:

```bash
docker build -f gatling-gradle-builder.Dockerfile -t galaxioteam/gatling-gradle-builder:local .
```

### `gatling-runtime.Dockerfile`

Hardened Gatling 3.13 runtime image:

- distroless final image
- non-root user
- offline Maven cache warmed at build time
- tiny BusyBox userspace instead of a full Debian/Ubuntu userspace

Why not fully distroless-only?

Gatling `3.13.x` ships as a Maven-wrapper-based bundle. Running the official bundle requires a shell and a few POSIX utilities because `mvnw` is a shell script. The runtime image therefore uses:

- tiny BusyBox userspace instead of a full Debian/Ubuntu userspace

Build runtime:

```bash
docker build -f gatling-runtime.Dockerfile -t galaxioteam/gatling-runtime:local .
```

### `gatling-debug.Dockerfile`

Debug-friendly Gatling 3.13 image:

- shell, git, jq, curl, netcat, procps
- meant only for troubleshooting and ad-hoc inspection

Build:

```bash
docker build -f gatling-debug.Dockerfile -t galaxioteam/gatling-debug:local .
```

Run bundled sample simulation:

```bash
docker run --rm galaxioteam/gatling-runtime:local
```

Override the Maven/Gatling goal:

```bash
docker run --rm galaxioteam/gatling-runtime:local test gatling:test -Dgatling.simulationClass=computerdatabase.BasicSimulation
```

## Production guidance

For production and CI usage, prefer the following split:

1. Use `gatling-sbt-builder`, `gatling-maven-builder`, and `gatling-gradle-builder` only as builder images.
2. Use `gatling-runtime` as the smallest safe image when you need the official 3.13 bundle workflow.
3. Use `gatling-debug` only for troubleshooting.
4. Run containers with:
   - read-only root filesystem
   - dropped Linux capabilities
   - `allowPrivilegeEscalation=false`
   - `seccomp=RuntimeDefault`
5. Pin upstream base images by digest in CI/CD before publishing to production registries.

## Main improvements versus the previous setup

- removed `apt-get upgrade` from image builds
- stopped copying a near-complete Ubuntu userspace into a distroless image
- made the base image truly minimal
- made Java runtime images non-root by default
- split Gatling images by builder tool: `sbt`, `maven`, `gradle`
- separated production and debug concerns
- switched sbt warmup from `g8` to `galaxio-cli`
- updated Picatinny in sbt warmup to the latest verified version
- fixed `SBT_OPTS` handling in the sbt builder

Docker Hub: [galaxioteam](https://hub.docker.com/u/galaxioteam)


<!-- IMAGE-SIZES-START -->

| Image | Tag | Size |
|-------|-----|------|
| `galaxio-cli` | `0.3.6` | N/A |
| `base-jdk` | `17-0.3.6` | N/A |
| `base-jdk` | `21-0.3.6` | N/A |
| `gatling-sbt-builder` | `17-0.3.6` | N/A |
| `gatling-sbt-builder` | `21-0.3.6` | N/A |
| `gatling-maven-builder` | `17-0.3.6` | N/A |
| `gatling-maven-builder` | `21-0.3.6` | N/A |
| `gatling-gradle-builder` | `17-0.3.6` | N/A |
| `gatling-gradle-builder` | `21-0.3.6` | N/A |
| `gatling-sbt-runtime` | `17-0.3.6` | N/A |
| `gatling-sbt-runtime` | `21-0.3.6` | N/A |
| `gatling-maven-runtime` | `17-0.3.6` | N/A |
| `gatling-maven-runtime` | `21-0.3.6` | N/A |
| `gatling-gradle-runtime` | `17-0.3.6` | N/A |
| `gatling-gradle-runtime` | `21-0.3.6` | N/A |
| `gatling-sbt-debug` | `17-0.3.6` | N/A |
| `gatling-sbt-debug` | `21-0.3.6` | N/A |
| `gatling-maven-debug` | `17-0.3.6` | N/A |
| `gatling-maven-debug` | `21-0.3.6` | N/A |
| `gatling-gradle-debug` | `17-0.3.6` | N/A |
| `gatling-gradle-debug` | `21-0.3.6` | N/A |


<!-- IMAGE-SIZES-END -->
