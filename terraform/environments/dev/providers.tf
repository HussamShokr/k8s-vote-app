# =============================================================================
# Provider Configuration
#
# The Kubernetes and Helm providers are configured with EKS cluster credentials
# obtained from the eks module output. This works because Terraform evaluates
# providers lazily — on first apply, the EKS cluster is created, then the
# Kubernetes/Helm providers are initialised with the real credentials.
#
# NOTE: When running `terraform destroy`, use:
#   terraform destroy -target=helm_release.voting_app  (first)
#   terraform destroy                                   (then all)
# to avoid provider connectivity errors during teardown.
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
