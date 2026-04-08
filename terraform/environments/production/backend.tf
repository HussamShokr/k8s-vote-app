# =============================================================================
# Remote State Backend — S3 + DynamoDB
#
# SETUP STEPS:
#   1. Run `terraform -chdir=../../bootstrap apply` first to create the bucket
#      and DynamoDB table.
#   2. Replace "your-terraform-state-bucket" below with the output bucket name.
#   3. Run `terraform init` — Terraform will prompt to migrate local state.
#
# The backend block cannot use variables, so values are static here.
# =============================================================================
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket" # replace after bootstrap
    key            = "voting-app/production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
