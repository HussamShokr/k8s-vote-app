variable "cluster_name" {
  description = "EKS cluster name — used to tag subnets for auto-discovery by the load balancer controller and Cluster Autoscaler"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "availability_zones" {
  description = "List of availability zones to span subnets across (minimum 2 for HA)"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ, EKS nodes run here"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ, internet-facing load balancers attach here"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cheaper, less resilient). Set to false for production to get one NAT per AZ."
  type        = bool
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
