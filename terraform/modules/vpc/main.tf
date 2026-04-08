# =============================================================================
# VPC
# Delegates to the official terraform-aws-modules/vpc module which handles:
#   - Public + private subnets, route tables, IGW
#   - NAT Gateway(s) for outbound traffic from private subnets
#   - EKS-required subnet tags for auto-discovery by the LB controller
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # NAT Gateway configuration
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Required for EKS DNS resolution
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS subnet auto-discovery tags
  # Public subnets: internet-facing load balancers (ALB/NLB)
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  # Private subnets: nodes + internal load balancers + Cluster Autoscaler
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.cluster_name}"    = "shared"
    "k8s.io/cluster-autoscaler/enabled"            = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

  tags = var.tags
}
