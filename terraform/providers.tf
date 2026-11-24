# providers.tf
# Configures the AWS provider. Credentials are NOT set here: Terraform reads
# them from your environment (AWS_PROFILE, `aws configure`, SSO, or
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY environment variables).

provider "aws" {
  region = var.aws_region

  # Applied automatically to every taggable resource that supports provider tags.
  default_tags {
    tags = local.common_tags
  }
}