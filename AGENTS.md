# docker-images — Agent Guide

Agent-facing reference for the `galax-io/docker-images` repository.
Galaxio team CI/CD container images for Gatling load testing, published to Docker Hub under `galaxioteam/`.

---

## Image Hierarchy

Every image inherits from the previous one. Never break this chain.

```
gcr.io/distroless/base-debian12:nonroot
└── galaxioteam/base             (Dockerfile)
    └── galaxioteam/base-jdk     (java.Dockerfile)          × java 17, 21
        ├── galaxioteam/gatling-sbt-builder                 × java 17, 21
        │   └── galaxioteam/gatling-sbt-runtime             × java 17, 21
        │       └── galaxioteam/gatling-sbt-debug           × java 17, 21
        ├── galaxioteam/gatling-maven-builder               × java 17, 21
        │   └── galaxioteam/gatling-maven-runtime           × java 17, 21
        │       └── galaxioteam/gatling-maven-debug         × java 17, 21
        └── galaxioteam/gatling-gradle-builder              × java 17, 21
            └── galaxioteam/gatling-gradle-runtime          × java 17, 21
                └── galaxioteam/gatling-gradle-debug        × java 17, 21
```

**7 Dockerfiles → 21 image tags** (base×1, base-jdk×2, each tool×3 images×2 java versions).

---

## File Map

| Dockerfile | Image | What it adds |
|---|---|---|
| `Dockerfile` | `galaxioteam/base` | Labels, env, nonroot user on distroless |
| `java.Dockerfile` | `galaxioteam/base-jdk` | JDK from Eclipse Temurin (17 or 21) |
| `gatling-sbt-builder.Dockerfile` | `galaxioteam/gatling-sbt-builder` | sbt, scala, warmed Coursier/.sbt caches |
| `gatling-maven-builder.Dockerfile` | `galaxioteam/gatling-maven-builder` | maven, warmed .m2 cache |
| `gatling-gradle-builder.Dockerfile` | `galaxioteam/gatling-gradle-builder` | gradle, warmed .gradle cache |
| `gatling-runtime.Dockerfile` | `galaxioteam/gatling-{tool}-runtime` | Gatling entrypoint, 3 tool variants |
| `gatling-debug.Dockerfile` | `galaxioteam/gatling-{tool}-debug` | + curl/git/jq/nc/procps, 3 tool variants |

Supporting files:
- `.github/scripts/buildkit-build.sh` — all builds go through this script, not `docker build`
- `.github/workflows/build.yml` — release CI (push to main / `v*` tag)
- `.github/workflows/pull-request-build.yml` — PR validation CI (build only, no push)
- `.github/workflows/pr-cleanup.yml` — cleanup on PR close
- `resources/sbt-warmup.sh` — sbt cache warmup script (called inside builder Dockerfile)
- `resources/.sbtopts` — sbt options for warmup stage
- `tests/test_buildkit_build.sh` — unit tests for buildkit-build.sh script

---

## Warmup Pattern

**Why warmup exists**: baking dependency caches into image layers means no network calls at runtime. Without warmup, each container start downloads hundreds of MB from Maven Central.

**Pattern** (maven/gradle): warmup stage FROM the official tool image (which already has JDK + tool + bash). Create inline project via heredoc, run compile, copy only the cache dir to final stage.

```dockerfile
FROM maven:${MAVEN_VERSION}-eclipse-temurin-${JAVA_VERSION} AS warmup
# Create inline pom.xml, run mvn to populate /root/.m2

FROM galaxioteam/base-jdk:${JAVA_VERSION}-${BASE_VERSION}
COPY --from=warmup --link /usr/share/maven/ /usr/share/maven/
COPY --from=warmup --link --chown=65532:65532 /root/.m2/ /home/nonroot/.m2/
```

**Pattern** (sbt): warmup FROM `sbtscala/scala-sbt:...`, create inline build.sbt + plugins.sbt + simulation class, run `sbt "Gatling / compile"`.

### Anti-patterns

| ❌ Wrong | ✓ Correct | Why |
|---|---|---|
| `FROM base-jdk AS jdk-src` + COPY into warmup | warmup FROM official tool image directly | Kills layer sharing; `jdk-src` is pointless indirection |
| `FROM debian:bookworm-slim AS warmup` + separate JDK copy | warmup FROM `maven:`/`gradle:`/`sbtscala/` | debian warmup lacks `uname`/`dirname`; tool scripts fail |
| `COPY --link --chown=nonroot:nonroot` | `COPY --link --chown=65532:65532` | `--link` uses independent layers; can't resolve named users |

---

## Version Locations

When bumping any version: update the Dockerfile `ARG` default **and** both workflow `env:` blocks.

| Variable | Dockerfile | `build.yml` | `pull-request-build.yml` |
|---|---|---|---|
| `GALAXIO_CLI_VERSION` | `java.Dockerfile` | `env:` | `env:` |
| `GATLING_VERSION` | all 3 builder Dockerfiles | `env:` | `env:` |
| `PICATINNY_VERSION` | `gatling-sbt-builder.Dockerfile` | `env:` | `env:` |
| `SBT_VERSION` | `gatling-sbt-builder.Dockerfile` | `env:` | `env:` |
| `GATLING_SBT_VERSION` | `gatling-sbt-builder.Dockerfile` | `env:` | `env:` |
| `MAVEN_VERSION` | `gatling-maven-builder.Dockerfile` | `env:` | `env:` |
| `GRADLE_VERSION` | `gatling-gradle-builder.Dockerfile` | `env:` | `env:` |

---

## BuildKit Conventions

- `# syntax=docker/dockerfile:1` — **required** at top of every Dockerfile
- `COPY --link` — parallel layer extraction; requires `--chown=65532:65532` (numeric, not named)
- `RUN --mount=type=cache,target=/var/cache/apt,sharing=locked` — apt cache in build stages
- All builds via `.github/scripts/buildkit-build.sh` (sets up buildkitd, handles cache import/export)

---

## CI/CD Strategy

### PR builds (`pull-request-build.yml`)
- **Build only — no Docker Hub push**
- Each stage uses `BASE_VERSION=latest` (pulls from already-published `galaxioteam/*:latest`)
- Validates Dockerfile correctness and build success against existing published base images

### Release builds (`build.yml`)
- Triggered on push to `main` or `v*` tag
- Tags pushed: version (`21-1.2.3`) **and** latest (`21-latest`) together
- Job DAG:
  ```
  prepare-release
  └── build-cli
      └── build-jdk  (matrix: [17, 21])
          └── build-chains  (matrix: [sbt, maven, gradle] × [17, 21])
              sequential: builder → runtime → debug
  ```
- Final `update-readme` job runs automatically after all images publish: queries image sizes,
  updates README between `<!-- IMAGE-SIZES-START -->` / `<!-- IMAGE-SIZES-END -->` markers, commits.

---

## Critical Rules

**DO:**
- Keep `FROM` chain intact — every final stage FROM the published previous image
- Use warmup FROM the official tool image (already has JDK + tool + bash)
- Use numeric UID `65532:65532` everywhere: `--chown`, `useradd`, `USER` directive
- Strip docs/man/locale at end of each stage to keep images slim
- Run `shellcheck resources/sbt-warmup.sh` before pushing `.sh` changes

**DON'T:**
- Add `FROM base-jdk AS jdk-src` — anti-pattern (see Warmup Pattern section)
- Push anything to Docker Hub from PR builds
- Use `--chown=nonroot:nonroot` with `COPY --link` (fails; independent layers can't resolve named users)
- Call `docker build` directly — use `.github/scripts/buildkit-build.sh`
- Modify `WORKDIR /home/nonroot` without checking all downstream `COPY` targets

---

## Local Build & Test

Build in hierarchy order (each needs previous published or locally-tagged image):

```bash
# Base images
docker build -f Dockerfile -t galaxioteam/base:local .
docker build -f java.Dockerfile \
  --build-arg BASE_VERSION=local \
  --build-arg JAVA_VERSION=21 \
  -t galaxioteam/base-jdk:21-local .

# Builder (example: sbt, java 21)
docker build -f gatling-sbt-builder.Dockerfile \
  --build-arg BASE_VERSION=local \
  --build-arg JAVA_VERSION=21 \
  -t galaxioteam/gatling-sbt-builder:21-local .

# Quick verification
docker run --rm galaxioteam/base-jdk:21-local java --version
docker run --rm galaxioteam/gatling-sbt-builder:21-local \
  bash -c "sbt --version && scala --version && galaxio version"
docker run --rm galaxioteam/gatling-maven-builder:21-local \
  bash -c "mvn --version && galaxio version"

# Script tests
bash tests/test_buildkit_build.sh
shellcheck resources/sbt-warmup.sh
```

---

## Repo Conventions

- Image tags: `{java_version}-{release_version}` (e.g. `21-0.6.1`) + `{java_version}-latest`
- `nonroot` user: uid/gid `65532` — defined in distroless base, inherited downstream
- All shell scripts: `set -euo pipefail`, shellcheck-clean
- Build args in Dockerfiles have defaults matching `build.yml` env block
- `AGENTS.md` is tracked in git and kept current with architecture changes
