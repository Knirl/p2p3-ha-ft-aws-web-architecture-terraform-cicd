# ---------------------------------------------------------------------------
# Copy this file to terraform.tfvars and fill in real values.
# terraform.tfvars itself is gitignored — this .example file is the one
# that gets committed, so anyone cloning the repo knows what to set without
# ever seeing your actual values.
# ---------------------------------------------------------------------------

# =============================================================================
# REQUIRED — these two have no default in variables.tf; terraform plan will
# fail with "no value for required variable" until they're set.
# =============================================================================

project_name = "p2p3"            # lowercase letters, numbers, hyphens only
alert_email  = "your-email@example.com" # AWS sends a confirmation link here after apply

# =============================================================================
# EVERYTHING BELOW HAS A DEFAULT IN variables.tf. Uncomment and change only
# what you actually want to override — leaving a line commented out means
# "use the default," not "use nothing."
# =============================================================================

# ---------------------------------------------------------------------------
# Identity / region
# ---------------------------------------------------------------------------

environment = "prod"            # dev | staging | prod
region      = "ap-southeast-1" # Singapore

# ---------------------------------------------------------------------------
# Networking — if you change region, azs almost certainly needs to change
# too (AZ names are region-specific, e.g. us-west-2a instead of us-east-1a).
# ---------------------------------------------------------------------------

vpc_cidr             = "10.0.0.0/16"
azs                  = ["ap-southeast-1a", "ap-southeast-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# Costs real money per hour + data processing while on. Needed if compute
# should have outbound internet access (e.g. package installs, SSM).

enable_nat_gateway = true

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

kms_key_deletion_window_in_days = 7 # AWS-enforced range: 7-30

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

db_instance_class              = "db.t3.micro"
db_allocated_storage           = 20
db_engine_version              = "8.0"
db_name                        = "p2v2db"
db_master_username             = "admin" # password is always generated, never set here
db_backup_retention_period     = 7
db_deletion_protection         = false
secret_recovery_window_in_days = 0 # 0 = immediate delete

# Roughly doubles RDS cost — turn on to actually exercise failover.
rds_multi_az = true

# ---------------------------------------------------------------------------
# Storage — the "wire S3 into compute" stretch goal is enable_ec2_s3_access.
# ---------------------------------------------------------------------------

storage_use_kms      = true # false = SSE-S3 (AES256), true = SSE-KMS via the shared CMK
enable_ec2_s3_access = true # true creates + attaches an IAM policy so EC2 can read/write the bucket

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

instance_type          = "t3.micro"
ami_id                 = null # leave null to auto-resolve latest Amazon Linux 2023
asg_min_size           = 2
asg_max_size           = 4
asg_desired_capacity   = 2 # only used on first creation — see compute module's lifecycle block
target_cpu_utilization = 50

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------

health_check_path       = "/"
alb_deletion_protection = false
