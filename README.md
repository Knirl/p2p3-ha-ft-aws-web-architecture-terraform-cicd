# Project 2 — v2: Modular Terraform on AWS

A 3-tier web application (ALB → ASG of EC2 → RDS MySQL) built entirely with modular,
parameterized Terraform. This is the third iteration of this project:

- **v1** Terraform, but everything hardcoded in one flat configuration
- **v2** (this version) — rebuilt again as 8 composable modules with variables,
  validation, conditional logic, and a decoupled root wiring layer

## Architecture

![Architecture Diagram](./screenshots/project2-architecture-diagram.png)

Supporting services: KMS (shared encryption key), Secrets Manager (DB credentials),
S3 (local website storage), CloudWatch + SNS (alarms and dashboard), Systems Manager
(instance access — no SSH, no bastion host, no key pairs anywhere in this build).

## Module layout

| Module | Depends on | Produces |
|---|---|---|
| `vpc` | — | VPC, public/private subnets, IGW, optional NAT |
| `security` | `vpc` | 3 chained security groups (alb → ec2 → rds) |
| `kms` | — | One shared Customer Managed Key |
| `database` | `vpc`, `security`, `kms` | RDS MySQL, Secrets Manager secret |
| `storage` | `kms` (optional) | S3 bucket, optional EC2 access IAM policy |
| `compute` | `vpc`, `security`, `storage` (optional) | Launch template, ASG, IAM instance role |
| `alb` | `vpc`, `security` | ALB, target group, HTTP listener |
| `observability` | `alb`, `compute` | SNS topic, CloudWatch alarm + dashboard |

Every dependency in that table flows one direction only — no module references a
module below it in the table, and `compute`/`alb` never reference each other at
all (see **Decoupling** below).

## Key design decisions

**No SSH, no bastion host.** EC2 instances have no key pair and no inbound port 22
anywhere. Access is via AWS Systems Manager Session Manager, using an IAM role
(`AmazonSSMManagedInstanceCore`) instead of a key file. Requires `enable_nat_gateway`
on (or a VPC endpoint) since SSM needs an outbound path to the Systems Manager
service.

**IMDSv2 enforced.** The launch template's `metadata_options` require session
tokens (`http_tokens = "required"`) and cap the hop limit at 1 — closing off a
known SSRF pattern where a vulnerable app could otherwise be tricked into
fetching the instance's IAM credentials from the metadata service.

**Credentials never leave Secrets Manager.** The database module outputs
`secret_arn`, never a username or password. Anything that needs the actual
credentials reads them from Secrets Manager at runtime.

**Decoupled ASG ↔ ALB.** Neither the `compute` nor `alb` module references the
other. The connection is a single `aws_autoscaling_attachment` resource in root
`main.tf` — the only place in the whole configuration aware both modules exist.
Either module can be modified independently without touching the other's code.

**Lifecycle-aware autoscaling.** The ASG's `lifecycle { ignore_changes =
[desired_capacity] }` stops `terraform apply` from fighting the target-tracking
scaling policy by resetting instance count on every run.

**Environment-aware safety defaults.** `skip_final_snapshot` on RDS and
`deletion_protection` on both RDS and the ALB are tied to `var.environment`,
so `dev` stays fast to tear down while `prod` gets guardrails against accidental
deletion.

**Cost-conscious toggles.** `enable_nat_gateway`, `rds_multi_az`, and
`storage_use_kms` all default to `false` — every one of them adds real
per-hour or per-request AWS cost, so they're opt-in rather than baked in.

## Terraform concepts this project demonstrates

- **Module composition** with strictly one-directional dependencies, communicated
  only through `variable` (in) and `output` (out) — never a module reaching into
  another module's resources directly.
- **The decoupling pattern**: when two modules' resources need to reference each
  other, that connection is made by a resource at the *root* level, not inside
  either module (`aws_autoscaling_attachment`, IAM policy attachment for S3 access).
- **Type-constrained, validated variables** — `validation` blocks catch bad input
  (a malformed email, an invalid environment name, an S3-incompatible project name)
  at `plan` time instead of failing deep inside an `apply`.
- **Data sources vs. resources** — `aws_caller_identity`, `aws_ami`, and
  `aws_region` look up values that already exist, keeping modules portable across
  accounts and regions instead of hardcoding account IDs, AMI IDs, or region strings.
- **Conditional resource creation** with `count = var.flag ? 1 : 0`, used for the
  optional NAT Gateway, optional storage IAM policy, and dynamic route blocks.
- **`lifecycle.ignore_changes`** to prevent Terraform from reverting infrastructure
  drift that's *supposed* to happen (autoscaling adjusting instance count).
- **Remote state with native locking** — an S3 backend with `use_lockfile = true`,
  the modern replacement for the older S3 + separate DynamoDB table pattern.
- **Provider-level `default_tags`** layered with module-level resource tags, so
  every resource gets baseline tags automatically even if a module forgets an
  explicit `tags` argument on a specific resource.
- **Secrets handled correctly**: generated with `random_password`, stored in
  Secrets Manager encrypted with a Customer Managed KMS Key, and never exposed
  through a Terraform output.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — at minimum, set project_name and alert_email

# edit providers.tf — replace the backend "s3" bucket placeholder with your
# real state-bootstrap bucket name (backend blocks can't use variables)

terraform init
terraform plan
terraform apply
```

After apply, check the `app_url` output — refresh it a few times and the
"Served by instance" line should rotate across whatever instances the ASG is
currently running. Check your inbox for the SNS subscription confirmation
email before alarms will actually deliver.

## What's intentionally out of scope

- No HTTPS/TLS listener — no real domain to issue an ACM certificate against.
- No Kubernetes/EKS anywhere in this build (a deliberate correction — earlier
  drafts of the design notes referenced K8s-style subnet discovery tags that
  don't apply to this plain EC2/ASG/ALB architecture, and were removed).
- No SSH access path, by design — see **No SSH, no bastion host** above.


# Project 3: Automated CI/CD Deployment Pipeline using AWS Developer Tools with Terraform

# Split-State AWS & Terraform CI/CD Pipeline

An automated, Git-driven CI/CD pipeline built on AWS to deploy and manage root application infrastructure using Terraform, AWS CodePipeline, AWS CodeBuild, and AWS CodeConnections.

## Architecture Overview

This project separates operational management into two isolated Terraform state boundaries:

1. **Pipeline Infrastructure (`cicd/`):** Manages the CI/CD pipeline components (CodePipeline, CodeBuild projects, IAM service roles, S3 artifact buckets, and SNS approval topics).
2. **Application Infrastructure (Root Directory):** Manages core cloud architecture resources (VPC, EC2, RDS, Security Groups, and networking).

![Overview](./screenshots/project3-overview.png)

---

## Key Features

- **Split-State Architecture:** Completely decouples pipeline orchestration from application infrastructure to reduce blast radius and prevent state lock contention.
- **Strict Plan-to-Apply Guarantee:** The `Plan` stage generates a binary `tfplan` artifact that is stored in S3 and passed directly to the `Apply` stage, ensuring exact execution without plan drift.
- **Containerized Terraform Execution:** CodeBuild uses ephemeral Linux containers dynamically running standard Terraform (`1.10.0`) via tailored `buildspec.yml` configurations.
- **Manual SNS Approval Gate:** Pauses execution after plan creation and notifies administrators via email prior to applying changes to production resources.
- **Zero-Trust IAM Roles:** Eliminates hardcoded AWS access keys by leveraging IAM Service Roles with scoped permissions.

---

## Directory Structure

```
.
├── main.tf                 # Root application infrastructure (VPC, EC2, RDS, etc.)
├── variables.tf            # Root application variables
├── outputs.tf              # Root application outputs
│
└── cicd/                   # CI/CD Pipeline Infrastructure
    ├── main.tf             # CodePipeline & CodeBuild resources
    ├── iam.tf              # Fine-grained IAM roles and policies
    ├── variables.tf        # Pipeline configuration variables
    ├── terraform.tfvars    # Environment variable settings
    └── buildspecs/         # Container build specifications
        ├── plan.yml        # Terraform plan phase configuration
        └── apply.yml       # Terraform apply phase configuration
```

---

## Deployment Steps

### Step 1: Deploy Pipeline Infrastructure (`cicd/`)

1. Create an AWS CodeConnection in the AWS Console linking your GitHub repository.
2. Initialize and apply the `cicd/` directory locally once:

```bash
cd cicd
terraform init
terraform apply
```

### Step 2: Confirm Notification Subscription

1. Check the email inbox associated with your SNS approval variable.
2. Click **Confirm Subscription** on the AWS Notification email to receive approval prompts.

### Step 3: Trigger Automated Deployments via Git

Push any infrastructure changes to your target repository branch to trigger the pipeline:

```bash
git add .
git commit -m "Deploy application infrastructure via automated pipeline"
git push origin main
```

---

## Pipeline Execution Details

1. **Source Stage:** AWS CodeConnections monitors the target repository for push events and archives source code to the S3 artifact bucket.
2. **Plan Stage:** CodeBuild runs `buildspecs/plan.yml`, installs Terraform `1.10.0`, executes `terraform plan -out=tfplan`, and passes the plan artifact downstream.
3. **Approval Stage:** Execution pauses. An email is emitted via SNS. Review the execution output logs in CloudWatch and approve the gate in the CodePipeline console.
4. **Apply Stage:** CodeBuild runs `buildspecs/apply.yml` and executes `terraform apply tfplan` to modify live infrastructure.

---

## Destroying Infrastructure

To clean up resources properly without encountering RDS final snapshot or state bucket locks:

1. Empty application infrastructure via the pipeline or locally:
   ```bash
   terraform destroy
   ```
2. Remove the pipeline infrastructure:
   ```bash
   cd cicd
   terraform destroy
   ```