# =============================================================================
# EKS Cluster
# Delegates to terraform-aws-modules/eks which handles:
#   - Control plane, OIDC provider, security groups
#   - Managed node group with auto-scaling tags
#   - EKS managed add-ons (coredns, kube-proxy, vpc-cni, ebs-csi-driver)
# =============================================================================
module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  # OIDC provider enables IRSA (IAM Roles for Service Accounts) — no static keys
  enable_irsa = true

  # AWS-managed add-ons — patched by AWS; pin versions in tfvars for reproducibility
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }

    # vpc-cni must be ready before nodes join so pods get IP addresses immediately
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }

    # EBS CSI driver uses IRSA — the IAM role is created below in this file
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  eks_managed_node_groups = {
    default = {
      name           = "${var.cluster_name}-nodes"
      instance_types = [var.node_instance_type]
      disk_size      = var.node_disk_size

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      ami_type   = "AL2_x86_64"
      subnet_ids = var.private_subnet_ids

      labels = { role = "application" }

      # Cluster Autoscaler discovers node groups via these tags
      tags = merge(var.tags, {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      })
    }
  }

  # Grants the Terraform IAM caller cluster-admin so Helm/k8s resources apply cleanly
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}

# =============================================================================
# IRSA — IAM Role for EBS CSI Driver
# The EKS cluster must exist before we can obtain the OIDC provider ARN, so
# this role depends on module.eks_cluster. Terraform resolves this ordering
# because the EKS cluster is created before the addon is installed.
# =============================================================================
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks_cluster.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks_cluster.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks_cluster.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
