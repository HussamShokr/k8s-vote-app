# =============================================================================
# Bootstrap — creates the S3 bucket and DynamoDB table used as the Terraform
# remote state backend for all environments.
#
# Run ONCE before initialising any environment:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var="state_bucket_name=my-unique-bucket-name"
#
# After apply, copy the output bucket name into each environment's backend.tf.
# State for bootstrap itself is stored locally (.terraform/terraform.tfstate).
# =============================================================================
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "voting-app"
      ManagedBy = "terraform"
      Purpose   = "terraform-state-backend"
    }
  }
}
