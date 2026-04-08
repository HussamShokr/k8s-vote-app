# All variable declarations — values are set in terraform.tfvars (not committed)
# Copy terraform.tfvars.example to terraform.tfvars and edit before first apply.

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "app_hostname" {
  description = "Public hostname for the voting app (e.g. vote.example.com). Used for Ingress and TLS cert."
  type        = string
}

# ── VPC ────────────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap with other environments."
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to span subnets across (minimum 2)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ, EKS nodes run here"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ, load balancers attach here"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cheaper). Set false for production HA."
  type        = bool
}

# ── EKS ────────────────────────────────────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster (e.g. 1.29)"
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Allow public access to the EKS API server"
  type        = bool
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API endpoint. Use your office/VPN CIDR in production."
  type        = list(string)
}

# ── Node Group ─────────────────────────────────────────────────────────────────
variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (ceiling for Cluster Autoscaler)"
  type        = number
}

variable "node_disk_size" {
  description = "EBS root volume size in GiB per node"
  type        = number
}

# ── Add-ons ────────────────────────────────────────────────────────────────────
variable "nginx_ingress_version" {
  description = "Helm chart version for ingress-nginx (pin for reproducibility)"
  type        = string
}

variable "metrics_server_version" {
  description = "Helm chart version for metrics-server (pin for reproducibility)"
  type        = string
}

# ── Application ────────────────────────────────────────────────────────────────
variable "deploy_app" {
  description = "Deploy the voting-app Helm chart after infrastructure is ready"
  type        = bool
  default     = true
}

variable "deploy_monitoring" {
  description = "Deploy the monitoring stack (Prometheus + Grafana + Loki)"
  type        = bool
  default     = false
}
