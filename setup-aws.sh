#!/usr/bin/env bash
# =============================================================================
# setup-aws.sh — One-command AWS EKS deployment for the Voting App
#
# Usage:
#   ./setup-aws.sh --hostname vote.example.com [OPTIONS]
#
# Options:
#   --hostname HOSTNAME     (required) Public hostname for the app Ingress
#   --region REGION         AWS region (default: us-east-1)
#   --env ENVIRONMENT       dev | staging | production (default: production)
#   --instance-type TYPE    EC2 instance type for nodes (default: t3.medium)
#   --nodes N               Desired node count (default: 2)
#   --monitoring            Also deploy Prometheus + Grafana + Loki
#   --skip-prereqs          Skip tool installation checks
#   --destroy               Tear down all infrastructure (terraform destroy)
#   --help                  Show this help
#
# Prerequisites (installed automatically if missing):
#   - AWS CLI v2
#   - Terraform >= 1.6
#   - kubectl
#   - Helm >= 3
#   - curl, unzip, jq
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${BOLD}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}" >&2; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${NC}\n"; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
HOSTNAME=""
AWS_REGION="us-east-1"
ENVIRONMENT="production"
INSTANCE_TYPE="t3.medium"
NODE_COUNT=2
MONITORING=false
SKIP_PREREQS=false
DESTROY=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Set after ENVIRONMENT is parsed — matches the locals.tf naming convention
CLUSTER_NAME=""  # computed below after arg parsing

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --hostname)      HOSTNAME="$2";       shift 2 ;;
    --region)        AWS_REGION="$2";     shift 2 ;;
    --env)           ENVIRONMENT="$2";    shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2";  shift 2 ;;
    --nodes)         NODE_COUNT="$2";     shift 2 ;;
    --monitoring)    MONITORING=true;     shift ;;
    --skip-prereqs)  SKIP_PREREQS=true;   shift ;;
    --destroy)       DESTROY=true;        shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# Prerequisites/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) error "Unknown option: $1. Run --help for usage." ;;
  esac
done

# Validate environment and derive computed values
case "$ENVIRONMENT" in
  dev|staging|production) ;;
  *) error "--env must be one of: dev, staging, production" ;;
esac

# Cluster name mirrors locals.tf: voting-app-<env>-eks
CLUSTER_NAME="voting-app-${ENVIRONMENT}-eks"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform/environments/${ENVIRONMENT}"

if [[ ! -d "$TERRAFORM_DIR" ]]; then
  error "Environment directory not found: ${TERRAFORM_DIR}"
fi

if [[ "$DESTROY" == "false" && -z "$HOSTNAME" ]]; then
  error "--hostname is required. Example: ./setup-aws.sh --hostname vote.example.com"
fi

# ---------------------------------------------------------------------------
# Helper: check command exists
# ---------------------------------------------------------------------------
need() {
  command -v "$1" &>/dev/null || return 1
}

# ---------------------------------------------------------------------------
# Install prerequisites
# ---------------------------------------------------------------------------
install_prereqs() {
  section "Installing prerequisites"

  # Detect OS
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  ARCH_ALT="amd64" ;;
    aarch64) ARCH_ALT="arm64" ;;
    arm64)   ARCH_ALT="arm64" ;;
    *)       warn "Unknown architecture: $ARCH — some installs may fail" ;;
  esac

  # ── AWS CLI v2 ──────────────────────────────────────────────────────────
  if ! need aws; then
    log "Installing AWS CLI v2..."
    if [[ "$OS" == "Linux" ]]; then
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp/awscli
      sudo /tmp/awscli/aws/install
      rm -rf /tmp/awscliv2.zip /tmp/awscli
    elif [[ "$OS" == "Darwin" ]]; then
      curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
      sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
      rm /tmp/AWSCLIV2.pkg
    else
      warn "Auto-install not supported on $OS — please install AWS CLI v2 manually"
    fi
    success "AWS CLI installed: $(aws --version)"
  else
    success "AWS CLI already installed: $(aws --version)"
  fi

  # ── Terraform ───────────────────────────────────────────────────────────
  if ! need terraform; then
    log "Installing Terraform..."
    TF_VERSION="1.8.5"
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH_ALT}.zip" \
      -o /tmp/terraform.zip
    unzip -q /tmp/terraform.zip -d /tmp/terraform
    sudo mv /tmp/terraform/terraform /usr/local/bin/
    rm -rf /tmp/terraform.zip /tmp/terraform
    success "Terraform installed: $(terraform version -json | jq -r '.terraform_version')"
  else
    success "Terraform already installed: $(terraform version -json | jq -r '.terraform_version')"
  fi

  # ── kubectl ─────────────────────────────────────────────────────────────
  if ! need kubectl; then
    log "Installing kubectl..."
    K8S_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH_ALT}/kubectl" \
      -o /tmp/kubectl
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm /tmp/kubectl
    success "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
  else
    success "kubectl already installed: $(kubectl version --client --short 2>/dev/null || true)"
  fi

  # ── Helm ────────────────────────────────────────────────────────────────
  if ! need helm; then
    log "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    success "Helm installed: $(helm version --short)"
  else
    success "Helm already installed: $(helm version --short)"
  fi

  # ── jq ──────────────────────────────────────────────────────────────────
  if ! need jq; then
    log "Installing jq..."
    if [[ "$OS" == "Linux" ]]; then
      sudo apt-get install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || \
        { curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${ARCH_ALT}" \
            -o /usr/local/bin/jq && chmod +x /usr/local/bin/jq; }
    elif [[ "$OS" == "Darwin" ]]; then
      brew install jq
    fi
    success "jq installed"
  fi
}

# ---------------------------------------------------------------------------
# Verify AWS credentials
# ---------------------------------------------------------------------------
check_aws_auth() {
  section "Verifying AWS credentials"
  if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
    error "AWS credentials not configured. Run 'aws configure' or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY."
  fi
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"
  success "Authenticated as: ${CALLER_ARN}"
  success "Account ID: ${ACCOUNT_ID}"
}

# ---------------------------------------------------------------------------
# Terraform init + apply / destroy
# ---------------------------------------------------------------------------
run_terraform() {
  section "Running Terraform"

  cd "$TERRAFORM_DIR"

  # Write a tfvars file for this run (non-interactive).
  # cluster_name and environment are computed in locals.tf — not passed here.
  TFVARS_FILE="${TERRAFORM_DIR}/setup-aws.auto.tfvars"
  cat > "$TFVARS_FILE" <<EOF
app_hostname       = "${HOSTNAME}"
aws_region         = "${AWS_REGION}"
node_instance_type = "${INSTANCE_TYPE}"
node_desired_size  = ${NODE_COUNT}
deploy_monitoring  = ${MONITORING}
EOF

  log "Initialising Terraform..."
  terraform init -input=false

  if [[ "$DESTROY" == "true" ]]; then
    warn "This will DESTROY all ${ENVIRONMENT} infrastructure (cluster: ${CLUSTER_NAME})."
    read -rp "Type the cluster name to confirm: " CONFIRM
    [[ "$CONFIRM" == "$CLUSTER_NAME" ]] || error "Confirmation failed — aborting."
    terraform destroy -var-file="$TFVARS_FILE" -auto-approve
    rm -f "$TFVARS_FILE"
    success "Infrastructure destroyed."
    return
  fi

  log "Planning Terraform changes..."
  terraform plan -var-file="$TFVARS_FILE" -out=tfplan -input=false

  log "Applying Terraform (this takes ~15 minutes for a new cluster)..."
  terraform apply tfplan

  rm -f "$TFVARS_FILE"  # clean up; values are now in tfstate
  success "Terraform apply complete."

  cd "$SCRIPT_DIR"
}

# ---------------------------------------------------------------------------
# Configure kubectl
# ---------------------------------------------------------------------------
configure_kubectl() {
  section "Configuring kubectl"
  aws eks update-kubeconfig \
    --region "$AWS_REGION" \
    --name "$CLUSTER_NAME"
  success "kubectl configured for cluster: ${CLUSTER_NAME}"
}

# ---------------------------------------------------------------------------
# Wait for nodes to be Ready
# ---------------------------------------------------------------------------
wait_for_nodes() {
  section "Waiting for worker nodes"
  log "Waiting for all nodes to reach Ready state (timeout: 10 min)..."
  kubectl wait node --all --for=condition=Ready --timeout=600s
  echo ""
  kubectl get nodes -o wide
  success "All nodes are Ready."
}

# ---------------------------------------------------------------------------
# Wait for core pods
# ---------------------------------------------------------------------------
wait_for_pods() {
  section "Waiting for application pods"
  local namespaces=("kube-system" "ingress-nginx" "default")
  for ns in "${namespaces[@]}"; do
    log "Checking namespace: ${ns}"
    kubectl wait pod --all -n "$ns" \
      --for=condition=Ready \
      --timeout=300s \
      --field-selector=status.phase!=Succeeded 2>/dev/null || true
  done
  success "Core pods are running."
}

# ---------------------------------------------------------------------------
# Get NLB hostname and print final instructions
# ---------------------------------------------------------------------------
print_summary() {
  section "Deployment Summary"

  NLB_HOSTNAME=""
  log "Waiting for NLB hostname to be assigned (up to 5 min)..."
  for i in $(seq 1 30); do
    NLB_HOSTNAME="$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    if [[ -n "$NLB_HOSTNAME" ]]; then
      break
    fi
    sleep 10
  done

  echo ""
  echo -e "${BOLD}┌─────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│            Voting App — AWS EKS Deployment           │${NC}"
  echo -e "${BOLD}└─────────────────────────────────────────────────────┘${NC}"
  echo ""
  echo -e "  ${CYAN}Cluster:${NC}       ${CLUSTER_NAME} [${ENVIRONMENT}] (${AWS_REGION})"
  echo -e "  ${CYAN}App hostname:${NC}  ${HOSTNAME}"
  echo ""
  if [[ -n "$NLB_HOSTNAME" ]]; then
    echo -e "  ${CYAN}NLB hostname:${NC}  ${NLB_HOSTNAME}"
    echo ""
    echo -e "  ${YELLOW}DNS ACTION REQUIRED:${NC}"
    echo -e "  Create a CNAME record in your DNS provider:"
    echo ""
    echo -e "    ${HOSTNAME}  →  ${NLB_HOSTNAME}"
    echo ""
    echo -e "  (or an ALIAS record if your DNS provider supports it)"
  else
    warn "NLB hostname not yet assigned. Run:"
    echo -e "    kubectl get svc -n ingress-nginx ingress-nginx-controller"
  fi
  echo ""
  echo -e "  ${CYAN}Application URLs (after DNS propagates):${NC}"
  echo -e "    Vote:   https://${HOSTNAME}/vote"
  echo -e "    Result: https://${HOSTNAME}/result"
  echo ""
  if [[ "$MONITORING" == "true" ]]; then
    GRAFANA_PASS="$(kubectl get secret -n default voting-app-grafana \
      -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo '<not found>')"
    echo -e "  ${CYAN}Grafana:${NC}"
    echo -e "    URL:      https://${HOSTNAME}/grafana"
    echo -e "    User:     admin"
    echo -e "    Password: ${GRAFANA_PASS}"
    echo ""
  fi
  echo -e "  ${CYAN}Useful commands:${NC}"
  echo -e "    kubectl get pods -n default"
  echo -e "    kubectl get svc  -n ingress-nginx"
  echo -e "    kubectl logs -n default -l app=vote -f"
  echo -e "    terraform -chdir=terraform output"
  echo ""
  echo -e "  ${CYAN}Tear down:${NC}"
  echo -e "    ./setup-aws.sh --hostname ${HOSTNAME} --env ${ENVIRONMENT} --destroy"
  echo ""
  success "Setup complete!"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}${BLUE}"
  echo "  ╦╔═  ┌─┐  ╦  ╦╔═╗  ┬ ┬  ┌─┐  ┌┬┐  ┌─┐  ╔═╗  ┌─┐"
  echo "  ╠╩╗  │  │  ║  ║╔═╝  └┬┘  │ │   │   ├┤   ╠═╣  ├─┘"
  echo "  ╩ ╩  └─┘  ╚═╝╚═╝    ┴   └─┘   ┴   └─┘  ╩ ╩  ┴  "
  echo -e "  AWS EKS Setup Script${NC}"
  echo ""

  if [[ "$SKIP_PREREQS" == "false" ]]; then
    install_prereqs
  fi

  check_aws_auth

  run_terraform

  if [[ "$DESTROY" == "true" ]]; then
    exit 0
  fi

  configure_kubectl
  wait_for_nodes
  wait_for_pods
  print_summary
}

main "$@"
