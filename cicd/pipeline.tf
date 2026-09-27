# ---------------------------------------------------------------------------
# S3 Bucket for CodePipeline Artifacts
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${local.name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(var.tags, {
    Name = "${local.name}-artifacts"
  })
}

data "aws_caller_identity" "current" {}

# Enable Server-Side Encryption for the Pipeline S3 Bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts_crypto" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block Public Access to the Artifact Bucket
resource "aws_s3_bucket_public_access_block" "pipeline_artifacts_block_public" {
  bucket                  = aws_s3_bucket.pipeline_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# SNS Topic & Email Subscription for Manual Approval Gate
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "approval" {
  name = "${local.name}-approval-topic"

  tags = merge(var.tags, {
    Name = "${local.name}-approval-topic"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.approval.arn
  protocol  = "email"
  endpoint  = var.approval_email
}

# ---------------------------------------------------------------------------
# CodePipeline IAM Service Role & Trust Policy
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "codepipeline_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${local.name}-pipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name}-pipeline-role"
  })
}

# CodePipeline Permissions Policy Document
data "aws_iam_policy_document" "codepipeline_policy" {
  # 1. Access to the Pipeline S3 Artifact Bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.pipeline_artifacts.arn,
      "${aws_s3_bucket.pipeline_artifacts.arn}/*"
    ]
  }

  # 2. Access to GitHub via CodeConnections formerly (CodeStar Connections)
  statement {
    effect = "Allow"
    actions = [
      "codestar-connections:UseConnection",
      "codeconnections:UseConnection"           # Including both actions in your IAM policy ensures your pipeline works regardless of whether your Connection ARN
    ]                                           # uses the old codestar-connections format or the new codeconnections format.
    resources = [var.code_connection_arn]
  }

  # 3. Access to trigger Plan & Apply CodeBuild Projects
  statement {
    effect = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
    resources = [
      aws_codebuild_project.plan.arn,
      aws_codebuild_project.apply.arn
    ]
  }

  # 4. Access to Publish to SNS Approval Topic
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.approval.arn]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "${local.name}-pipeline-policy"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}

# ---------------------------------------------------------------------------
# AWS CodePipeline Resource
# ---------------------------------------------------------------------------
resource "aws_codepipeline" "pipeline" {
  name     = "${local.name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # STAGE 1: Source (GitHub Connection)
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection" #WS kept CodeStarSourceConnection as the internal action provider name in the API
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn        = var.code_connection_arn
        FullRepositoryId     = var.github_repository_id
        BranchName           = var.github_branch
        DetectChanges        = "true"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  # STAGE 2: Terraform Plan & Security Checks
  stage {
    name = "Terraform-Plan"

    action {
      name            = "Plan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      output_artifacts = ["plan_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.plan.name
      }
    }
  }

  # STAGE 3: Manual Approval Gate
  stage {
    name = "Approval-Gate"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.approval.arn
        CustomMessage   = "A new infrastructure change is ready for review. Check the CodeBuild plan output before approving."
      }
    }
  }

  # STAGE 4: Terraform Apply
  stage {
    name = "Terraform-Apply"

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["plan_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.apply.name
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-pipeline"
  })
}