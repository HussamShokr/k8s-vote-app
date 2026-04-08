variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in MAJOR.MINOR format (e.g. 1.29)."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets where nodes and the control plane will run"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Whether to allow public access to the EKS API server endpoint"
  type        = bool
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Restrict to your office/VPN CIDR in production."
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for managed worker nodes"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes (floor for Cluster Autoscaler)"
  type        = number

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (ceiling for Cluster Autoscaler)"
  type        = number
}

variable "node_disk_size" {
  description = "EBS root volume size in GiB for each node"
  type        = number

  validation {
    condition     = var.node_disk_size >= 20
    error_message = "node_disk_size must be at least 20 GiB (EKS minimum)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
