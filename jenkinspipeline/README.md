# Jenkins Pipeline Automation

Creates the `JJ-Pipelines` Jenkins view and three pipeline jobs — one per
`Jenkinsfile*` in this repo — via the Jenkins REST API.

| Job name                     | Script path              |
|-------------------------------|---------------------------|
| `sample-java-app-build`       | `Jenkinsfile`             |
| `sample-java-app-ecr`         | `Jenkinsfile.ecr`         |
| `sample-java-app-deploy-app`  | `Jenkinsfile.deploy-app`  |

Each job is a "Pipeline script from SCM" job pointing at this repo's `origin`
remote (resolved dynamically via `git remote get-url origin` at run time) on
the `master` branch.

## Prerequisites

- `bash`, `curl`, `git`
- A Jenkins user with permission to create views and jobs, and an API token
  for that user (**Manage Jenkins > Users > \<user\> > Configure > API Token**)

## Setup

```bash
cp .env.example .env
# then edit .env and fill in JENKINS_URL, JENKINS_USER, JENKINS_API_TOKEN
```

`.env` is git-ignored — never commit it.

## Run

```bash
bash jenkinspipeline/create_pipelines.sh
```

The script is idempotent: re-running it updates existing jobs' config and
re-adds them to the view (a harmless no-op if already a member) instead of
failing.

## Verify

- The script prints the view URL and each job's URL on success.
- `curl -s -u "$JENKINS_USER:$JENKINS_API_TOKEN" "$JENKINS_URL/view/JJ-Pipelines/api/json"`
  should list all three jobs.
- Visit `$JENKINS_URL/view/JJ-Pipelines/` in a browser.
