variable "aws_region" {
  description = "AWS region where the state bucket and lock table will be created"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state (e.g. mycompany-voting-app-tfstate)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name (lowercase, hyphens allowed, 3-63 characters)."
  }
}

variable "lock_table_name" {
  description = "DynamoDB table name used for state locking"
  type        = string
  default     = "terraform-state-lock"
}
