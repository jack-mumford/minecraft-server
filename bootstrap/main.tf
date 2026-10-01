# One-time setup, applied locally with your own AWS credentials. Creates the
# resources GitHub Actions needs and that must outlive the server stack:
# Terraform state bucket, world-backup bucket, and the OIDC role for Actions.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "region" {
  description = "AWS region for the buckets (use the same region as the server)."
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name prefix; must match the server stack's `name` variable."
  type        = string
  default     = "minecraft"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the deploy role."
  type        = string
  default     = "jack-mumford/minecraft-server"
}

variable "github_repository_immutable" {
  description = <<-EOT
    Repository in GitHub's immutable OIDC subject form (owner@owner_id/name@repo_id), used when the
    repo has use_immutable_subject enabled. Find it with:
    gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
    Set to null to trust only the name-based subject.
  EOT
  type        = string
  default     = "jack-mumford@58003173/minecraft-server@1398763133"
  nullable    = true
}

variable "github_branch" {
  description = "Branch whose workflows may assume the deploy role."
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one."
  type        = bool
  default     = false
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  oidc_url    = "token.actions.githubusercontent.com"
  oidc_arn    = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  ami_ssm_arn = "arn:aws:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*"

  # Accept both GitHub subject formats: name-based and immutable (IDs stay fixed across renames).
  github_subjects = compact([
    "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}",
    var.github_repository_immutable == null ? "" : "repo:${var.github_repository_immutable}:ref:refs/heads/${var.github_branch}",
  ])
}

# --- Buckets ---

resource "aws_s3_bucket" "state" {
  bucket = "${var.name}-tfstate-${local.account_id}"
}

resource "aws_s3_bucket" "backups" {
  bucket = "${var.name}-backups-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "cleanup"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# --- GitHub Actions OIDC role ---

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://${local.oidc_url}"
}

resource "aws_iam_role" "github_actions" {
  # Deliberately not prefixed with "${var.name}-": the role may manage
  # "${var.name}-*" IAM roles and must not be able to modify itself.
  name = "github-actions-${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = local.github_subjects
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Ec2"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
      },
      {
        Sid    = "ServerIam"
        Effect = "Allow"
        Action = "iam:*"
        Resource = [
          "arn:aws:iam::${local.account_id}:role/${var.name}-*",
          "arn:aws:iam::${local.account_id}:instance-profile/${var.name}-*",
        ]
      },
      {
        Sid      = "AmiLookup"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = local.ami_ssm_arn
      },
      {
        Sid    = "RunBackups"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ssm:${var.region}::document/AWS-RunShellScript",
          "arn:aws:ec2:${var.region}:${local.account_id}:instance/*",
        ]
      },
      {
        Sid      = "ReadBackupResults"
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:DescribeInstanceInformation"]
        Resource = "*"
      },
      {
        Sid      = "StateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      },
    ]
  })
}

# --- Static server address ---
# Kept here, not in the server stack, so Destroy doesn't release it: Xaero's
# World Map and Minimap store each player's map under the server address.

import {
  to = aws_eip.minecraft
  id = "eipalloc-0ebb6edbfd02969f1"
}

resource "aws_eip" "minecraft" {
  domain = "vpc"

  tags = { Name = var.name }

  lifecycle {
    prevent_destroy = true
    # Attached/detached by the server stack.
    ignore_changes = [instance, network_interface, associate_with_private_ip]
  }
}

output "server_address" {
  description = "Permanent address players connect to."
  value       = aws_eip.minecraft.public_ip
}

# --- Values to store as GitHub repository variables ---

output "github_variables" {
  description = "Set these as repository variables (Settings → Secrets and variables → Actions → Variables)."
  value = {
    AWS_REGION      = var.region
    AWS_ROLE_ARN    = aws_iam_role.github_actions.arn
    TF_STATE_BUCKET = aws_s3_bucket.state.bucket
    BACKUP_BUCKET   = aws_s3_bucket.backups.bucket
  }
}
