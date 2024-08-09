# Credentials should be provided by using the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables.
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      owner     = var.owner
      workspace = terraform.workspace
      project   = var.project
      id        = random_string.setup.result
    }
  }
}

module "github_oidc" {
  source = "../../modules/github_oidc"

  oidc_github_repo = var.oidc_github_repo
  region           = var.region
  owner            = var.owner
  project          = var.project
}

resource "random_string" "setup" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project}-tfstate-${var.owner}-${random_string.setup.result}"

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "default" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# https://avd.aquasec.com/misconfig/aws/s3/avd-aws-0132/
# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.tfstate.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "default" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Create a DynamoDB table for locking the state file
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project}-tfstate-lock-${var.owner}-${random_string.setup.result}"
  hash_key     = "LockID"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "local_file" "setup_env" {
  content  = <<-EOT
    WORKSPACE=${terraform.workspace}
    BUCKET=${aws_s3_bucket.tfstate.bucket}
    DYNAMODB_TABLE=${aws_dynamodb_table.tfstate_lock.id}
    REGION=${var.region}
  EOT
  filename = ".env"
}

resource "local_file" "ecs_env" {
  content  = <<-EOT
    BUCKET=${aws_s3_bucket.tfstate.bucket}
    DYNAMODB_TABLE=${aws_dynamodb_table.tfstate_lock.id}
    REGION=${var.region}
  EOT
  filename = "../ecs/.env"
}
