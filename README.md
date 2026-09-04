# wallet-balance-service

Take-home assignment: deploy the provided `wallet-balance-service` to AWS
using Terraform and GitHub Actions.

The infrastructure was applied to a real AWS account and verified end to
end — all four endpoints answered correctly through the internal load
balancer, and the CI/CD pipeline built, pushed and deployed a new task
definition revision on merge to `main`.

The environment has since been destroyed. The NAT gateway is the main
running cost and the brief did not ask for a live URL, so screenshots of
each verification step are in `docs/evidence/` instead.

## Contents

- [Summary](#summary)
- [Architecture and trade-offs](#architecture)
- [How to deploy](#how-to-deploy)
- [Verification](#verification)
- [CI/CD](#cicd)
- [Security](#security)
- [Assumptions](#assumptions)
- [What I would change for production](#what-i-would-change-for-production)
- [Documented TODOs](#documented-todos)

---

## Summary

For a reviewer who does not want to read the whole file. Every point
below is expanded further down.

**What was built.** Two Fargate tasks behind an internal ALB, backed by
Single-AZ RDS PostgreSQL, all in private subnets. Public subnets hold
only the NAT gateway. Applied to a real account (54 resources), verified
end to end, then destroyed — evidence is in `docs/evidence/`.

**Compute.** ECS Fargate, not EKS: one service, nothing pointing at
Kubernetes. Not EC2: I did not want to own host patching, and the brief
asks for *managed* Postgres.

**No public entry point.** `/balance/:userId` has no authentication, so
the load balancer is internal. Access is through Systems Manager to a
maintenance host with no public IP, no key pair and no inbound rules.

**Secrets.** RDS owns the master password via
`manage_master_user_password`, so Terraform never holds it — not in
state, not in a plan, not in CI logs. A second secret holds the full
connection string; Terraform declares it but deliberately not its value,
because writing that value would pull the password back into state. ECS
resolves it at task startup, so the application never calls AWS.

**Least privilege — the two I would point at first.** Security group
rules reference other security groups, never CIDR ranges, so access
follows identity rather than address. And the task role carries only the
three `ssmmessages` actions ECS Exec needs, because I read the code and
the application never calls an AWS API.

**CI/CD.** One workflow, two jobs. `test` runs on every push and pull
request; `deploy` runs on `main` only, because the OIDC trust policy is
pinned to `refs/heads/main` and a pull request cannot get credentials at
all. Images are tagged by commit SHA, never `latest`, and ECR rejects
overwriting a tag. Terraform owns the infrastructure; the pipeline owns
one field, the image.

**Health check on `/health`, not `/ready`.** On ECS a failing health
check does not only stop routing — it makes ECS replace the task.
Restarting does not fix a database outage, and every task shares one
database, so draining them all leaves nowhere to route. A CloudWatch
alarm on 5XX carries that signal instead, because deciding where to send
traffic and telling me what broke are two different jobs.

**Deliberate trade-offs.** Single-AZ RDS (reduced availability tier, not
a reduced engine — backups and PITR are on). One NAT gateway, the largest
running cost and the one real single point of failure. Local Terraform
state, since only durability applies to a single operator. Flat Terraform
with no modules, because a module with one caller is indirection without
reuse.

**Two problems found by actually running it, not by reading docs.**

- The pipeline failed OIDC auth with everything apparently correct.
  CloudTrail showed the subject claim GitHub really sends — it appends
  immutable numeric ids to the owner and repository names. Fixed with
  `StringLike` over the ids only; the branch is still matched exactly.
- `/ready` returned 503 with `no encryption`. RDS enforces TLS, and
  `psql` negotiates it by default while node-postgres does not — so my
  debugging tool connected and the application did not. Fixed in the
  injected connection string, no rebuild.

**Known gaps, stated openly.** `sslmode=no-verify` encrypts but does not
verify. Driver errors leak host and database name on an unauthenticated
endpoint. Task egress is open until interface VPC endpoints exist. All
three are in [Documented TODOs](#documented-todos) with reasoning.

---

## Repository layout

```
src/                        application (provided, unchanged)
db/schema.sql               schema and seed data (provided, unchanged)
test/                       jest test (provided, unchanged)
Dockerfile                  provided, modified — see below
terraform/                  infrastructure, one file per AWS service
.github/workflows/deploy.yml  CI/CD
docs/                       architecture diagram and evidence
```

### Changes to the provided files

The brief says application code is not assessed. The Dockerfile is not
application code — it is part of the deployment — so I changed two lines:

- `npm install` → `npm ci --omit=dev`. `npm install` may re-resolve
  versions even when a lockfile is present, so the image that passes CI
  is not necessarily the image that ships. `npm ci` installs exactly what
  the lockfile pins and fails if the two files have drifted apart.
- Added `USER node`, after the install step. The container previously ran
  as root. Fargate reduces the blast radius of a container escape but
  does not remove it, and a root process can also rewrite files inside
  its own image. `node:18-alpine` already ships a `node` user, so none
  needed creating. Placement matters: `/app` is owned by root, so a
  non-root user cannot write `node_modules` into it.

Nothing else in the provided code was touched.

## Architecture

![Architecture](docs/architecture.png)

The service runs as two Fargate tasks behind an internal Application Load
Balancer, backed by an RDS PostgreSQL instance. Everything that runs code
or holds data sits in private subnets. There is no public entry point:
the only way in is AWS Systems Manager, which is controlled by IAM.

A request goes: operator → Systems Manager → maintenance host → internal
ALB → Fargate task → RDS. The public subnets exist to hold the NAT
gateway and to give the private subnets a way out for image pulls and
secret lookups. Nothing else runs there.

### Trade-offs

The brief gave a 3–4 hour time box, so several decisions were made to
keep the scope small. Each one below is a choice, not an oversight.

| Decision | Why | What I gave up |
|---|---|---|
| **ECS Fargate**, not EKS | One service, and nothing in the brief points at Kubernetes. EKS needs a reason — a Kubernetes ecosystem dependency, fine-grained scheduling, or policy enforcement. None applied. | Kubernetes features I did not need |
| **Fargate**, not EC2 | I did not want to own host patching for a single container. The brief also asks for *managed* Postgres, so a single EC2 box running both containers was ruled out anyway. | Lower cost, and more control over the host |
| **Internal ALB**, not internet-facing | `GET /balance/:userId` has no authentication. Putting it on the internet would expose account balances to anyone. | No public URL to demo. I test from inside the VPC instead. |
| **Single-AZ RDS** | This reduces the availability tier, not the engine. Automated backups and point-in-time recovery are still on, so an outage costs visibility, not data. | The database is unavailable during maintenance windows and AZ failures |
| **One NAT gateway**, not one per AZ | It is the largest running cost in this stack, roughly 32 USD per month. One is enough to prove the design. | This is the one real single point of failure in the network |
| **`desired_count = 2`** | Two tasks so a rolling deployment always leaves one serving. | Not sized for load — the workload is a single-key lookup |
| **ALB health check on `/health`**, not `/ready` | On ECS a failing health check does not only stop routing, it makes ECS replace the task. Restarting does not fix a database outage, and every task shares one database, so draining them all leaves nowhere to route. | The load balancer will send traffic to a task that cannot reach the database. The user gets a 500 from the app instead of a 503 from the ALB — the same failure, without a restart loop. A CloudWatch alarm on 5XX carries that signal instead. |
| **Maintenance host over SSM**, not an SSH bastion | No public IP, no key pair, no inbound rules at all. The SSM agent dials out, so nothing dials in. Access is authorised by IAM and every session is in CloudTrail. | An extra instance to pay for and remove. It exists only because schema loading is manual. |
| **Flat Terraform**, no modules | A module earns its place when something is instantiated more than once. There is one environment and one service, so a module would be an indirection layer with a single caller. Files are split by AWS service instead. | Harder to reuse if a second environment appears — that is when I would promote them |
| **Local Terraform state** | Remote state solves two problems: concurrent access and durability. Only the second applies here, since I am the only operator and Terraform never runs in CI. | No locking, no versioning. I backed the state file up by hand. |
| **Terraform not run in CI** | The brief asks for build, test and deploy on merge. Infrastructure changes are rare and worth a human running them. | Infrastructure drift is not caught automatically |
| **One CloudWatch alarm** | The brief said a fully wired monitoring stack was not expected, only a plan. A working alarm plus a plan is stronger evidence than a plan alone. | No RDS alarms and no synthetic checks yet — both are in the TODO list |

## How to deploy

### Prerequisites

- AWS credentials with permission to create the resources below
- Terraform >= 1.12
- Docker
- The AWS Session Manager plugin, for reaching the maintenance host

### Why deployment is not a single command

Terraform creates the infrastructure and stops there. Two things are
written by an operator instead, and both are deliberate:

- **The container image.** An image is a build artifact, not declarative
  state. Terraform has no business producing one.
- **The value inside the connection-string secret.** RDS generates the
  master password and keeps it in its own secret. If Terraform wrote the
  application's connection string, it would have to read that password
  first, and the password would land in state — which is exactly what
  `manage_master_user_password` exists to prevent.

So the first apply succeeds with tasks failing to start. That is the
expected intermediate state, not something to debug.

### 1. Apply

```bash
cd terraform
terraform init
terraform plan          # about 54 resources
terraform apply
```

RDS takes most of the time; the whole apply is around 15 minutes.

### 2. Push the first image

```bash
eval "$(terraform output -raw ecr_login_command)"

REPO=$(terraform output -raw ecr_repository_url)
docker build -t "$REPO:bootstrap" ..
docker push "$REPO:bootstrap"
```

The repository uses immutable tags, so this tag can be pushed only once.
To rebuild, push a new tag and update `ecr_image_tag` in
`terraform.tfvars`.

### 3. Write the connection string

```bash
MASTER=$(terraform output -raw rds_master_secret_arn)
aws secretsmanager get-secret-value --secret-id "$MASTER" \
  --query SecretString --output text
# -> {"username":"wallet","password":"..."}

ENDPOINT=$(terraform output -raw rds_endpoint)

aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw db_url_secret_name)" \
  --secret-string 'postgres://wallet:PASSWORD_HERE@HOST:5432/wallet?sslmode=no-verify'
```

`sslmode=no-verify` is required. RDS enforces TLS, and node-postgres does
not enable it unless told to — see [Security](#security).

### 4. Start the tasks

```bash
aws ecs update-service \
  --cluster "$(terraform output -raw ecs_cluster_name)" \
  --service "$(terraform output -raw ecs_service_name)" \
  --force-new-deployment

aws ecs wait services-stable \
  --cluster "$(terraform output -raw ecs_cluster_name)" \
  --services "$(terraform output -raw ecs_service_name)"
```

ECS decides to roll out when the task definition revision changes. Here
the revision did not change — what changed was the content behind it, so
the deployment has to be forced. This is also why the pipeline tags
images by commit SHA: every deployment becomes a real revision change and
nothing has to be forced.

### 5. Load the schema

`db/schema.sql` is not copied into the image, so it cannot be applied
from the container. Port forwarding brings RDS to a local port, so the
file stays in the repository and `psql` runs locally.

```bash
BASTION=$(terraform output -raw bastion_instance_id)
ENDPOINT=$(terraform output -raw rds_endpoint)

aws ssm start-session --target "$BASTION" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${ENDPOINT%:*}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"
```

In a second terminal:

```bash
psql 'postgres://wallet:PASSWORD_HERE@localhost:15432/wallet' -f db/schema.sql
```

The schema is idempotent — `CREATE TABLE IF NOT EXISTS` plus
`ON CONFLICT DO NOTHING` — so running it twice is harmless and no
migration state table is needed.

Alternatively, open a shell on the maintenance host and use the
`db-connect` helper, which reads the connection string from Secrets
Manager itself so no password is typed:

```bash
aws ssm start-session --target "$BASTION"
db-connect -c "SELECT * FROM wallet_balances;"
```

### 6. Configure the pipeline

```bash
terraform output -raw github_deploy_role_arn
```

Store it under **Settings → Secrets and variables → Actions → Variables**
as `AWS_ROLE_ARN`. It is a variable rather than a secret because an ARN
is an identifier, not a credential. No AWS key is stored anywhere.

### Tearing down

```bash
terraform destroy
```

State is local, so back up `terraform.tfstate` before deleting the
working directory. Without it these resources are orphaned and still
billable, and Terraform can no longer remove them.

---

## Verification

Everything below was run against the deployed environment. Screenshots
are in `docs/evidence/`.

**Endpoints, through the internal load balancer, from the maintenance
host:**

```
GET /health              200  {"status":"ok","service":"wallet-balance-service","uptime":559}
GET /ready               200  {"status":"ready"}
GET /balance/user-001    200  {"user_id":"user-001","available_balance":"4250.00","currency":"THB"}
GET /balance/user-999    404
```
![Endpoints verified](docs/evidence/01-endpoints-verified.png)


`/ready` returning 200 is the one that matters: it runs `SELECT 1`
against RDS, so it proves the whole path works — security groups, the
secret, the network, and TLS.

![Database seeded](docs/evidence/02-database-seeded.png)

**Infrastructure:**

```
Apply complete! Resources: 54 added, 0 changed, 0 destroyed.
```
![ECS service running](docs/evidence/04-ecs-service-running.png)


**Pipeline:** both jobs green, ECS service reporting
`rolloutState=COMPLETED` with 2/2 tasks running, and the task definition
at revision 3 with an image tagged by commit SHA rather than `latest`.

## CI/CD

One workflow, `.github/workflows/deploy.yml`, with two jobs.

| Job | Runs on | Does |
|---|---|---|
| `test` | every push and pull request | `npm ci`, then `npm test` |
| `deploy` | pushes to `main` only | build, push to ECR, register a new task definition revision, update the service |

`deploy` has `needs: test`, so a failing test stops the deployment.

![Pipeline green](docs/evidence/03-github-actions-green.png)


### Why two jobs

The OIDC trust policy is pinned to `refs/heads/main`. A pull request
cannot obtain AWS credentials at all — that is the intent, not a
limitation. Splitting the jobs means a pull request still gets test
feedback without being able to touch AWS.

### Who owns what

| | Terraform | Pipeline |
|---|---|---|
| Scope | VPC, RDS, ECR, ECS, IAM, task definition revision 1 | the `image` field, nothing else |
| Runs | when I run it | every merge to `main` |

The ECS service has `lifecycle { ignore_changes = [task_definition] }`.
Without it, the next `terraform apply` would see the service on revision
7 while state says revision 1, and quietly roll the image backwards.

This split also limits the blast radius. The deploy role can push to one
ECR repository and update one ECS service. It cannot reach the VPC, the
database, or any secret. If the pipeline is compromised, that is the
whole reach.

### Notable details

**No `services: postgres` block.** I read the application code first.
`app.listen` is guarded by `require.main === module`, and the connection
pool is built lazily inside `getPool()`, which `/health` never calls. The
test suite opens no TCP connection to a database, so a service container
would only make CI slower. The `test` job runs in about 19 seconds.

**Images are tagged with the commit SHA, never `latest`.** A fixed tag
makes every task definition revision identical, so ECS has nothing to
roll out. It also breaks traceability from a running task back to a
commit. The ECR repository is set to immutable tags, so a tag cannot be
quietly repointed at different content.

![Task definition revision](docs/evidence/05-task-definition-revision.png)


**The task definition is pulled fresh from AWS on every run**, not
committed to the repository. A committed copy goes stale as soon as
Terraform changes anything, and would then overwrite it. `describe-task-definition`
returns fields that `register-task-definition` rejects, so they are
stripped with `jq` before the file is used.

**`wait-for-service-stability: true`.** Without it the job goes green as
soon as the deployment is requested, even if the new tasks fail to start.
The deploy step takes about five minutes because it actually waits.

### One problem worth writing down

The first pipeline run failed at `Configure AWS credentials` with
`Not authorized to perform sts:AssumeRoleWithWebIdentity`, even though the
repository, the branch and the role ARN were all correct.

Rather than guess, I looked at what AWS actually received. CloudTrail
recorded the subject claim as:

```
repo:NatsumachiAria@73279182/wallet-balance-service@1356771410:ref:refs/heads/main
```

GitHub appends an immutable numeric id to both the owner and the
repository name, so that renaming a repository cannot inherit the old
name's trust. My `StringEquals` condition was matching the documented
shape rather than the shape actually sent.

I changed it to `StringLike` with wildcards over the ids only:

```hcl
values = ["repo:${var.github_owner}*/${var.github_repo_name}*:ref:refs/heads/${var.github_branch}"]
```

The branch is still matched exactly, so a fork or any other branch still
cannot assume the role. The owner and repository are separate variables
because the wildcard has to sit between them.

## Security

The brief asked for secrets management and at least one concrete
least-privilege control, with the reasoning made explicit. This section
is written as "what it actually prevents" rather than "what I turned on",
because a list of enabled features does not say much on its own.

### Secrets

There are two secrets, and the split is the point.

**1. The RDS master password.** Created and owned by RDS through
`manage_master_user_password = true`. There is no `password` argument
anywhere in the Terraform. The result is that no password appears in
state, in a plan output, in CI logs, or in this repository.

**2. The application connection string**, `wallet/database-url`. The
application reads a single `DATABASE_URL`, so it needs the full string —
host, user and password together. Terraform declares this secret but
**not its value**: there is no `aws_secretsmanager_secret_version`
resource. Writing the value through Terraform would mean reading the
password from secret 1 first, and that password would land in state,
undoing the first decision.

So Terraform owns the address and an operator writes the value once
during bootstrap. The empty resource in `secrets.tf` is deliberate.

The ECS task never calls AWS. The **execution role** exchanges the ARN
for the value at task startup, before the container process begins, and
injects it as an environment variable. The application only reads
`process.env`.

This is visible in the first deployment attempt: tasks would not start at
all, with `ResourceNotFoundException ... for staging label AWSCURRENT`.
The secret existed but had no version yet. The container was never
created — which is exactly how the injection is supposed to work.

### Least-privilege controls

| Control | What it actually prevents |
|---|---|
| RDS in private subnets | Unreachable from the internet even if the password is known |
| Internal ALB | The unauthenticated `/balance` endpoint has no public entry point at all |
| `publicly_accessible = false` on RDS | A second barrier at the instance, in case a route to an internet gateway is ever added by mistake |
| Security group rules reference other security groups, never CIDR ranges | Something else launched into the same subnet still cannot reach the database. Access is granted by identity, not by address. |
| The database security group has **no egress rules** | A compromised database has no outbound path to send data over |
| The maintenance host has **no inbound rules and no key pair** | No port 22 to scan and no key to lose. The SSM agent dials out, so nothing dials in. |
| IMDSv2 required on the maintenance host | An SSRF bug on that host cannot be used to read its instance credentials |
| Execution role scoped to one secret ARN, not `*` | If that role leaks, it can read that one secret and no other secret in the account |
| Task role carries only three `ssmmessages` actions | I checked the code: the application never calls an AWS API. If the container is compromised, there are no credentials for S3, DynamoDB or any secret. |
| OIDC trust pinned to `refs/heads/main` | A fork, or a push to any other branch, cannot obtain deploy credentials |
| No AWS access keys stored anywhere | Nothing long-lived to leak or rotate |
| Deploy role limited to one ECR repository and one ECS service | A compromised pipeline cannot touch the network, the database, or any secret |
| ECR immutable tags | A tag cannot be silently repointed at different image content |

The two I would point at first are the security group references and the
task role. Referencing a security group instead of a CIDR range means the
rule follows identity rather than address, so it keeps holding as the
account grows. And the task role is small because I read the application
before writing it — most of the time this role gets a broad managed
policy attached without anyone checking whether the code needs it.

### TLS to the database — found during verification

After the first successful deployment, `/health` returned 200 but
`/ready` returned 503:

```
no pg_hba.conf entry for host "10.0.11.29", user "wallet",
database "wallet", no encryption
```

The last two words are the clue. RDS enforces TLS by default, and the two
clients disagree about what to do about that:

| Client | Default | Result |
|---|---|---|
| `psql` (libpq) | `sslmode=prefer` — negotiates TLS on its own | connected |
| `pg` (node-postgres) | does not enable TLS unless told | rejected |

My maintenance host connected fine while the application did not, using
the same credentials. Testing only with `psql` would have hidden this.

I fixed it in the connection string rather than in the application code,
since the string is already injected as a secret — no rebuild and no new
image:

```
postgres://wallet:...@host:5432/wallet?sslmode=no-verify
```

`no-verify` encrypts the connection but does not validate the certificate
chain. That is a gap, and it is in the TODO list: for production I would
ship the RDS CA bundle and move to `verify-full`, because encryption
without verification still leaves an in-path attacker able to impersonate
the database.

### Known weaknesses

- **Error messages leak connection details.** `/ready` and `/balance`
  return the raw `pg` error, which includes the host, port and database
  name — on an endpoint with no authentication. The 503 quoted above is
  a live example. Application code was out of scope, so this is
  documented rather than fixed.
- **Task egress is open.** The Fargate tasks need ECR, Secrets Manager
  and CloudWatch, which are public AWS endpoints reached through NAT
  because the interface VPC endpoints are not deployed. Narrowing egress
  by port would be guesswork until those endpoints exist. The control
  that matters here is ingress: the database accepts connections from
  the app and maintenance host security groups only.
- **`sslmode=no-verify`**, as described above.

## Assumptions

The brief left some things open. These are the calls I made and why.

| Assumption | Reasoning |
|---|---|
| The service is internal, not public | `GET /balance/:userId` has no authentication. Exposing it would publish account balances to anyone who could guess a user id. If it were meant to be public, the missing piece is authentication in the application, not a public load balancer. |
| One environment is enough | The brief asks for a working deployment, not a promotion path. Adding staging would have cost time without demonstrating anything new. |
| No custom domain or TLS certificate | The load balancer is internal and there is no domain to attach. An HTTPS listener would have been decorative here. |
| Traffic is low and steady | A single-key lookup over three rows. Two tasks are for deployment continuity, not capacity, and there is no autoscaling. |
| The reviewer wants to read the code, not use a live URL | The brief asks for a repository link. I applied the stack, verified it, captured evidence, and destroyed it rather than leaving a NAT gateway running. |
| Application code is out of scope | The brief says so explicitly. The Dockerfile is not application code — it is part of the deployment — so I did change that. |

---

## What I would change for production

This service holds financial balances, so the bar is different from a
take-home.

| Now | Production |
|---|---|
| Single-AZ RDS | Multi-AZ, plus a read replica if the read path grows. Restores should be rehearsed, not assumed. |
| One NAT gateway | One per availability zone. It is the only real single point of failure in this network. |
| `sslmode=no-verify` | Ship the RDS CA bundle and use `verify-full`. Encryption without verification still allows an in-path attacker to impersonate the database. |
| Schema applied by hand | A versioned migration tool running as a pipeline stage before deploy, using a role that can perform DDL but cannot read wallet data. |
| Raw driver errors returned to the client | Log the detail, return a generic message. Right now the host, port and database name leak on an unauthenticated endpoint. |
| Secret rotation does not reach running tasks | ECS injects secrets at task startup, so a rotated password is only picked up on redeploy. Production needs a rotation event that triggers one. |
| Open egress from the tasks | Interface VPC endpoints for ECR, Secrets Manager and CloudWatch, then egress narrowed to those plus the database. |
| One CloudWatch alarm | RDS alarms, a synthetic check against `/ready`, and alarms routed somewhere a human is actually paged. |
| No authentication on `/balance` | Balances are personal financial data. At minimum, authentication and an audit trail of who read what. |
| Local Terraform state | S3 with native locking and versioning. The locking matters for a team; the versioning matters more, because losing state does not lose infrastructure — it loses the ability to manage or remove it. |
| Terraform run by hand | Plan on pull request, apply on merge, with a human approving the plan. |
| Maintenance host exists | It exists only because schema loading is manual. Once migrations move into the pipeline, it goes away. |

---

## Documented TODOs

Things I knowingly did not do inside the time box.

| TODO | Why it was deferred |
|---|---|
| `sslmode=verify-full` | Needs the RDS CA bundle in the image and a change to the application's database client, which the brief excludes from assessment |
| Interface VPC endpoints | Would also let task egress be narrowed. A larger change than it looks, and the S3 gateway endpoint already covers the expensive path — ECR image layers. |
| Suppressing driver errors in responses | Application code, out of scope |
| Synthetic check against `/ready` | Level three of the monitoring plan. Levels one and two — logs and a 5XX alarm — are in place. |
| RDS-level alarms | Same reasoning. The 5XX alarm already fires on the failure mode that matters most. |
| SNS subscription | The topic exists and the alarm publishes to it, but subscribing an email endpoint needs a manual confirmation, so it cannot be finished in Terraform alone. |
| HTTPS listener | No domain and no certificate for an internal load balancer |
| Automatic rollback on failed deployment | ECS deployment circuit breaker is off. With `wait-for-service-stability` the pipeline fails loudly instead, which is enough to notice; automatic rollback is the next step. |
| Terraform in CI | The brief did not ask for it, and infrastructure changes here are rare enough to be worth a human running them |
| Removing the maintenance host | Tied to moving migrations into the pipeline |