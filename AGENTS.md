# docker-images — Agent Guide

Docker image CI/CD repo for Galaxio Gatling load testing. Published to Docker Hub `galaxioteam/`.

Use Docker skills: `docker-syntax-dockerfile`, `docker-syntax-buildkit`, `docker-syntax-multistage`, `docker-impl-build-optimization`, `docker-impl-cicd`, `docker-errors-build`.

## Image Hierarchy

Every image `FROM` the previous. Never break this chain.

```
gcr.io/distroless/base-debian12:nonroot
└── galaxioteam/base             (Dockerfile)
    └── galaxioteam/base-jdk     (java.Dockerfile)              × java 17, 21
        ├── gatling-sbt-builder  → gatling-sbt-runtime  → gatling-sbt-debug
        ├── gatling-maven-builder→ gatling-maven-runtime→ gatling-maven-debug
        └── gatling-gradle-builder→gatling-gradle-runtime→gatling-gradle-debug
```

7 Dockerfiles → 21 image tags. Builders warm dependency caches (Coursier/.sbt, .m2, .gradle) so containers don't re-download at runtime.

## Conventions

- `# syntax=docker/dockerfile:1` at top of every Dockerfile
- `COPY --link` with `--chown=65532:65532` (numeric only — `--link` can't resolve named users)
- `RUN --mount=type=cache,target=/var/cache/apt,sharing=locked` for apt
- Warmup stage = `FROM` official tool image (`maven:`, `gradle:`, `sbtscala/`) — never `FROM debian:bookworm-slim` with JDK copied in
- nonroot uid/gid `65532` everywhere: `--chown`, `useradd`, `USER`
- Shell scripts: `set -euo pipefail`, shellcheck-clean
- Version bumps: update Dockerfile `ARG` defaults + `env:` blocks in both `build.yml` and `pull-request-build.yml`
- Builds go through `.github/scripts/buildkit-build.sh`, not `docker build`

## DO / DON'T

| ✓ Do | ❌ Don't |
|---|---|
| warmup FROM official tool image | `FROM base-jdk AS jdk-src` + COPY into warmup |
| `--chown=65532:65532` with `--link` | `--chown=nonroot:nonroot` with `--link` |
| PR = build only, no Docker Hub push | Push images from PR builds |
| Strip docs/man/locale in final stages | Leave JDK src.zip/demo/man in image |
| `shellcheck` + `hadolint` before commit | Commit unvalidated shell/Dockerfiles |

## PR Workflow

1. **Branch**: feature branch off `main`
2. **Pre-commit checks**: `shellcheck resources/*.sh`, `hadolint *.Dockerfile Dockerfile`
3. **Commits**: squash semantically — each commit must be green (CI passes). No red commits on `main`
4. **Merge strategy**: always **rebase + merge** (no merge commits)
5. **PR CI** (`pull-request-build.yml`): build-only, `BASE_VERSION=latest`, no Hub push
6. **Release CI** (`build.yml`): push to main or `v*` tag → pushes version + latest tags

## CI DAG

```
prepare-release → build-cli → build-jdk [17, 21] → build-chains [sbt, maven, gradle] × [17, 21]
                                                     each chain: builder → runtime → debug
```

`update-readme` job auto-updates image sizes in README after publish.
