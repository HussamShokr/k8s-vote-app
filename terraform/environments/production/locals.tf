locals {
  environment  = "production"
  project      = "voting-app"
  cluster_name = "${local.project}-${local.environment}-eks"

  # Applied to every resource via the AWS provider's default_tags
  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = "k8s-vote-app"
  }
}
