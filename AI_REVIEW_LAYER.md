# AI Review Layer

An AI review layer runs at build time in Jenkins: every `Jenkinsfile*` now
scans and triages each build. It's additive reporting/triage — it doesn't
change deployment behavior.

## What was added

| File | Does |
|---|---|
| `ci/security-scan.sh` | Runs Gitleaks (secrets) and a `trivy fs` scan (dependencies) against the source tree, writing JSON reports to `security-reports/`. Uses Trivy rather than OWASP Dependency-Check specifically because Dependency-Check needs an NVD API key to run in reasonable time (see incident note below). Invoked from the new **Security Scan** stage, right after **Sonar Scan** (or after **Test** in `Jenkinsfile.deploy-app`, which has no Sonar stage), in all five `Jenkinsfile*`. |
| `ci/image-scan.sh` | Runs Trivy against the just-built Docker image (`IMAGE_REF=${IMAGE_NAME}:${BUILD_NUMBER}`), writing `security-reports/trivy-report.json`. Invoked from the new **Container Image Scan** stage, right after **Build Docker Image**, in `Jenkinsfile.ecr` / `.ecs` / `.eks` (before the image is pushed to ECR). |
| `ci/ai-triage.sh` | Calls the Claude API directly (raw HTTPS via `curl`, model `claude-opus-5`) with: the `*.java` diff since the previous commit, the JaCoCo coverage XML, and whichever of the scanner reports exist. Writes one `ai-review-report.md` with test-gap analysis, security triage, and a PASS / PASS WITH FINDINGS / BLOCKER verdict line. Invoked from the new **AI Review** stage in all five `Jenkinsfile*`, using a Jenkins `ANTHROPIC_API_KEY` credential the same way `Sonar Scan` already uses `SONAR_TOKEN`. |
| `Jenkinsfile`, `Jenkinsfile.ecr`, `Jenkinsfile.ecs`, `Jenkinsfile.eks`, `Jenkinsfile.deploy-app` | Each gained a **Security Scan** stage and an **AI Review** stage; `.ecr`/`.ecs`/`.eks` also gained a **Container Image Scan** stage between **Build Docker Image** and **Push to ECR**. All new stages `archiveArtifacts` their reports (`security-reports/*.json`, `ai-review-report.md`) so they're visible from the Jenkins build page. |
| `pom.xml` | Added `jacoco-maven-plugin` (0.8.12), bound to `test`, so `target/site/jacoco/jacoco.xml` and `index.html` are produced on every `mvn test` — the coverage baseline the AI Review stage reads. This also benefits the existing `Sonar Scan` stage. |
| `sonar-project.properties` | Added `sonar.coverage.jacoco.xmlReportPaths` so SonarQube also picks up the new JaCoCo coverage data. |

### Why Jenkins-only, build-scoped rather than PR-scoped

`jenkinspipeline/create_pipelines.sh` registers each Jenkinsfile as a plain
"Pipeline script from SCM" job pinned to `master` — not a multibranch/PR
job — so Jenkins builds have no PR diff or PR-comment target to act on. The
AI Review stage works with what a Jenkins build actually has: it diffs
`HEAD~1..HEAD` (its equivalent of "what changed since last time") and
reports via console output + archived artifacts rather than a PR comment.
(An earlier version of this also added GitHub Actions workflows for PR-time
review; those were removed to keep the AI review layer entirely inside
Jenkins.)

### Incident: why there's no OWASP Dependency-Check

The first live run of `sample-java-app-build` (build #3) was manually
aborted after ~2.5 minutes stuck on `mvn org.owasp:dependency-check-maven:check`:
without an `NVD_API_KEY`, its first run downloads the full NVD vulnerability
feed (387,285 records at the time) and had only reached 3% when it was
killed — comfortably capable of exceeding the pipeline's 30-minute
`timeout()` on every single build. Rather than requiring an NVD API key,
dependency/SCA scanning uses `trivy fs` instead (`ci/security-scan.sh`),
which ships its own prebuilt vulnerability DB and needs no API key. The only
credential this whole AI review layer requires is `ANTHROPIC_API_KEY`.

## Required setup (not done by this change)

- Add an `ANTHROPIC_API_KEY` credential (Secret text) in Jenkins — same
  place `SONAR_TOKEN` and `aws-credentials` already live — so the `AI
  Review` stage's `credentials('ANTHROPIC_API_KEY')` binding resolves. This
  is the only credential the whole AI review layer needs.
- Docker must be available on the Jenkins agent — already a requirement
  today (the existing `Build Docker Image` / `docker push` stages need it).
  `ci/security-scan.sh` / `ci/image-scan.sh` also need outbound access to
  pull `zricethezav/gitleaks` and `aquasec/trivy` images, and
  `ci/ai-triage.sh` needs `jq` on the agent plus outbound HTTPS to
  `api.anthropic.com`.

## Design notes

- **Advisory, not blocking.** The `AI Review` stage always exits 0 — even on
  an API failure it writes a fallback report rather than failing the build.
  None of the new stages fail a build today. The verdict line in
  `ai-review-report.md` (PASS / PASS WITH FINDINGS / BLOCKER) is there so a
  team can later wire a `BLOCKER` result to `error()` the stage once they
  trust the signal, without having to touch the prompt.
- **Reuses the actual shipped artifact.** The image scan runs Trivy against
  the same `Dockerfile` the ECR/ECS/EKS pipelines push, so a finding
  reflects what would actually go to production.
- **Diff-scoped where it matters.** The AI Review stage diffs `HEAD~1..HEAD`
  for the test-gap analysis, so it doesn't re-flag the repo's pre-existing
  seeded issues (hardcoded key, MD5, `java.util.Random`, etc.) on every
  unrelated build — only newly changed code is reviewed for test gaps.
  Secret/dependency/image scans still run full-scope, since those risks
  aren't diff-local.
- **Scripts are single-responsibility, matching `ci/deploy-app.sh`'s
  existing pattern**: `security-scan.sh` (secrets + deps), `image-scan.sh`
  (Trivy, needs a built image), and `ai-triage.sh` (the Claude call) are
  separate scripts invoked from separate stages, rather than one large
  script or a new Jenkins Shared Library (this repo doesn't have one, and
  introducing one is a bigger structural change than this task).

## Not done here (left for follow-up)

- Making the Sonar quality gate or the AI Review stage required/blocking
  (the verdict line is designed to make this an easy follow-up).
- Fixing the repo's pre-existing seeded issues that the reviewer will now be
  able to see clearly (hardcoded key, MD5, `java.util.Random`, root
  Docker/k8s execution, `testFailureIgnore=true`).
- Consolidating the 5 Jenkinsfiles' now-larger duplicated stage lists into a
  shared library.
