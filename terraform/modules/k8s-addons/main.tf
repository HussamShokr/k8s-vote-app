# =============================================================================
# gp3 StorageClass
# Replaces the legacy gp2 default with the newer, faster, cheaper gp3.
# WaitForFirstConsumer avoids cross-AZ volume scheduling failures.
# =============================================================================
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# Remove the default annotation from gp2 so only gp3 is the default
resource "kubernetes_annotations" "gp2_non_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"

  metadata {
    name = "gp2"
  }

  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  force = true
}

# =============================================================================
# Metrics Server
# Required for HorizontalPodAutoscaler to read CPU/memory metrics.
# =============================================================================
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP"
  }
}

# =============================================================================
# NGINX Ingress Controller
# Fronted by an AWS Network Load Balancer (TCP pass-through).
# NLB preserves real client IPs and supports TLS termination in NGINX.
# =============================================================================
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_version
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-cross-zone-load-balancing-enabled"
    value = "true"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-backend-protocol"
    value = "tcp"
  }
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }
  set {
    name  = "controller.allowSnippetAnnotations"
    value = "true"
  }
}

# =============================================================================
# Voting App — Helm chart from the project root
# Gated by var.deploy_app so infra can be applied independently first.
# =============================================================================
resource "helm_release" "voting_app" {
  count = var.deploy_app ? 1 : 0

  name      = "voting-app"
  chart     = var.voting_app_chart_path
  namespace = "default"

  values = [file(var.voting_app_values_file)]

  set {
    name  = "global.hostname"
    value = var.app_hostname
  }
  set {
    name  = "monitoring.enabled"
    value = tostring(var.deploy_monitoring)
  }
  set {
    name  = "monitoring.lokiEnabled"
    value = tostring(var.deploy_monitoring)
  }

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.metrics_server,
    kubernetes_storage_class.gp3,
  ]
}
