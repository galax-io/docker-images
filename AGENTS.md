# docker-images — Agent Guide

Docker image CI/CD repo for Galaxio Gatling load testing. Published to Docker Hub `galaxioteam/`.

**Constitution:** the principles of this repository are in `.specify/memory/constitution.md`; where they conflict with this file, the constitution wins.

Use Docker skills: `docker-syntax-dockerfile`, `docker-syntax-buildkit`, `docker-syntax-multistage`, `docker-impl-build-optimization`, `docker-impl-cicd`, `docker-errors-build`.

## Image Hierarchy

Every image `FROM` the previous. Never break this chain.

debian:bookworm-slim             (java.Dockerfile adds the JDK and a checksum-verified galaxio-cli release)
└── galaxioteam/base-jdk         (java.Dockerfile)              × java 17, 21
    ├── gatling-sbt-builder  → gatling-sbt-runtime  → gatling-sbt-debug
    ├── gatling-maven-builder→ gatling-maven-runtime→ gatling-maven-debug
    └── gatling-gradle-builder→gatling-gradle-runtime→gatling-gradle-debug
```

6 Dockerfiles → 20 image tags. The chain starts at `debian:bookworm-slim`; `galaxioteam/galaxio` is not a parent of any image here. Builders warm dependency caches (Coursier/.sbt, .m2, .gradle) so containers don't re-download at runtime.

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
- **Every PR links a feature.** No PR of a product repository merges without `Part of galax-io/galaxio-sdlc-backlog#<feature>` (or a closing link to a feature); `scripts/check-linkage.sh --pr` fails it. A bot's PR (a bot author, or a `dependabot/` or `update/` branch) and the backlog's own PRs are exempt. The backlog is private, so the CI job reads it with `BACKLOG_READ_TOKEN`, a read-only token for that repository (Issues and Metadata) set as an organization secret; without it the gate fails and says it cannot read the backlog. A technical PR with no feature of its own may skip this check with the maintainer's agreement: a line `No feature: <why, and who agreed>` of its own in its description, at least ten characters long, which the gate prints in its log. A milestone gets no standing feature of its own any more; the ones that exist stay until their release.
- **Work enters through the backlog.** A bug, an audit finding or a request is not worked on until it belongs to a feature: grouped into one or given one. An issue from outside stays in its repository, which is public, and carries the label `status:needs-feature` until it is linked to a feature in the backlog.
- **Feature done.** A feature issue is closed only when every line of its checklist is checked.
- **Release.** When every feature of a business milestone is closed, close the milestone and publish a GitHub Release in `galax-io/galaxio-sdlc-backlog` that lists each feature with the repository versions that carry it. Name the release and its tag by the milestone's id, the title up to its first em dash, lowercased (`M1 — first run` → `m1`).
- **Published releases are not edited.** A revert after the release is a new feature in the next business milestone.
- **Never** close a business milestone with an open feature, release a feature whose repository version is not tagged, or leave a repository version out of the release text.


## Labels (ALWAYS)

One label scheme for every repository of the organization: `scripts/labels.json` in `galax-io/galaxio-sdlc-backlog` (`plans/label-scheme.md` there says why). A label says what the milestone and the feature link do not: the kind of work, its topic, how bad it is, where it stands.

- **Names.** Every label is `group:value`. Labels a tool owns (GitHub's `good first issue` and `help wanted`, Dependabot's, and those code reads, listed as `reserved`) are left alone.
- **Exactly one `type:*` on every open issue:** `bug`, `enhancement`, `docs`, `maintenance`, `question`; in the backlog `type:feature` (an issue of a business milestone) or `type:standing` (the standing feature of an older milestone). An issue without a type is not triaged.
- **At most one each:** `severity:*` (`critical`, `high`, `medium`, `low`: the impact, not the order of work), `status:*` (`needs-triage`, `needs-info`, `needs-feature`, `ready-for-agent`, `ready-for-human`, `blocked`), `tier:*`.
- **Any number:** `area:*` (topics shared by every repository), `module:*` (parts of one repository, declared in the scheme), `source:external`, `source:audit`.
- **Not labels.** The order of work is the milestone: no `priority:*`. The feature is the `Part of` link: no `feature:*`. A rejected or duplicate issue is closed with that reason and a comment: no `wontfix`, `invalid`, `duplicate`.
- **The engine's labels** `sdlc:*` live in the backlog: the maintainer sets `sdlc:run`; only the engine sets `sdlc:gate`, `sdlc:done` and `sdlc:failed`.
- **A new label is a change to the scheme**, a PR to `scripts/labels.json`, not a label made in one repository. `scripts/sync-labels.sh` applies the scheme; `--check` lists what breaks it.

## Task number (ALWAYS)

A task of the backlog has one number across the organization: `BCKLG-<N>`, where `<N>` is its issue number in `galax-io/galaxio-sdlc-backlog`. It is the only number a spec gets, and it names the task wherever `#N` alone would be read as an issue or PR of another repository.

- **Spec.** Its directory is `specs/BCKLG-<N>-<name>/`, `<N>` its main task. Its `spec.md`, `plan.md` and `tasks.md` carry the line `**Задачи**: BCKLG-<N>[, BCKLG-<M>…]` under the title, or `**Tasks**: …` in a repository whose files are English only, read alike: every task it carries, the main one first. A task has one spec: before writing one, find the spec whose tasks line names the task, check it against the task as its issue says now, and update it rather than write another. A spec directory from before the number keeps its name.
- **Branch.** A spec branch made by hand is `spec/BCKLG-<N>-<name>`; the engine's run is `BCKLG-<N>-<time>`, on the branch `sdlc/BCKLG-<N>-<time>`.
- **Commit.** A commit that does a task's work carries the trailer `Refs: BCKLG-<N>`; its subject stays a Conventional Commit.
- **PR.** Its body carries the line `Refs: BCKLG-<N>` beside `Part of galax-io/galaxio-sdlc-backlog#<N>`.
- **Checked.** `scripts/check-linkage.sh --pr` fails a PR of a feature without its number, a spec directory it adds that is not named by a task, and a spec, plan or tasks without the tasks line; `--specs` checks every spec of a checkout.

