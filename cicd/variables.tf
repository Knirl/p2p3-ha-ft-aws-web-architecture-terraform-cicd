variable "region" {
  description = "AWS region where CI/CD pipeline resources will be deployed."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name used for naming resources."
  type        = string
  default     = "p2p3"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "codebuild_compute_type" {
  description = "Compute environment type for CodeBuild containers."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "codebuild_image" {
  description = "Docker image used by CodeBuild. Using AWS Standard 5.0 image containing common CLI tools."
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:6.0"
}

variable "github_repository_id" {
  description = "GitHub repository formatted as 'owner/repo' (e.g. 'username/aws-project')."
  type        = string
}

variable "github_branch" {
  description = "Git branch to trigger the pipeline on commit pushes."
  type        = string
  default     = "main"
}

variable "code_connection_arn" {
  description = "ARN of the AWS codeconnection established with GitHub."
  type        = string
}

variable "approval_email" {
  description = "Email address to receive SNS notifications for the manual approval gate."
  type        = string
}

variable "tags" {
  description = "Default resource tags."
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Environment = "prod"
    Project     = "Project-3-CICD"
  }
}