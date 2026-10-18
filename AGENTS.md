# docker-images — Agent Guide

Docker image CI/CD repo for Galaxio Gatling load testing. Published to Docker Hub `galaxioteam/`.

Use Docker skills: `docker-syntax-dockerfile`, `docker-syntax-buildkit`, `docker-syntax-multistage`, `docker-impl-build-optimization`, `docker-impl-cicd`, `docker-errors-build`.

## Image Hierarchy

Every image `FROM` the previous. Never break this chain.

galaxioteam/galaxio              (external: github.com/galax-io/galaxio-cli, always latest)
└── galaxioteam/base-jdk         (java.Dockerfile)              × java 17, 21
    ├── gatling-sbt-builder  → gatling-sbt-runtime  → gatling-sbt-debug
    ├── gatling-maven-builder→ gatling-maven-runtime→ gatling-maven-debug
    └── gatling-gradle-builder→gatling-gradle-runtime→gatling-gradle-debug
```

6 Dockerfiles → 20 image tags. Base image (`galaxioteam/galaxio`) built externally, versioned independently. Builders warm dependency caches (Coursier/.sbt, .m2, .gradle) so containers don't re-download at runtime.

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
2. **Pre-commit checks**: `shellcheck resources/*.sh`, `hadolint *.Dockerfile`
3. **Commits**: squash semantically — each commit must be green (CI passes). No red commits on `main`
4. **Merge strategy**: always **rebase + merge** (no merge commits)
5. **PR CI** (`pull-request-build.yml`): build-only, `BASE_VERSION=latest`, no Hub push
6. **Release CI** (`build.yml`): push to main or `v*` tag → pushes version + latest tags

## CI DAG

```
prepare-release → build-jdk [17, 21] → build-chains [sbt, maven, gradle] × [17, 21]
                                         each chain: builder → runtime → debug
```

Triggers: push to main, `v*` tags, weekly schedule (Monday 06:00 UTC), manual dispatch.

## Feature milestones (ALWAYS)

A feature is an issue in `galax-io/galaxio-sdlc-backlog`. It belongs to exactly one backlog milestone whose description has the line `Release: business`. Backlog milestones without that line (the backlog's own tooling and documents) are not releases and follow "Milestones" above.

- **Feature issue.** Lists the work in every repository it touches as a checklist, one line per issue or PR: `- [ ] galax-io/<repo>#<N> → <repo milestone>`. A line is checked when that work is merged and the repository milestone it names has been released, so its tag exists.
- **Repository work.** Every issue and PR of a feature carries the version milestone of its own repository and writes `Part of galax-io/galaxio-sdlc-backlog#<feature>`. A repository ships its own version when its milestone is complete, as under "Release Process". `scripts/check-linkage.sh` skips the same-milestone rule for a link to a feature; the PR still needs its own milestone.
- **Every PR links a feature.** No PR of a product repository merges without `Part of galax-io/galaxio-sdlc-backlog#<feature>` (or a closing link to a feature); `scripts/check-linkage.sh --pr` fails it. A bot's PR (a bot author, or a `dependabot/` or `update/` branch) and the backlog's own PRs are exempt. The backlog is private, so the CI job reads it with `BACKLOG_READ_TOKEN`, a read-only token for that repository (Issues and Metadata) set as an organisation secret; without it the gate fails and says it cannot read the backlog. Maintenance and technical PRs with no feature of their own link the standing feature of the active business milestone (the issue with the label `standing`); every business milestone has one.
- **Work enters through the backlog.** A bug, an audit finding or a request is not worked on until it belongs to a feature: grouped into one or given one. An issue from outside stays in its repository, which is public, and carries the label `needs-feature` until it is linked to a feature in the backlog.
- **Feature done.** A feature issue is closed only when every line of its checklist is checked.
- **Release.** When every feature of a business milestone is closed, close the milestone and publish a GitHub Release in `galax-io/galaxio-sdlc-backlog` that lists each feature with the repository versions that carry it. Name the release and its tag by the milestone's id, the title up to its first em dash, lowercased (`M1 — first run` → `m1`).
- **Published releases are not edited.** A revert after the release is a new feature in the next business milestone.
- **Never** close a business milestone with an open feature, release a feature whose repository version is not tagged, or leave a repository version out of the release text.

