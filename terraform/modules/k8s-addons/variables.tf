variable "nginx_ingress_version" {
  description = "Helm chart version for ingress-nginx"
  type        = string
  default     = "4.10.1"
}

variable "metrics_server_version" {
  description = "Helm chart version for metrics-server"
  type        = string
  default     = "3.12.1"
}

variable "app_hostname" {
  description = "Hostname used for the voting-app Ingress and TLS certificate"
  type        = string
}

variable "deploy_app" {
  description = "Whether to deploy the voting-app Helm chart"
  type        = bool
  default     = true
}

variable "deploy_monitoring" {
  description = "Whether to deploy the monitoring stack (Prometheus + Grafana + Loki)"
  type        = bool
  default     = false
}

variable "voting_app_chart_path" {
  description = "Absolute path to the voting-app Helm chart directory"
  type        = string
}

variable "voting_app_values_file" {
  description = "Absolute path to the values-aws.yaml override file for the voting-app chart"
  type        = string
}
