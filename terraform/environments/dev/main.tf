# =============================================================================
# dev — root module
# Composes the vpc, eks, and k8s-addons modules into a complete environment.
# All environment-specific values come from terraform.tfvars.
# =============================================================================

module "vpc" {
  source = "../../modules/vpc"

  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name                         = local.cluster_name
  kubernetes_version                   = var.kubernetes_version
  vpc_id                               = module.vpc.vpc_id
  private_subnet_ids                   = module.vpc.private_subnet_ids
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  node_instance_type                   = var.node_instance_type
  node_desired_size                    = var.node_desired_size
  node_min_size                        = var.node_min_size
  node_max_size                        = var.node_max_size
  node_disk_size                       = var.node_disk_size
  tags                                 = local.common_tags
}

module "k8s_addons" {
  source = "../../modules/k8s-addons"

  nginx_ingress_version  = var.nginx_ingress_version
  metrics_server_version = var.metrics_server_version
  app_hostname           = var.app_hostname
  deploy_app             = var.deploy_app
  deploy_monitoring      = var.deploy_monitoring

  # Absolute paths are evaluated at plan time, before the working directory changes
  voting_app_chart_path  = "${path.module}/../../../helm"
  voting_app_values_file = "${path.module}/../../../helm/values-aws.yaml"
}
