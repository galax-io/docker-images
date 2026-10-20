<!--
Sync Impact Report
- Version change: (template) -> 1.0.0
- Bump: MAJOR, first ratified constitution of docker-images.
- Sections: Precedence; Core Principles (I. The image chain is the contract,
  II. Non-root UID 65532 in every image, III. Pinned and verified inputs, versions in one step,
  IV. Lean multi-stage builds through BuildKit, V. Warmed caches are the product,
  VI. Published tags are never overwritten, VII. Deterministic gates before merge);
  Public Contracts and Dependencies; Security and Secrets;
  Development Workflow and Quality Gates; Governance.
- Templates checked: .specify/templates/plan-template.md (Constitution Check reads the principles
  below; no change needed), .specify/templates/spec-template.md, .specify/templates/tasks-template.md
  (no change needed; the kit is owned by spec-kit-galaxio-bootstrap and is not edited here).
- Known deviations, to be removed by backlog work, not by this document: pull request builds push
  `<java>-<sha>` tags and `-pr` cache refs to Docker Hub (Principle VI; galax-io/galaxio-sdlc-backlog#291);
  Dockerfile chain arguments default to `latest` (Principle III); `AGENTS.md` ("Image Hierarchy") names
  `galaxioteam/galaxio` as the root of the chain, `java.Dockerfile` starts from `debian:bookworm-slim`
  (Principle I).
- Follow-up: none.
-->

# docker-images Constitution

## Precedence

When two sources disagree, the higher one wins:

1. The maintainer's direct instruction.
2. The ecosystem constitution: `galax-io/galaxio-sdlc-backlog`, `.specify/memory/constitution.md`.
3. This constitution.
4. This repository's `AGENTS.md` (the working guide: commands, structure, conventions).

This constitution may tighten the ecosystem principles and add its own; it never contradicts them.

## Core Principles

### I. The image chain is the contract

- Every image MUST be built `FROM` its parent in the chain `base-jdk` -> `gatling-<tool>-builder`
  -> `gatling-<tool>-runtime` -> `gatling-<tool>-debug`, for `<tool>` in `sbt`, `maven`, `gradle`,
  as drawn in `AGENTS.md` ("Image Hierarchy"). The parent is chosen by the build arguments
  `BASE_VERSION`, `BUILDER_IMAGE`/`BUILDER_VERSION` and `RUNTIME_IMAGE`/`RUNTIME_VERSION`.
- A change MUST NOT skip a link, rename an image under `galaxioteam/`, or drop a tool or a Java line
  of the CI matrix (`java-version: ['17', '21']`, `tool: ['sbt', 'maven', 'gradle']` in
  `.github/workflows/build.yml` and `pull-request-build.yml`) without a deliberate, announced
  breaking change (Principle VI).
- The root of the chain is `java.Dockerfile`, built `FROM debian:bookworm-slim`; `galaxioteam/galaxio`
  is not a base of the images that run tests.
- One Dockerfile per role: `java.Dockerfile`, `gatling-{sbt,maven,gradle}-builder.Dockerfile`,
  `gatling-runtime.Dockerfile` and `gatling-debug.Dockerfile`; runtime and debug stay parameterized
  over the builder, not copied per tool.

Rationale: downstream users and CI pull images by name and tag; each layer relies on what its parent
installed (the JDK, `galaxio`, the build tool, the warmed caches).

### II. Non-root UID 65532 in every image

- The final stage of every image MUST end with `USER nonroot:nonroot`, where `nonroot` is UID/GID
  `65532`, created once in `java.Dockerfile`.
- `COPY --link` MUST use the numeric `--chown=65532:65532`; a named user with `--link` MUST NOT be used.
- A stage MAY switch to `USER root` only to install files and MUST switch back in the same stage
  (as `gatling-debug.Dockerfile` does).

Rationale: `tests/test_runtime_smoke.sh` and `tests/test_integration.sh` assert UID `65532`; the README
tells users to run with dropped capabilities and no privilege escalation.

### III. Pinned and verified inputs, versions in one step

- Every binary fetched over the network during a build or a CI job MUST be checked against a SHA-256
  before use: `galaxio-cli` with `GALAXIO_CLI_CHECKSUM` and `sha256sum -c` (`java.Dockerfile`,
  `gatling-sbt-builder.Dockerfile`), BuildKit with `BUILDKIT_CHECKSUM` in both build workflows.
  Bumping a version MUST bump its checksum in the same change.
- Tool versions (`GATLING_VERSION`, `GATLING_SBT_VERSION`, `SBT_VERSION`, `PICATINNY_VERSION`,
  `GALAXIO_CLI_VERSION`, `MAVEN_VERSION`, `GRADLE_VERSION`) MUST change together in the Dockerfile
  `ARG` defaults and the `env:` blocks of both `build.yml` and `pull-request-build.yml`; a version
  present in only some of these places is a violation.
- Upstream base images MUST be named with an explicit version tag. `latest` MUST NOT be used as a
  parent at all, neither for an external image nor in this repository's own chain: a chain argument
  (`BASE_VERSION`, `BUILDER_VERSION`, `RUNTIME_VERSION`) has no default of `latest`, and a build
  without an explicit version fails. Defaults of `latest` that exist today are a deviation to remove.

Rationale: a silent upstream change or a half-applied bump produces images that differ between PR
and release builds.

### IV. Lean multi-stage builds through BuildKit

- Every Dockerfile MUST start with `# syntax=docker/dockerfile:1`.
- A warmup stage MUST be `FROM` the official tool image (`maven:`, `gradle:`, `sbtscala/scala-sbt`);
  it MUST NOT be assembled from `debian:bookworm-slim` with a JDK copied in.
- The final stage MUST copy only the artifacts it needs (`COPY --from=...`); JDK `src.zip`, `demo`,
  `man`, and `/usr/share/{doc,man,info,locale}` stay out of final images.
- apt in a build MUST use `RUN --mount=type=cache,target=/var/cache/apt,sharing=locked`.
- CI images MUST be built through `.github/scripts/buildkit-build.sh` (registry cache in
  `galaxioteam/buildkit-cache`), not `docker build`.

Rationale: the size and attack surface of the published images are the point of this repository.

### V. Warmed caches are the product

- Each builder MUST resolve and compile a Gatling project at build time so its cache (`~/.sbt` and
  Coursier, `~/.m2`, `~/.gradle`) lands in `/home/nonroot`, owned by `65532`.
- The sbt builder MUST warm through `galaxio template init gatling/scala-sbt`
  (`resources/sbt-warmup.sh`) with the Kafka, JDBC and AMQP plugins and Picatinny enabled, so the
  cache matches what users generate with `galaxio-cli`.
- Every image MUST end with a `RUN` that proves its tools work (`java --version`, the build tool's
  `--version`, `galaxio version`); a build that cannot run them fails.

Rationale: containers built from these images must not re-download dependencies at run time.

### VI. Published tags are never overwritten

- Registry limits are a budget. Docker Hub pull and push limits are shared by every build, and a
  storm of pushes and pulls during active development exhausts them. Pull request builds MUST NOT
  push images or caches to Docker Hub. Today they push `<java>-<commit sha>` tags and `-pr` cache
  refs; that is a deviation, tracked by galax-io/galaxio-sdlc-backlog#291 together with the rework of
  the CI. Until it is removed, a pull request build MUST NOT push or overwrite a version tag or the
  moving `<java>` tag, and MUST NOT add a new kind of tag or cache ref.
- Version tags (`<java>-<X.Y.Z>`, `<java>-v<X.Y.Z>`) are produced only by the `prepare-release` job
  of `build.yml` (manual dispatch, the weekly schedule, or a pushed `v*` tag). A plain push to `main`
  MUST NOT cut a release.
- The commit subject decides the bump (`feat` -> minor, `!:` or `BREAKING CHANGE` -> major, else
  patch). A change that renames or removes an image, a tag scheme, an environment variable, a
  path in `/home/nonroot`, or the runtime `ENTRYPOINT` MUST be marked breaking.

Rationale: users pin `galaxioteam/*:<java>-<version>`; the release text in `build.yml` lists those
tags for every image.

### VII. Deterministic gates before merge

- A change to a shell script MUST pass ShellCheck (`.github/workflows/shellcheck.yml`, severity
  warning) and keep `set -euo pipefail` (or `set -eu` for POSIX `sh`).
- A change to a Dockerfile MUST pass `hadolint *.Dockerfile` before commit (`AGENTS.md`).
- A change to `.github/scripts/buildkit-build.sh` or `resources/sbt-warmup.sh` MUST come with a
  failing-then-passing case in `tests/test_buildkit_build.sh` or `tests/test_sbt_warmup.sh`.
- Every runtime image MUST pass `tests/test_runtime_smoke.sh` and the `BasicSimulation` run against
  `tests/fixtures/<tool>` in CI before it ships.

Rationale: these images are only checked by running them; a red chain is never released.

## Public Contracts and Dependencies

From `catalog-info.yaml` and the Dockerfiles:

- **Uses `galaxio-cli`** (API): the `galaxio` binary is installed from the `galax-io/galaxio-cli`
  release tarball `galaxio_<version>_linux_amd64.tar.gz`; the images rely on `galaxio version`,
  `galaxio template configure` and `galaxio template init`. A change of the CLI's command surface
  or release asset name is a breaking input here.
- **Uses `galaxio-template-registry`** (template): the sbt warmup renders `gatling/scala-sbt`, fetched
  from `galax-io/templates-gatling` with the values in `resources/sbt-warmup.sh`. Template values the
  warmup passes MUST stay valid for the ref it pins.
- **Uses `spec-kit-galaxio-bootstrap`** (process): the Spec Kit kit and the gate files arrive through
  `copier update` and are not edited here (see below).
- **Offers**: the images under `galaxioteam/` on Docker Hub, their tags, `HOME=/home/nonroot`,
  the build tool environment variables (`SBT_OPTS`, `COURSIER_CACHE`, `MAVEN_CONFIG`,
  `GRADLE_USER_HOME`, `GATLING_JAVA_OPTS`, `JAVA_OPTS_COMMON`) and the runtime `ENTRYPOINT
  ["/bin/bash", "-c"]`. These are public; changing them follows Principle VI.
- `catalog-info.yaml` relations MUST be updated in the same change that adds or removes a
  dependency.

## Security and Secrets

- Docker Hub credentials exist only as the repository secrets `DOCKER_USERNAME` and
  `DOCKER_PASSWORD`; no credential, token or registry password is committed or baked into an image
  layer.
- The backlog token `BACKLOG_READ_TOKEN` is used only in `.github/workflows/linkage.yml`, a workflow
  that runs no build code; it MUST NOT be passed to a build workflow.
- Every job MUST declare minimal `permissions:`; only `prepare-release` (the release tag) and
  `github-release` (the GitHub Release) in `build.yml` write `contents`.

## Development Workflow and Quality Gates

- Work enters through the backlog: every PR carries a milestone and
  `Part of galax-io/galaxio-sdlc-backlog#<feature>`, enforced by `scripts/check-linkage.sh --pr`.
- The Spec Kit kit (`.claude/skills/speckit-*`, `.agents/skills/speckit-*`, `.specify/` except
  `memory/`) MUST match `.specify/speckit-kit.sha256`, enforced by `scripts/check-speckit.sh`.
- Branch from `main`, one concern per PR, rebase merge only, every commit green; no force-push to
  `main`.
- A plan's Constitution Check answers, for each principle above, whether the change touches it and
  how it stays within it.

## Governance

- This constitution is amended only by a pull request to this repository with the maintainer's
  explicit approval. Each amendment updates the Sync Impact Report at the top of this file.
- Versioning: MAJOR for removing or redefining a principle, MINOR for adding a principle or section,
  PATCH for wording that changes no rule.
- An exception to a principle is recorded in the plan's Complexity Tracking with an owner and a
  removal date; an exception without both is a violation.
- Reviewers check every PR against this file; where `AGENTS.md` and this file disagree, this file
  wins and `AGENTS.md` is corrected.

**Version**: 1.0.0 | **Ratified**: 2026-10-20 | **Last Amended**: 2026-10-20
