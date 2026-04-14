#!/usr/bin/env bash
# =============================================================================
# cleanup.sh — Full teardown of the Voting App and Canonical Kubernetes (MicroK8s)
#
# Usage:
#   sudo ./cleanup.sh              # Remove app + MicroK8s (keep kubectl & Helm)
#   sudo ./cleanup.sh --all        # Remove everything including kubectl and Helm
#   sudo ./cleanup.sh --dry-run    # Show what would be removed without doing it
# =============================================================================

set -euo pipefail

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
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

REMOVE_TOOLS=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --all)      REMOVE_TOOLS=true ;;
    --dry-run)  DRY_RUN=true ;;
    --help|-h)
      cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --all        Also remove kubectl and Helm binaries
  --dry-run    Print what would be removed without actually doing it
  --help       Show this message
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${CYAN}[dry-run]${NC} $*"
  else
    eval "$@" 2>/dev/null || true
  fi
}

# Must run as root (or sudo)
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Please run as root: sudo $0 $*"
  exit 1
fi

# Identify the real user behind sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
echo -e "${RED}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║           FULL CLEANUP — THIS IS IRREVERSIBLE        ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  This will remove:"
echo "    • Helm release and all Kubernetes namespaces"
echo "    • MicroK8s (snap remove --purge) and all cluster data"
echo "    • Persistent volumes and hostpath storage on disk"
echo "    • Leftover network interfaces (cni0, flannel, calico)"
echo "    • kubeconfig at $REAL_HOME/.kube/config"
[[ "$REMOVE_TOOLS" == true ]] && echo "    • kubectl and Helm binaries"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN — nothing will actually be removed."
else
  read -rp "  Type 'yes' to confirm full cleanup: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && echo "Aborted." && exit 0
fi

# =============================================================================
# STEP 1 — Helm release + namespaces
# =============================================================================
step "Step 1 — Removing Helm release and namespaces"

if command -v helm &>/dev/null && command -v kubectl &>/dev/null; then
  for ns in voting-app; do
    if kubectl get namespace "$ns" &>/dev/null 2>&1; then
      info "Uninstalling Helm release in '$ns'..."
      run helm uninstall voting-app -n "$ns" --ignore-not-found 2>/dev/null || true
      info "Deleting namespace '$ns'..."
      run kubectl delete namespace "$ns" --grace-period=0 --force
      success "Namespace '$ns' removed."
    else
      warn "Namespace '$ns' not found — skipping."
    fi
  done
else
  warn "helm/kubectl not found — skipping Helm release removal."
fi

# =============================================================================
# STEP 2 — MicroK8s
# =============================================================================
step "Step 2 — Removing MicroK8s"

if command -v microk8s &>/dev/null || snap list microk8s &>/dev/null 2>&1; then
  info "Running snap remove microk8s --purge ..."
  run snap remove microk8s --purge
  success "MicroK8s removed."
else
  warn "MicroK8s not installed — skipping."
fi

# =============================================================================
# STEP 3 — Leftover MicroK8s directories
# =============================================================================
step "Step 3 — Removing leftover data directories"

for dir in \
  /var/snap/microk8s \
  /var/lib/microk8s \
  /var/snap/microk8s/common/var/lib/containerd \
  /var/snap/microk8s/common/run; do
  if [[ -d "$dir" ]]; then
    info "Removing $dir ..."
    run rm -rf "$dir"
    success "$dir removed."
  fi
done

# hostpath-storage data (PV contents live here by default)
HOSTPATH_DIR="/var/snap/microk8s/common/default-storage"
if [[ -d "$HOSTPATH_DIR" ]]; then
  info "Removing hostpath PV data at $HOSTPATH_DIR ..."
  run rm -rf "$HOSTPATH_DIR"
  success "Hostpath storage data removed."
fi

# =============================================================================
# STEP 4 — Orphaned processes
# =============================================================================
step "Step 4 — Killing orphaned Kubernetes processes"

for pattern in 'kubectl ' 'vi /tmp/kubectl-edit'; do
  PIDS=$(pgrep -f "$pattern" 2>/dev/null || true)
  if [[ -n "$PIDS" ]]; then
    info "Killing processes matching '$pattern': $PIDS"
    run kill -9 $PIDS
    success "Processes killed."
  fi
done

# =============================================================================
# STEP 5 — Leftover network interfaces
# =============================================================================
step "Step 5 — Removing leftover network interfaces"

for iface in cni0 flannel.1 vxlan.calico tunl0 kube-ipvs0; do
  if ip link show "$iface" &>/dev/null 2>&1; then
    info "Removing interface $iface ..."
    run ip link delete "$iface"
    success "Interface $iface removed."
  fi
done

# Remove calico interfaces (cali*)
CALI_IFACES=$(ip link show 2>/dev/null | grep -oP 'cali[a-z0-9]+' || true)
for iface in $CALI_IFACES; do
  info "Removing calico interface $iface ..."
  run ip link delete "$iface"
done

# =============================================================================
# STEP 6 — kubeconfig
# =============================================================================
step "Step 6 — Removing kubeconfig"

for cfg in \
  "$REAL_HOME/.kube/config" \
  /root/.kube/config; do
  if [[ -f "$cfg" ]]; then
    info "Removing $cfg ..."
    run rm -f "$cfg"
    success "$cfg removed."
  fi
done

# =============================================================================
# STEP 7 — kubectl and Helm (only with --all)
# =============================================================================
if [[ "$REMOVE_TOOLS" == true ]]; then
  step "Step 7 — Removing kubectl and Helm"

  for bin in /usr/local/bin/kubectl /usr/local/bin/helm; do
    if [[ -f "$bin" ]]; then
      info "Removing $bin ..."
      run rm -f "$bin"
      success "$bin removed."
    fi
  done
else
  info "Keeping kubectl and Helm (pass --all to remove them too)."
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}============================================================${NC}"
echo -e "${BOLD}${GREEN}  Cleanup complete — system is back to a clean slate.${NC}"
echo -e "${BOLD}${GREEN}============================================================${NC}"
echo ""
echo -e "To redeploy, run:"
echo -e "  ${CYAN}sudo ./setup-canonical-k8s.sh --monitoring${NC}"
echo ""
