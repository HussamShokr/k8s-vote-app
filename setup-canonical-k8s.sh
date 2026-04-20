#!/usr/bin/env bash
# =============================================================================
# setup-canonical-k8s.sh — Production setup for Voting App on Ubuntu
#                          using Canonical Kubernetes (MicroK8s)
#
# Usage:
#   ./setup-canonical-k8s.sh                              # Basic install
#   ./setup-canonical-k8s.sh --monitoring                 # App + Prometheus + Grafana + Loki
#   ./setup-canonical-k8s.sh --tls                        # Enable TLS with Let's Encrypt
#   ./setup-canonical-k8s.sh --monitoring --tls           # Full production stack
#   ./setup-canonical-k8s.sh --uninstall                  # Remove the Helm release and PVCs
#   ./setup-canonical-k8s.sh --reset                      # Wipe MicroK8s completely (fresh slate)
#
# Required flags when --tls is used:
#   --hostname=<domain>    Your public domain name (e.g. vote.example.com)
#   --email=<email>        Email for Let's Encrypt registration
#
# Optional flags:
#   --metallb-ips=<range>  MetalLB IP range (e.g. 192.168.1.100-192.168.1.110)
#                          Defaults to auto-detect from current network interface
#   --namespace=<ns>       Kubernetes namespace (default: voting-app)
#   --hostname=<domain>    Hostname / domain for the ingress (default: voting.local)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
HELM_RELEASE="voting-app"
HELM_CHART_DIR="./helm"
NAMESPACE="voting-app"
HOSTNAME="voting.local"
EMAIL=""
METALLB_IPS=""
MONITORING=false
TLS=false
SELF_SIGNED=false
UNINSTALL=false
RESET=false
KUBECTL_WAIT_TIMEOUT=300s

# -----------------------------------------------------------------------------
# Colours
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
die()     { error "$*"; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    info "This script needs sudo for some steps. You may be prompted for your password."
    sudo -v
  fi
}

detect_arch() {
  local raw
  raw="$(uname -m)"
  case "$raw" in
    x86_64)        echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l)        echo "arm"   ;;
    *)             die "Unsupported architecture: $raw" ;;
  esac
}

ARCH="$(detect_arch)"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
for arg in "$@"; do
  case $arg in
    --monitoring)        MONITORING=true ;;
    --tls)               TLS=true ;;
    --self-signed)       TLS=true; SELF_SIGNED=true ;;
    --uninstall)         UNINSTALL=true ;;
    --reset)             RESET=true ;;
    --hostname=*)        HOSTNAME="${arg#*=}" ;;
    --email=*)           EMAIL="${arg#*=}" ;;
    --metallb-ips=*)     METALLB_IPS="${arg#*=}" ;;
    --namespace=*)       NAMESPACE="${arg#*=}" ;;
    --help|-h)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --monitoring             Deploy Prometheus, Grafana, and Loki (requires 8+ GB RAM)
  --tls                    Enable HTTPS with Let's Encrypt (requires --hostname and --email)
  --self-signed            Enable HTTPS with a self-signed cert — no domain or email needed.
                           Perfect for LAN/private network use.
  --hostname=<domain>      Domain or local hostname for ingress (default: voting.local)
  --email=<email>          Email for Let's Encrypt registration (required with --tls)
  --metallb-ips=<range>    IP range for MetalLB LoadBalancer (e.g. 192.168.1.100-192.168.1.110)
  --namespace=<ns>         Kubernetes namespace (default: voting-app)
  --uninstall              Remove Helm release and PVCs
  --reset                  Full MicroK8s wipe — removes ALL workloads, addons, and data.
                           Run setup again afterward for a fresh install.
  --help                   Show this message
EOF
      exit 0
      ;;
    *) die "Unknown argument: $arg. Run $0 --help for usage." ;;
  esac
done

# Validate TLS requirements
if [[ "$TLS" == true && "$SELF_SIGNED" == false ]]; then
  [[ -z "$EMAIL" ]] && die "--email is required when --tls is used. e.g. --email=admin@example.com"
  [[ "$HOSTNAME" == "voting.local" ]] && \
    die "--hostname must be a real public domain when --tls is used. For LAN use, try --self-signed instead."
fi

# =============================================================================
# UNINSTALL
# =============================================================================
uninstall() {
  step "Uninstalling Voting App"

  if helm status "$HELM_RELEASE" -n "$NAMESPACE" &>/dev/null; then
    info "Removing Helm release '$HELM_RELEASE' from namespace '$NAMESPACE'..."
    helm uninstall "$HELM_RELEASE" -n "$NAMESPACE"
    success "Helm release removed."
  else
    warn "Helm release '$HELM_RELEASE' not found — skipping."
  fi

  info "Deleting PersistentVolumeClaims in namespace '$NAMESPACE'..."
  kubectl delete pvc --all -n "$NAMESPACE" --ignore-not-found=true
  success "PVCs deleted."

  info "Deleting namespace '$NAMESPACE'..."
  kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
  success "Namespace deleted."

  echo ""
  success "Uninstall complete."
  exit 0
}

[[ "$UNINSTALL" == true ]] && uninstall

# =============================================================================
# RESET  (--reset)  — full MicroK8s wipe, ready for a fresh install
# =============================================================================
reset_cluster() {
  step "Resetting MicroK8s — this will DELETE all workloads, addons, volumes, and data"

  echo -e "${RED}${BOLD}"
  echo "  WARNING: This is irreversible."
  echo "  MicroK8s will be fully removed and reinstalled (snap remove --purge + snap install)."
  echo "  All Kubernetes resources, persistent volumes, and addon state will be destroyed."
  echo -e "${NC}"
  read -rp "  Type 'yes' to confirm: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && die "Reset aborted."

  # 'microk8s reset' is known to hang when hostpath-storage PVCs are still
  # bound. A snap remove --purge + reinstall is faster and guaranteed clean.
  info "Removing MicroK8s (snap remove --purge)..."
  snap remove microk8s --purge
  success "MicroK8s removed."

  info "Reinstalling MicroK8s (channel 1.32/stable)..."
  snap install microk8s --classic --channel=1.32/stable
  success "MicroK8s reinstalled."

  info "Clearing local kubeconfig..."
  REAL_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
  REAL_HOME="${REAL_HOME:-$HOME}"
  rm -f "$REAL_HOME/.kube/config"
  success "kubeconfig cleared."

  echo ""
  echo -e "${BOLD}${GREEN}Reset complete — MicroK8s is fresh.${NC}"
  echo -e "Run ${CYAN}./setup-canonical-k8s.sh [--monitoring] [--hostname=...]${NC} to redeploy."
  echo ""
  exit 0
}

[[ "$RESET" == true ]] && reset_cluster

# =============================================================================
# CHECK OS
# =============================================================================
step "Checking operating system"

[[ "$(uname -s)" != "Linux" ]] && die "This script is for Ubuntu/Linux only."

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
  warn "OS does not appear to be Ubuntu. Proceeding, but results may vary."
else
  UBUNTU_VERSION=$(grep "^VERSION_ID" /etc/os-release | cut -d'"' -f2)
  success "Ubuntu $UBUNTU_VERSION detected."
fi

require_sudo

# =============================================================================
# STEP 1 — MicroK8s
# =============================================================================
step "Step 1/6 — Canonical Kubernetes (MicroK8s)"

if command_exists microk8s && microk8s version &>/dev/null 2>&1; then
  MK_VERSION=$(microk8s version 2>/dev/null | head -1)
  success "MicroK8s already installed: $MK_VERSION"
else
  info "Installing MicroK8s via snap (channel 1.32/stable)..."
  sudo snap install microk8s --classic --channel=1.32/stable
  success "MicroK8s installed."
fi

# Add user to microk8s group so kubectl works without sudo
if ! groups "$USER" | grep -q microk8s; then
  info "Adding $USER to the 'microk8s' group..."
  sudo usermod -aG microk8s "$USER"
  warn "Group membership changed. Applying in current shell..."
  # Re-exec under the new group so the rest of the script has access
  exec sg microk8s -c "$0 $*"
fi

info "Waiting for MicroK8s to be ready..."
microk8s status --wait-ready --timeout=120
success "MicroK8s is ready."

# =============================================================================
# STEP 2 — kubectl (via MicroK8s alias) + standalone kubectl
# =============================================================================
step "Step 2/6 — kubectl"

# Configure standard kubectl to use MicroK8s credentials
# When invoked via sudo, write kubeconfig to the invoking user's home dir,
# not root's, so plain 'kubectl' works for that user after the script exits.
REAL_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
REAL_HOME="${REAL_HOME:-$HOME}"
REAL_USER="${SUDO_USER:-$USER}"

mkdir -p "$REAL_HOME/.kube"
microk8s config > "$REAL_HOME/.kube/config"
chmod 600 "$REAL_HOME/.kube/config"
chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/.kube/config" 2>/dev/null || true

if ! command_exists kubectl; then
  info "Installing kubectl..."
  KUBECTL_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
  curl -sSLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl
  success "kubectl $KUBECTL_VERSION installed."
else
  success "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client -o json | grep -oP '"gitVersion":\s*"\K[^"]+')"
fi

# =============================================================================
# STEP 3 — Helm
# =============================================================================
step "Step 3/6 — Helm"

if command_exists helm; then
  success "Helm already installed: $(helm version --short)"
else
  info "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  success "Helm installed: $(helm version --short)"
fi

# =============================================================================
# STEP 4 — Enable MicroK8s Addons
# =============================================================================
step "Step 4/6 — Enabling MicroK8s addons"

enable_addon() {
  local addon=$1
  shift
  local extra_args="${*:-}"
  local state
  state=$(microk8s status --format yaml 2>/dev/null \
    | grep -A1 "name: ${addon}" | grep "status:" | awk '{print $2}' || echo "disabled")

  if [[ "$state" == "enabled" ]]; then
    success "Addon '${addon}' already enabled."
  else
    info "Enabling addon: ${addon} ${extra_args}..."
    # shellcheck disable=SC2086
    microk8s enable "${addon}" ${extra_args}
    success "Addon '${addon}' enabled."
  fi
}

# Core addons — always required
enable_addon dns
enable_addon hostpath-storage
enable_addon metrics-server
enable_addon ingress

info "Waiting for ingress controller to be ready..."
kubectl wait --namespace ingress \
  --for=condition=ready pod \
  --selector=name=nginx-ingress-microk8s \
  --timeout=120s 2>/dev/null \
|| kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s 2>/dev/null \
|| warn "Ingress controller pod not detected in expected namespace — check: kubectl get pods -A | grep ingress"
success "Ingress controller is ready."

# MetalLB — needed for LoadBalancer services (production bare-metal)
if [[ -z "$METALLB_IPS" ]]; then
  # Auto-detect a sensible IP range from the default route interface
  DEFAULT_IF=$(ip route | awk '/^default/ {print $5}' | head -1)
  HOST_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null \
    | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)
  if [[ -n "$HOST_IP" ]]; then
    # Suggest the last /28 block (.200-.214) of the host's /24 subnet
    SUBNET_PREFIX=$(echo "$HOST_IP" | cut -d. -f1-3)
    METALLB_IPS="${SUBNET_PREFIX}.200-${SUBNET_PREFIX}.214"
    warn "MetalLB IP range not specified. Auto-detected: $METALLB_IPS"
    warn "Change with --metallb-ips=<range> if this conflicts with your network."
  else
    die "Cannot auto-detect MetalLB IP range. Provide --metallb-ips=<start>-<end>"
  fi
fi

info "Enabling MetalLB with IP range: $METALLB_IPS"
microk8s enable metallb:"$METALLB_IPS"
success "MetalLB enabled ($METALLB_IPS)."

# cert-manager — required for TLS (install regardless; only ClusterIssuer is conditional)
info "Enabling cert-manager addon..."
microk8s enable cert-manager
info "Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=cert-manager \
  --timeout=180s 2>/dev/null \
|| warn "cert-manager pods not ready yet — they may still be pulling images."
success "cert-manager enabled."

# =============================================================================
# STEP 5 — Create Namespace
# =============================================================================
step "Step 5/6 — Namespace"

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  success "Namespace '$NAMESPACE' already exists."
else
  kubectl create namespace "$NAMESPACE"
  success "Namespace '$NAMESPACE' created."
fi

# =============================================================================
# STEP 6 — Deploy via Helm
# =============================================================================
step "Step 6/6 — Deploying Voting App via Helm"

if [[ ! -d "$HELM_CHART_DIR" ]]; then
  die "Helm chart directory '$HELM_CHART_DIR' not found. Run this script from the repo root."
fi

info "Updating Helm chart dependencies..."
CHARTS_CACHED=false
if ls "$HELM_CHART_DIR/charts/"*.tgz &>/dev/null 2>&1; then
  CHARTS_CACHED=true
fi

DEPS_OK=false
for attempt in 1 2 3; do
  if helm dependency update "$HELM_CHART_DIR"; then
    DEPS_OK=true
    break
  fi
  warn "Dependency update failed (attempt $attempt/3)..."
  [[ $attempt -lt 3 ]] && info "Retrying in 15s..." && sleep 15
done

if [[ "$DEPS_OK" == false ]]; then
  if [[ "$CHARTS_CACHED" == true ]]; then
    warn "Download failed — using cached charts from a previous run."
    helm dependency build "$HELM_CHART_DIR" 2>/dev/null || true
  else
    die "Helm dependency update failed after 3 attempts and no cached charts found. Check your internet connection."
  fi
fi
success "Dependencies ready."

# Install Prometheus Operator CRDs before the chart so Helm can validate
# ServiceMonitor / PodMonitor resources during rendering.
step "Installing Prometheus Operator CRDs"
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml \
  2>/dev/null || true

# Remove the standalone operator deployment so it doesn't conflict with the
# Helm-managed one inside kube-prometheus-stack.
for resource in \
  "deployment/prometheus-operator" \
  "service/prometheus-operator" \
  "serviceaccount/prometheus-operator"; do
  kubectl delete "$resource" -n default --ignore-not-found=true
done
for resource in \
  "clusterrole/prometheus-operator" \
  "clusterrolebinding/prometheus-operator"; do
  kubectl delete "$resource" --ignore-not-found=true
done
success "Prometheus Operator CRDs installed."

# Build Helm arguments
HELM_ARGS=(
  --namespace "$NAMESPACE"
  --values "$HELM_CHART_DIR/values-production.yaml"
  --set "global.hostname=${HOSTNAME}"
)

# Monitoring flags
if [[ "$MONITORING" == true ]]; then
  HELM_ARGS+=(
    --set "monitoring.enabled=true"
    --set "monitoring.lokiEnabled=true"
  )
  info "Monitoring stack: enabled"
fi

# TLS flags
if [[ "$TLS" == true ]]; then
  HELM_ARGS+=(
    --set "certificate.enabled=true"
    --set "clusterIssuer.enabled=true"
  )
  if [[ "$SELF_SIGNED" == true ]]; then
    HELM_ARGS+=(
      --set "clusterIssuer.type=selfSigned"
    )
    info "TLS (self-signed cert): enabled for ${HOSTNAME}"
    warn "Browsers will show a security warning — click 'Advanced → Proceed' to continue."
  else
    HELM_ARGS+=(
      --set "clusterIssuer.type=letsencrypt"
      --set "clusterIssuer.email=${EMAIL}"
    )
    info "TLS (Let's Encrypt): enabled for ${HOSTNAME}"
  fi
else
  info "TLS: disabled (HTTP only). Use --tls or --self-signed to enable HTTPS."
fi

# Install or upgrade
if helm status "$HELM_RELEASE" -n "$NAMESPACE" &>/dev/null; then
  info "Release '$HELM_RELEASE' already exists — upgrading..."
  helm upgrade "$HELM_RELEASE" "$HELM_CHART_DIR" "${HELM_ARGS[@]}"
  success "Helm release upgraded."
else
  info "Installing release '$HELM_RELEASE'..."
  helm install "$HELM_RELEASE" "$HELM_CHART_DIR" "${HELM_ARGS[@]}"
  success "Helm release installed."
fi

# =============================================================================
# APPLY INFRASTRUCTURE MANIFESTS
# =============================================================================
step "Applying infrastructure manifests"

INFRA_DIR="$(dirname "$0")/k8s-specifications/infra"
if [[ -d "$INFRA_DIR" ]]; then
  kubectl apply -f "$INFRA_DIR/"
  success "Infrastructure manifests applied."
else
  warn "Infra manifest directory not found at '$INFRA_DIR' — skipping."
fi

# =============================================================================
# WAIT FOR PODS
# =============================================================================
step "Waiting for pods to be ready"

wait_for() {
  local label=$1
  local name=$2
  local timeout=${3:-$KUBECTL_WAIT_TIMEOUT}
  info "Waiting for $name..."
  kubectl wait --for=condition=ready pod \
    -l "$label" \
    -n "$NAMESPACE" \
    --timeout="$timeout" 2>/dev/null \
  && success "$name is ready." \
  || warn "$name did not become ready in time — check: kubectl describe pod -l $label -n $NAMESPACE"
}

# DB must be ready before worker init containers can finish
wait_for "app=db"     "PostgreSQL"  "${KUBECTL_WAIT_TIMEOUT}"
wait_for "app=redis"  "Redis"       "120s"
wait_for "app=vote"   "Vote UI"     "120s"
wait_for "app=result" "Result UI"   "120s"
wait_for "app=worker" "Worker"      "${KUBECTL_WAIT_TIMEOUT}"

if [[ "$MONITORING" == true ]]; then
  info "Waiting for monitoring stack (can take 3-5 minutes on first pull)..."
  kubectl wait --for=condition=ready pod \
    -l "app.kubernetes.io/name=grafana" \
    -n "$NAMESPACE" \
    --timeout=300s 2>/dev/null \
  && success "Grafana is ready." \
  || warn "Grafana not ready yet — check: kubectl get pods -n $NAMESPACE"
fi

# =============================================================================
# VERIFY
# =============================================================================
step "Verification"

echo ""
info "Nodes:"
kubectl get nodes -o wide

echo ""
info "Pods (-n $NAMESPACE):"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
info "Services:"
kubectl get svc -n "$NAMESPACE"

echo ""
info "Ingress:"
kubectl get ingress -n "$NAMESPACE"

if [[ "$TLS" == true ]]; then
  echo ""
  info "Certificates:"
  kubectl get certificate -n "$NAMESPACE" 2>/dev/null || true
fi

echo ""
info "PersistentVolumeClaims:"
kubectl get pvc -n "$NAMESPACE"

echo ""
info "HorizontalPodAutoscalers:"
kubectl get hpa -n "$NAMESPACE" 2>/dev/null || true

# =============================================================================
# DONE
# =============================================================================
INGRESS_IP=$(kubectl get svc -n ingress-nginx \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null \
  || kubectl get svc -n ingress \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null \
  || echo "<ingress-ip>")

PROTO="http"
[[ "$TLS" == true ]] && PROTO="https"

# Also update the ingress annotation to force HTTPS redirect when TLS is on
if [[ "$TLS" == true ]]; then
  kubectl annotate ingress voting-app-ingress \
    nginx.ingress.kubernetes.io/ssl-redirect="true" \
    nginx.ingress.kubernetes.io/force-ssl-redirect="true" \
    -n "$NAMESPACE" --overwrite 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${GREEN}============================================================${NC}"
echo -e "${BOLD}${GREEN}  Voting App is up and running on Canonical Kubernetes!${NC}"
echo -e "${BOLD}${GREEN}============================================================${NC}"
echo ""
echo -e "  ${BOLD}Vote UI    :${NC}  ${PROTO}://${HOSTNAME}/vote"
echo -e "  ${BOLD}Result UI  :${NC}  ${PROTO}://${HOSTNAME}/result"

if [[ "$MONITORING" == true ]]; then
  echo -e "  ${BOLD}Grafana    :${NC}  ${PROTO}://${HOSTNAME}/grafana"
  echo -e "  ${BOLD}             ${NC}  Username: admin  |  Password: prom-operator"
fi

if [[ "$HOSTNAME" == "voting.local" ]]; then
  echo ""
  echo -e "${YELLOW}Note:${NC} Using local hostname '${HOSTNAME}'."
  echo -e "       Add the following line to your /etc/hosts (or DNS):"
  echo -e "       ${CYAN}${INGRESS_IP}  ${HOSTNAME}${NC}"
fi

if [[ "$TLS" == false ]]; then
  echo ""
  echo -e "${YELLOW}Note:${NC} HTTPS is disabled. Re-deploy with ${CYAN}--tls --hostname=<domain> --email=<email>${NC}"
  echo -e "       to get an auto-renewing Let's Encrypt certificate."
fi

echo ""
echo -e "Cluster info:  ${CYAN}kubectl get nodes${NC}"
echo -e "App status:    ${CYAN}kubectl get pods -n ${NAMESPACE}${NC}"
echo -e "To uninstall:  ${CYAN}./setup-canonical-k8s.sh --uninstall${NC}"
echo ""
