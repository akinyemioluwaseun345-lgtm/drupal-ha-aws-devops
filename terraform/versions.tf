# versions.tf
# Pins the Terraform CLI version and the providers this project uses.
# Pinning keeps your results repeatable: everyone running this code gets
# compatible provider versions.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Creates every AWS resource (VPC, EC2, RDS, EFS, ALB, IAM ...).
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Generates the random database password.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}