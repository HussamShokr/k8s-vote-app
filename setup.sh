#!/usr/bin/env bash
# =============================================================================
# setup.sh — Full Minikube setup for the Voting App (Ubuntu)
#
# Usage:
#   ./setup.sh                  # Basic install (app only)
#   ./setup.sh --monitoring     # App + Prometheus + Grafana + Loki
#   ./setup.sh --uninstall      # Remove everything
#   ./setup.sh --help
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
HOSTNAME="minikube.local"
HELM_RELEASE="voting-app"
HELM_CHART_DIR="./helm"
MINIKUBE_CPUS=2
MINIKUBE_MEMORY=4096
MINIKUBE_CPUS_MONITORING=4
MINIKUBE_MEMORY_MONITORING=8192
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
NC='\033[0m' # No Colour

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
die()     { error "$*"; exit 1; }

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    info "This script needs sudo for some steps. You may be prompted for your password."
    sudo -v
  fi
}

command_exists() { command -v "$1" &>/dev/null; }

version_gte() {
  # Returns 0 (true) if $1 >= $2 (semver strings)
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

# Detect CPU architecture and map to the naming convention each tool uses
detect_arch() {
  local raw
  raw="$(uname -m)"
  case "$raw" in
    x86_64)          echo "amd64" ;;
    aarch64|arm64)   echo "arm64" ;;
    armv7l)          echo "arm"   ;;
    *)               die "Unsupported architecture: $raw" ;;
  esac
}

ARCH="$(detect_arch)"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
MONITORING=false
UNINSTALL=false

for arg in "$@"; do
  case $arg in
    --monitoring)  MONITORING=true ;;
    --uninstall)   UNINSTALL=true  ;;
    --help|-h)
      echo "Usage: $0 [--monitoring] [--uninstall]"
      echo ""
      echo "  --monitoring   Also deploy Prometheus, Grafana, and Loki"
      echo "                 (requires 4 CPUs and 8 GB RAM)"
      echo "  --uninstall    Remove the Helm release, PVCs, and stop Minikube"
      exit 0
      ;;
    *) die "Unknown argument: $arg. Run $0 --help for usage." ;;
  esac
done

# =============================================================================
# UNINSTALL
# =============================================================================
uninstall() {
  step "Uninstalling Voting App"

  if helm status "$HELM_RELEASE" &>/dev/null; then
    info "Removing Helm release '$HELM_RELEASE'..."
    helm uninstall "$HELM_RELEASE"
    success "Helm release removed."
  else
    warn "Helm release '$HELM_RELEASE' not found — skipping."
  fi

  info "Deleting PersistentVolumeClaims..."
  kubectl delete pvc --all --ignore-not-found=true
  success "PVCs deleted."

  info "Stopping Minikube..."
  minikube stop || true
  success "Minikube stopped."

  echo ""
  success "Uninstall complete. Run 'minikube delete' to remove the cluster entirely."
  exit 0
}

[[ "$UNINSTALL" == true ]] && uninstall

# =============================================================================
# CHECK OS
# =============================================================================
step "Checking operating system"

if [[ "$(uname -s)" != "Linux" ]]; then
  die "This script is for Ubuntu/Linux only."
fi

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
  warn "OS does not appear to be Ubuntu. Proceeding anyway, but results may vary."
else
  UBUNTU_VERSION=$(grep "^VERSION_ID" /etc/os-release | cut -d'"' -f2)
  success "Ubuntu $UBUNTU_VERSION detected."
fi

require_sudo

# =============================================================================
# STEP 1 — DOCKER
# =============================================================================
step "Step 1/7 — Docker"

if command_exists docker; then
  DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
  success "Docker $DOCKER_VERSION already installed."
else
  info "Installing Docker..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io
  success "Docker installed."
fi

# Ensure current user is in the docker group
if ! groups "$USER" | grep -q docker; then
  info "Adding $USER to the docker group..."
  sudo usermod -aG docker "$USER"
  warn "Docker group membership added. If Docker commands fail, run: newgrp docker"
  warn "Or log out and log back in, then re-run this script."
  # Apply group in current shell
  exec sg docker "$0 $*"
fi

docker info &>/dev/null || die "Docker daemon is not running. Start it with: sudo systemctl start docker"
success "Docker daemon is running."

# =============================================================================
# STEP 2 — MINIKUBE
# =============================================================================
step "Step 2/7 — Minikube"

if command_exists minikube && minikube version &>/dev/null 2>&1; then
  MK_VERSION=$(minikube version --short)
  success "Minikube $MK_VERSION already installed."
else
  if [[ -f /usr/local/bin/minikube ]]; then
    warn "Existing minikube binary is not executable (wrong architecture) — reinstalling..."
    sudo rm -f /usr/local/bin/minikube
  fi
  info "Installing Minikube (arch: ${ARCH})..."
  curl -sSLo /tmp/minikube \
    "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}"
  sudo install /tmp/minikube /usr/local/bin/minikube
  rm /tmp/minikube
  success "Minikube installed."
fi

# =============================================================================
# STEP 3 — KUBECTL
# =============================================================================
step "Step 3/7 — kubectl"

if command_exists kubectl && kubectl version --client &>/dev/null 2>&1; then
  KB_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -oP '"gitVersion":\s*"\K[^"]+' | head -1)
  success "kubectl $KB_VERSION already installed."
else
  if [[ -f /usr/local/bin/kubectl ]]; then
    warn "Existing kubectl binary is not executable (wrong architecture) — reinstalling..."
    sudo rm -f /usr/local/bin/kubectl
  fi
  info "Installing kubectl (arch: ${ARCH})..."
  KUBECTL_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
  curl -sSLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl
  success "kubectl $KUBECTL_VERSION installed."
fi

# =============================================================================
# STEP 4 — HELM
# =============================================================================
step "Step 4/7 — Helm"

if command_exists helm; then
  HELM_VERSION=$(helm version --short)
  success "Helm $HELM_VERSION already installed."
else
  info "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | bash -s -- --no-sudo 2>/dev/null \
    || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  success "Helm installed."
fi

# =============================================================================
# STEP 5 — START MINIKUBE
# =============================================================================
step "Step 5/7 — Starting Minikube"

if [[ "$MONITORING" == true ]]; then
  CPU_COUNT=$MINIKUBE_CPUS_MONITORING
  MEM_SIZE=$MINIKUBE_MEMORY_MONITORING
  info "Monitoring enabled — using ${CPU_COUNT} CPUs and ${MEM_SIZE} MB RAM."
else
  CPU_COUNT=$MINIKUBE_CPUS
  MEM_SIZE=$MINIKUBE_MEMORY
  info "Using ${CPU_COUNT} CPUs and ${MEM_SIZE} MB RAM."
fi

MINIKUBE_STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null || echo "Stopped")

if [[ "$MINIKUBE_STATUS" == "Running" ]]; then
  success "Minikube is already running."
else
  info "Starting Minikube (driver=docker)..."
  minikube start \
    --driver=docker \
    --cpus="$CPU_COUNT" \
    --memory="$MEM_SIZE" \
    --wait=all
  success "Minikube started."
fi

# =============================================================================
# STEP 6 — ENABLE ADDONS
# =============================================================================
step "Step 6/7 — Enabling Minikube addons"

enable_addon() {
  local addon=$1
  if minikube addons list | grep -E "^[| ]+$addon" | grep -q "enabled"; then
    success "Addon '$addon' already enabled."
  else
    info "Enabling addon: $addon..."
    minikube addons enable "$addon"
    success "Addon '$addon' enabled."
  fi
}

enable_addon ingress
enable_addon metrics-server

info "Waiting for ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
success "Ingress controller is ready."

# =============================================================================
# STEP 7 — /etc/hosts
# =============================================================================
step "Step 7/7 — Configuring /etc/hosts"

MINIKUBE_IP=$(minikube ip)
info "Minikube IP: $MINIKUBE_IP"

if grep -qE "^\s*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+${HOSTNAME}" /etc/hosts; then
  # Update the entry if IP changed
  EXISTING_IP=$(grep -E "\s+${HOSTNAME}" /etc/hosts | awk '{print $1}' | head -1)
  if [[ "$EXISTING_IP" != "$MINIKUBE_IP" ]]; then
    warn "Existing /etc/hosts entry has IP $EXISTING_IP — updating to $MINIKUBE_IP..."
    sudo sed -i "s|^${EXISTING_IP}\s\+${HOSTNAME}|${MINIKUBE_IP} ${HOSTNAME}|" /etc/hosts
    success "/etc/hosts entry updated."
  else
    success "/etc/hosts already has correct entry: $MINIKUBE_IP $HOSTNAME"
  fi
else
  info "Adding '$MINIKUBE_IP $HOSTNAME' to /etc/hosts..."
  echo "$MINIKUBE_IP $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
  success "/etc/hosts updated."
fi

# =============================================================================
# CERT-MANAGER CRDs
# Must be applied before `helm install` because Helm validates ALL resources
# in the release (including Certificate and ClusterIssuer) before creating
# anything — even the cert-manager subchart's own CRDs.
# Applying just the CRDs first breaks the chicken-and-egg deadlock.
# =============================================================================
step "Installing cert-manager CRDs"

CERT_MANAGER_VERSION="v1.14.5"

if kubectl get crd certificates.cert-manager.io &>/dev/null 2>&1; then
  success "cert-manager CRDs already installed."
else
  info "Applying cert-manager CRDs (${CERT_MANAGER_VERSION})..."
  kubectl apply -f \
    "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml"
  info "Waiting for CRDs to be established..."
  kubectl wait --for=condition=established \
    crd/certificates.cert-manager.io \
    crd/clusterissuers.cert-manager.io \
    --timeout=60s
  success "cert-manager CRDs installed."
fi

# =============================================================================
# INSTALL HELM CHART
# =============================================================================
step "Installing Helm chart"

if [[ ! -d "$HELM_CHART_DIR" ]]; then
  die "Helm chart directory '$HELM_CHART_DIR' not found. Run this script from the repo root."
fi

HELM_ARGS=(
  --set "global.hostname=${HOSTNAME}"
)

if [[ "$MONITORING" == true ]]; then
  HELM_ARGS+=(
    --set "monitoring.enabled=true"
    --set "monitoring.lokiEnabled=true"
  )
  info "Monitoring flags: enabled"
fi

if helm status "$HELM_RELEASE" &>/dev/null; then
  info "Release '$HELM_RELEASE' already exists — upgrading..."
  helm upgrade "$HELM_RELEASE" "$HELM_CHART_DIR" "${HELM_ARGS[@]}"
  success "Helm release upgraded."
else
  info "Installing release '$HELM_RELEASE'..."
  helm install "$HELM_RELEASE" "$HELM_CHART_DIR" "${HELM_ARGS[@]}"
  success "Helm release installed."
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
    --timeout="$timeout" 2>/dev/null \
  && success "$name is ready." \
  || warn "$name did not become ready within timeout — check: kubectl describe pod -l $label"
}

# DB must be ready before worker init containers can complete
wait_for "app=db"     "PostgreSQL"  "${KUBECTL_WAIT_TIMEOUT}"
wait_for "app=redis"  "Redis"       "120s"
wait_for "app=vote"   "Vote UI"     "120s"
wait_for "app=result" "Result UI"   "120s"
wait_for "app=worker" "Worker"      "${KUBECTL_WAIT_TIMEOUT}"

if [[ "$MONITORING" == true ]]; then
  info "Waiting for monitoring stack (this can take 2-3 minutes)..."
  kubectl wait --for=condition=ready pod \
    -l "app.kubernetes.io/name=grafana" \
    --timeout=300s 2>/dev/null \
  && success "Grafana is ready." \
  || warn "Grafana not ready yet — check: kubectl get pods"
fi

# =============================================================================
# VERIFY
# =============================================================================
step "Verification"

echo ""
info "Pods:"
kubectl get pods -o wide

echo ""
info "Services:"
kubectl get svc

echo ""
info "Ingress:"
kubectl get ingress

echo ""
info "Certificates:"
kubectl get certificate 2>/dev/null || true

echo ""
info "PersistentVolumeClaims:"
kubectl get pvc

echo ""
info "HorizontalPodAutoscalers:"
kubectl get hpa 2>/dev/null || true

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}============================================${NC}"
echo -e "${BOLD}${GREEN}  Voting App is up and running!${NC}"
echo -e "${BOLD}${GREEN}============================================${NC}"
echo ""
echo -e "  ${BOLD}Vote UI    :${NC}  https://${HOSTNAME}/vote"
echo -e "  ${BOLD}Result UI  :${NC}  https://${HOSTNAME}/result"

if [[ "$MONITORING" == true ]]; then
  echo -e "  ${BOLD}Grafana    :${NC}  https://${HOSTNAME}/grafana"
  echo -e "  ${BOLD}             ${NC}  Username: admin  |  Password: prom-operator"
fi

echo ""
echo -e "${YELLOW}Note:${NC} Your browser will show an SSL warning (self-signed cert)."
echo -e "       Click 'Advanced' → 'Proceed to ${HOSTNAME}' to continue."
echo ""
echo -e "To uninstall: ${CYAN}./setup.sh --uninstall${NC}"
echo ""
