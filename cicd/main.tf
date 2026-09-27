

locals {
  name     = "${var.project_name}-${var.environment}" #standardized naming string prefix by interpolating your project name and environment variables.
}

# ---------------------------------------------------------------------------
# CloudWatch Log Groups for CodeBuild
# Setting explicit retention (e.g., 14 or 30 days) prevents unexpected costs.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "codebuild_plan" {
  name              = "/aws/codebuild/${local.name}-plan"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name = "${local.name}-plan-log-group"
  })
}

resource "aws_cloudwatch_log_group" "codebuild_apply" {
  name              = "/aws/codebuild/${local.name}-apply"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name = "${local.name}-apply-log-group"
  })
}

# ---------------------------------------------------------------------------
# Plan CodeBuild Project
# ---------------------------------------------------------------------------

resource "aws_codebuild_project" "plan" {
  name         = "${local.name}-plan"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = var.codebuild_compute_type
    image        = var.codebuild_image
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "cicd/buildspecs/plan.yml"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild_plan.name
      stream_name = "plan-execution"
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-plan"
  })
}

# ---------------------------------------------------------------------------
# Apply CodeBuild Project
# ---------------------------------------------------------------------------

resource "aws_codebuild_project" "apply" {
  name         = "${local.name}-apply"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = var.codebuild_compute_type
    image        = var.codebuild_image
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "cicd/buildspecs/apply.yml"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild_apply.name
      stream_name = "apply-execution"
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-apply"
  })
}