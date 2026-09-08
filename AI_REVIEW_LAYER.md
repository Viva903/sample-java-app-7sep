# AI Review Layer

Three GitHub Actions workflows add an AI review layer on top of every pull
request, ahead of the existing Jenkins build/deploy pipelines
(`Jenkinsfile`, `Jenkinsfile.ecr`, `Jenkinsfile.ecs`, `Jenkinsfile.eks`,
`Jenkinsfile.deploy-app`). They run on `pull_request` events only — they do
not change Jenkins, deployment, or the build itself.

## What was added

| File | Does |
|---|---|
| `.github/workflows/ai-pr-review.yml` | Claude reviews the PR diff for bugs, security issues, and maintainability, and posts one PR comment. |
| `.github/workflows/ai-security-scan.yml` | Runs Gitleaks (secrets), OWASP Dependency-Check (vulnerable dependencies), and Trivy (container image built from the repo `Dockerfile`), then has Claude triage the three raw reports into one prioritized "must fix / worth tracking / noise" PR comment. Raw JSON reports are uploaded as a workflow artifact. |
| `.github/workflows/ai-test-gap-analysis.yml` | Runs `mvn test` (now with JaCoCo instrumentation), then has Claude cross-reference the coverage report against the PR diff to list untested changed methods, ranked by risk, with draft JUnit 5 tests suggested (not committed) for the riskiest ones. |
| `pom.xml` | Added `jacoco-maven-plugin` (0.8.12), bound to `test`, so `target/site/jacoco/jacoco.xml` and `index.html` are produced on every `mvn test` — the coverage baseline the test-gap workflow reads. This also benefits the existing Jenkins `Sonar Scan` stage. |
| `sonar-project.properties` | Added `sonar.coverage.jacoco.xmlReportPaths` so SonarQube also picks up the new JaCoCo coverage data. |

## Required setup (not done by this change)

- Add an `ANTHROPIC_API_KEY` repository secret (Settings → Secrets and
  variables → Actions) — all three workflows need it.
- Optional: add an `NVD_API_KEY` secret to speed up/raise rate limits on the
  OWASP Dependency-Check scan (it runs without one, just slower).
- Docker must be available on the `ubuntu-latest` runner for the Gitleaks and
  Trivy steps — this is preinstalled on GitHub-hosted runners by default.

## Design notes

- **Advisory, not blocking.** All three workflows post PR comments; none of
  them fail the PR check by default. This matches the "faster delivery,
  AI-prioritized findings instead of blanket hard gates" direction from the
  brainstorm — a team can later turn any of these into a required check once
  they trust the signal.
- **Reuses the actual shipped artifact.** The security scan builds the image
  from the same `Dockerfile` the Jenkins ECR/ECS/EKS pipelines push, so a
  finding here reflects what would actually go to production.
- **Diff-scoped, not whole-repo.** The PR review and test-gap prompts are
  scoped to the PR's diff against its base branch, so they don't re-flag the
  repo's pre-existing seeded issues (hardcoded key, MD5, `java.util.Random`,
  etc.) on every unrelated PR — only new/changed code is reviewed. The
  security scan (secrets/deps/image) still runs full-scope, since those risks
  aren't diff-local.
- **Not wired into Jenkins.** PR-time review is inherently a git-hosting-side
  concept; since this repo is hosted on GitHub
  (`https://github.com/Viva903/sample-java-app-7sep`), GitHub Actions is the
  natural place for it, separate from the Jenkins pipelines that handle
  build/deploy after merge.

## Not done here (left for follow-up)

- Making the Sonar quality gate or these AI checks required/blocking.
- Fixing the repo's pre-existing seeded issues that the reviewers will now be
  able to see clearly (hardcoded key, MD5, `java.util.Random`, root
  Docker/k8s execution, `testFailureIgnore=true`).
- Consolidating the 5 Jenkinsfiles into a shared library.
