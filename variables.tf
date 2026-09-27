# ---------------------------------------------------------------------------
# Identity — these two feed every module's naming/tagging convention
# (${project_name}-${environment}-...) and get merged into common_tags.
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Short name used as a prefix for all resource names/tags. Lowercase letters, numbers, and hyphens only — this also becomes part of the S3 bucket name in the storage module, which has its own character restrictions."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Controls several safety-vs-convenience defaults elsewhere (e.g. database's skip_final_snapshot is tied to this being \"prod\" or not)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "AWS region to deploy into. Used by the provider block in providers.tf, not passed to any module directly — resources inherit it automatically from the provider configuration."
  type        = string
  default     = "ap-southeast-1"
}

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications (observability module). AWS sends a confirmation link here after the first apply — see the observability module's comments."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

# ---------------------------------------------------------------------------
# Networking (vpc module)
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# Defaults assume us-east-1. If deploying elsewhere, override this to match
# real AZs in that region (e.g. us-west-2a/us-west-2b) — the vpc module's
# own validation only checks that at least 2 AZs are given, not that they
# exist in the target region.
variable "azs" {
  description = "Availability Zones for the public/private subnets. Must be the same length as public_subnet_cidrs and private_subnet_cidrs."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Must be the same length as azs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. Must be the same length as azs."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# Off by default: saves the NAT Gateway's hourly + data processing charges
# for dev/portfolio runs. Turn on if compute needs outbound internet access
# (e.g. `dnf update` in the user data script actually reaching the internet,
# or SSM needing an outbound path — see the compute module's SSM comments).
variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnet outbound internet access."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period before the KMS key is permanently deleted after a destroy (7-30 days, AWS-enforced range)."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# Database (database module)
# ---------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance size."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for the RDS instance, in GB."
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "db_name" {
  description = "Name of the initial database created inside the RDS instance."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Master username for the RDS instance. The password itself is always generated, never set here."
  type        = string
  default     = "admin"
}

# Off by default for the same reason NAT is off: this roughly doubles RDS
# cost. Turn on to actually exercise the failover behavior for the
# portfolio demo (see the v1 build log's failover verification steps —
# same idea, now controlled by a variable instead of being permanently on).
variable "rds_multi_az" {
  description = "Whether to enable Multi-AZ standby replication and automatic failover for RDS."
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated RDS backups."
  type        = number
  default     = 7
}

variable "secret_recovery_window_in_days" {
  description = "Waiting period before a deleted Secrets Manager secret is permanently removed. 0 = immediate (convenient for dev teardown)."
  type        = number
  default     = 0
}

variable "db_deletion_protection" {
  description = "Whether to enable RDS deletion protection."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Storage (storage module)
# ---------------------------------------------------------------------------

# Off by default: falls back to the storage module's own AES256 default,
# which needs no KMS key at all. Turn on to use the shared CMK instead (see
# main.tf — this is what decides whether module.kms.key_arn actually gets
# passed to the storage module or not).
variable "storage_use_kms" {
  description = "Whether the S3 bucket should use the shared KMS key (SSE-KMS) instead of the default AES256 (SSE-S3)."
  type        = bool
  default     = true
}

# This is the master switch for the whole "wire S3 into compute" stretch
# goal. Off by default so the base build stays minimal; flip on to see the
# IAM policy get created in storage AND attached in compute in the same
# apply.
variable "enable_ec2_s3_access" {
  description = "Whether to create and attach an IAM policy granting EC2 instances read/write access to the S3 bucket."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Compute (compute module)
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

# null lets the compute module auto-resolve the latest Amazon Linux 2023 AMI
# itself — see that module's data "aws_ami" block. Override only if you need
# a specific/pinned AMI.
variable "ami_id" {
  description = "AMI ID override. Leave null to auto-resolve the latest Amazon Linux 2023 AMI."
  type        = string
  default     = null
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Initial desired instance count. Ignored on later applies — see the compute module's lifecycle block."
  type        = number
  default     = 2
}

variable "target_cpu_utilization" {
  description = "Target average CPU percentage for the ASG's target-tracking scaling policy."
  type        = number
  default     = 50
}

# ---------------------------------------------------------------------------
# ALB (alb module)
# ---------------------------------------------------------------------------

variable "health_check_path" {
  description = "Path the ALB target group health check requests."
  type        = string
  default     = "/"
}

variable "alb_deletion_protection" {
  description = "Whether to enable ALB deletion protection."
  type        = bool
  default     = false
}
