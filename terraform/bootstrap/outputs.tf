output "state_bucket_name" {
  description = "S3 bucket name — paste this into each environment's backend.tf"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket (for IAM policy references)"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "DynamoDB lock table name — paste this into each environment's backend.tf"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "backend_config_snippet" {
  description = "Paste this backend block into each environment's backend.tf"
  value       = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.terraform_state.id}"
      region         = "${var.aws_region}"
      encrypt        = true
      dynamodb_table = "${aws_dynamodb_table.terraform_state_lock.name}"
      # key = "voting-app/<environment>/terraform.tfstate"
    }
  EOT
}
