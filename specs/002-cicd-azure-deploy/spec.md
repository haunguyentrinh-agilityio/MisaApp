# Feature Specification: CI/CD Pipeline with Branch-Based Deployment to Azure

**Feature Branch**: `002-cicd-azure-deploy`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Setup CI/CD process. Use Github Action. Merge code to develop branch -> deploy develop environment; merge code to stag branch -> deploy stage environment; merge code to main branch -> deploy production environment. Use Azure Container platform"

## Clarifications

### Session 2026-10-14

- Q: Should production deploy automatically on merge to `main`, or wait for approval? → A: Approval is
  required for both stage and production; develop deploys automatically.
- Q: How are the Azure resources created? → A: Defined as code in this repository and applied by the
  pipeline.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Merging to `develop` ships to the develop environment (Priority: P1)

A developer merges a pull request into `develop`. Without any manual steps, the change is checked, built,
and released to the develop environment, where the team can open MisaApp in a browser and try it. The
developer can see whether the release succeeded and which commit is running.

**Why this priority**: This is the most frequent path and the foundation for the other two. Once one
environment deploys automatically, stage and production are the same flow with different targets.

**Independent Test**: Merge a small visible change into `develop`; within the target time the develop
environment URL serves the new version, its health check reports healthy, and the chat box works.

**Acceptance Scenarios**:

1. **Given** a pull request targeting `develop` passes all checks, **When** it is merged, **Then** the
   pipeline starts automatically and the develop environment runs the merged commit when it finishes.
2. **Given** a merge into `develop`, **When** any quality check fails (backend tests, frontend lint,
   type check, unit tests, build, or end-to-end tests), **Then** nothing is deployed, the previous
   version keeps running, and the failure is visible on the commit with a link to the logs.
3. **Given** a successful deployment, **When** a team member opens the develop environment, **Then**
   the app loads, the health endpoint reports healthy (including the database), and a chat message
   gets a reply.
4. **Given** the merged change includes a database migration, **When** it is deployed, **Then** the
   develop database schema is updated before the new version takes traffic.

---

### User Story 2 - Pull requests are validated before merge (Priority: P1)

A developer opens or updates a pull request against `develop`, `stag`, or `main`. The same quality
checks used before deployment run on the pull request and report pass/fail, so broken code is caught
before it reaches any environment.

**Why this priority**: Deploy-on-merge is only safe if merges are checked first. Without this, every
broken merge becomes a broken environment.

**Independent Test**: Open a pull request containing a deliberately failing test; the checks report a
failure on the pull request and nothing is deployed anywhere.

**Acceptance Scenarios**:

1. **Given** a pull request is opened or updated, **When** the checks run, **Then** the pull request
   shows a pass/fail status for each check.
2. **Given** a pull request, **When** its checks run, **Then** no environment is changed.
3. **Given** a pull request whose checks fail, **When** a reviewer looks at it, **Then** they can tell
   which check failed and open its log.

---

### User Story 3 - Merging to `stag` ships to the stage environment (Priority: P2)

A release owner promotes tested work by merging `develop` into `stag`. After a designated approver
approves the release, the stage environment is updated with that exact code so the team can do
acceptance testing in a production-like setting with its own data and configuration.

**Why this priority**: Stage is the safety net before production, but the team can work (with more
risk) on develop alone.

**Independent Test**: Merge `develop` into `stag` and approve the release; the stage environment
serves the merged commit, while the develop environment is unaffected.

**Acceptance Scenarios**:

1. **Given** a merge into `stag` whose checks pass, **When** the pipeline reaches the deployment step,
   **Then** it waits for approval and stage keeps running the previous version until approved.
2. **Given** a pending stage release, **When** a designated approver approves it, **Then** the stage
   environment runs that commit and the develop and production environments are unchanged.
3. **Given** a pending stage release, **When** an approver rejects it, **Then** nothing is deployed and
   the run is marked as rejected with the approver's name.
4. **Given** the stage environment, **When** it runs, **Then** it uses its own database and its own
   configuration and secrets, never those of develop or production.

---

### User Story 4 - Merging to `main` ships to production (Priority: P2)

A release owner merges `stag` into `main` to release. The build and checks run immediately; the
production deployment then waits until a designated approver approves it, after which production is
updated with that code.

**Why this priority**: This is the business goal (getting changes to real users), but it depends on
the develop and stage flows being proven first.

**Independent Test**: Merge `stag` into `main` and approve the release; production serves the merged
commit and its health check is green, with no downtime visible to a user who is chatting during the
release.

**Acceptance Scenarios**:

1. **Given** a merge into `main` whose checks pass, **When** the pipeline reaches the deployment step,
   **Then** it waits for a designated approver and production is unchanged until approval.
2. **Given** a pending production release, **When** it is approved and the release completes, **Then**
   production runs that commit, the approval (who, when) is recorded, and develop and stage are
   unchanged.
3. **Given** a pending production release, **When** someone who is not a designated approver tries to
   approve it, **Then** the approval is refused.
4. **Given** a user is using production during a release, **When** the new version rolls out, **Then**
   the app stays available and their existing conversations are preserved.
5. **Given** a production release whose post-deployment health check fails, **When** the pipeline
   detects it, **Then** traffic stays on (or returns to) the previous version and the team is notified.

---

### User Story 5 - Roll back an environment to a previous version (Priority: P3)

When a release causes a problem, a release owner can put an environment back on a previously deployed
version without rebuilding it and without changing the other environments.

**Why this priority**: Rarely used, but it bounds how long an incident lasts. Fixing forward through a
new merge is the fallback until this exists.

**Independent Test**: Deploy two versions to develop, roll back to the first, and confirm develop
serves the first version again.

**Acceptance Scenarios**:

1. **Given** an environment that has had at least two successful deployments, **When** a release owner
   triggers a rollback to an earlier version, **Then** that environment runs the earlier version and
   the other environments are unchanged.
2. **Given** a rollback, **When** it completes, **Then** the deployment history shows who rolled back,
   when, and to which version.

---

### Edge Cases

- Two merges land on the same branch in quick succession: deployments to one environment never run in
  parallel; the newest commit is the one that ends up deployed.
- A deployment starts but the new version fails to become healthy: the previous version keeps serving
  traffic and the run is marked failed.
- A database migration fails mid-deployment: the new version is not put into service and the run is
  marked failed; the team is notified.
- A migration is not backward compatible with the version still serving traffic during rollout: it is
  flagged by the release process (documented rule), since the pipeline cannot detect it automatically.
- Required secrets or configuration for an environment are missing: the deployment fails fast with a
  clear message naming the missing setting (never its value).
- The cloud platform is temporarily unreachable: the run fails without partial changes and can be
  re-run manually.
- Someone pushes directly to `develop`, `stag`, or `main` instead of merging a pull request: the
  branches are protected so this is rejected (administrators excepted), and a push that does land
  still goes through the same checks before deploying.
- A stage or production release is never approved: the approval expires after the platform's waiting
  limit, nothing is deployed, and the run is marked as not deployed.
- A newer merge arrives while an older release is waiting for approval: the older pending release is
  superseded so approvers only ever approve the latest commit.
- An infrastructure change would delete or replace a stateful resource (such as a database): the change
  is visible in the planned-changes output before approval, and deletion protection blocks it unless
  explicitly lifted.
- A deployment is re-run for a commit that is already deployed: the result is the same version
  running, with no side effects.
- The Gemini API key is absent for an environment: the app still starts (echo model fallback), and the
  pipeline does not fail because of it.

## Requirements *(mandatory)*

### Functional Requirements

**Continuous integration**

- **FR-001**: The pipeline MUST run the project's full definition-of-done checks (backend tests;
  frontend lint, type check, unit tests, and build; end-to-end tests against the containerized stack)
  on every pull request targeting `develop`, `stag`, or `main`.
- **FR-002**: The pipeline MUST run the same checks on every merge to `develop`, `stag`, or `main`
  before any deployment, and MUST NOT deploy if any check fails.
- **FR-003**: Each check MUST report its result on the pull request or commit, with a link to its logs.
- **FR-004**: End-to-end tests in the pipeline MUST NOT depend on real AI model output or on a real
  AI API key.

**Build and release**

- **FR-005**: The pipeline MUST build each deployable component once per commit and deploy that same
  built artifact, so what was tested is what is deployed.
- **FR-006**: Every built artifact MUST be traceable to the commit it was built from, and every
  environment MUST be able to report which commit it is running.
- **FR-007**: Built artifacts MUST be retained long enough to allow rolling back to at least the last
  5 releases of each environment.

**Deployment**

- **FR-008**: A merge to `develop` MUST deploy to the develop environment; a merge to `stag` MUST
  deploy to the stage environment; a merge to `main` MUST deploy to the production environment. A
  deployment MUST NOT change any other environment.
- **FR-009**: Deployments to stage and production MUST wait for approval from a designated approver
  after the checks pass; develop deploys without approval. Only designated approvers can approve, a
  rejected or expired approval MUST deploy nothing, and every approval or rejection MUST be recorded
  (who, when).
- **FR-010**: Deployments to the same environment MUST be serialized; a newer pending deployment
  supersedes an older one that has not started.
- **FR-011**: Database schema migrations MUST be applied as an explicit deployment step before the new
  version receives traffic, not by the application on startup in stage or production.
- **FR-012**: A deployment MUST verify the new version is healthy (including database connectivity)
  before it is considered successful; if verification fails, the previous version MUST remain or
  become the serving version.
- **FR-013**: Production and stage releases MUST NOT cause user-visible downtime for the chat app.
- **FR-014**: Release owners MUST be able to trigger a rollback of a single environment to a
  previously deployed version.
- **FR-015**: Release owners MUST be able to manually re-run a deployment for an environment.

**Environments, configuration, and secrets**

- **FR-016**: Develop, stage, and production MUST each have their own database, configuration, and
  secrets; no environment may read another environment's data or secrets.
- **FR-017**: Secrets (database credentials, AI API key, cloud credentials) MUST be stored in a
  managed secret store and MUST NOT appear in the repository, in build artifacts, or in pipeline logs.
- **FR-018**: The pipeline MUST authenticate to the cloud platform without long-lived stored
  passwords where the platform supports it.
- **FR-019**: Each environment MUST be reachable at a stable, documented HTTPS address.
- **FR-020**: The Azure resources that make up each environment MUST be defined as code in this
  repository and created/updated by the pipeline, so that all three environments are built from the
  same definition and differ only in declared per-environment parameters (size, scale, names).
- **FR-020a**: Infrastructure changes MUST go through the same pull request review and branch flow as
  application code; the pipeline MUST show the planned infrastructure changes for review, and for stage
  and production those changes MUST be covered by the same approval as the deployment.
- **FR-020b**: Applying the infrastructure definition MUST be repeatable: re-applying it without changes
  MUST NOT alter or recreate resources, and MUST NOT delete or reset an environment's database data.
- **FR-020c**: The only one-time manual setup allowed is what the pipeline needs in order to start
  (subscription access, pipeline identity, and storage for infrastructure state), and it MUST be
  documented step by step.

**Visibility and governance**

- **FR-021**: The team MUST be able to see, per environment, the deployment history: commit, who
  triggered it, when, and the result.
- **FR-022**: A failed deployment to any environment MUST notify the team through the repository's
  standard notifications.
- **FR-023**: `develop`, `stag`, and `main` MUST be protected so that changes land only through pull
  requests whose checks have passed.
- **FR-024**: The process (branch flow, how to promote, how to roll back, how to add a secret) MUST be
  documented in `docs/`.

### Key Entities

- **Environment**: A named, isolated deployment target (develop, stage, production) with its own
  address, database, configuration, secrets, and approval rules. Mapped one-to-one to a source branch.
- **Release artifact**: The built, versioned output for one commit (one per deployable component),
  immutable once built and reused across environments.
- **Deployment**: One attempt to put a release artifact into an environment: commit, environment,
  trigger (merge, manual re-run, rollback), actor, start/end time, result.
- **Pipeline run**: One execution of the checks (and optionally a deployment) for a pull request or
  merge, with per-check results and logs.
- **Approval**: A decision by a designated approver on a pending stage or production release: release,
  approver, decision (approved/rejected/expired), time.
- **Infrastructure definition**: The versioned description, kept in the repository, of every cloud
  resource an environment needs, plus the per-environment parameters that distinguish develop, stage,
  and production.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a merge to `develop`, the change is live in the develop environment within
  20 minutes in at least 90% of runs, with zero manual steps.
- **SC-002**: 100% of deployments are preceded by a passing run of the full quality checks; no failing
  commit ever reaches any environment.
- **SC-003**: A user chatting in production during a release experiences no failed requests caused by
  the release (zero downtime during rollout).
- **SC-004**: A release owner can roll an environment back to a previous version in under 10 minutes.
- **SC-005**: For any environment, a team member can find which commit is running and who deployed it
  in under 1 minute.
- **SC-006**: Zero secrets are present in the repository, build artifacts, or pipeline logs (verified
  by secret scanning and log review).
- **SC-007**: A new team member can follow the documentation to promote a change from develop to
  production without help.
- **SC-008**: Once a stage or production release is approved, it is live within 15 minutes in at least
  90% of runs.
- **SC-009**: A brand-new environment can be created from the repository's infrastructure definition
  with no manual cloud-console steps beyond the documented one-time bootstrap.
- **SC-010**: 100% of stage and production deployments have a recorded approval by a designated
  approver.

## Assumptions

- **Platform constraints (from the request)**: the pipeline runs on GitHub Actions and the app is hosted
  on Azure's container platform. The specific Azure service, registry, and database offering are chosen
  in the plan.
- The branches `develop`, `stag` (the stage environment's branch, spelled as it exists in the repository),
  and `main` already exist on the remote. Promotion flows `develop` → `stag` → `main` via pull requests.
- An Azure subscription and GitHub repository admin access are available to whoever sets this up;
  cost limits and Azure region are decided in the plan.
- The designated approvers for stage and production are the repository owner(s) to start with; the
  list is managed in the repository settings and can change without a code change.
- The infrastructure-as-code tool is chosen in the plan; the tool's state (if any) is stored remotely
  and protected, not in the repository.
- Each environment runs the same set of components as the Docker stack (frontend, backend, database);
  the end-to-end test runner is a CI-only component and is not deployed.
- Data in each environment persists across deployments; develop and stage hold test data only, and no
  production data is copied to lower environments.
- Develop and stage may run without an AI API key (echo model); production uses a real key.
- Custom domain names are out of scope for now; platform-provided HTTPS addresses are acceptable.
- Out of scope: authentication for the app itself, preview environments per pull request, performance/
  load testing in the pipeline, multi-region deployment, and automated cost reporting.
- Notifications use GitHub's built-in mechanisms (failed check/run emails, commit status); chat
  integrations (e.g. Teams/Slack) are out of scope.
