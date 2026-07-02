#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="${KUBECONFIG:-${SCRIPT_DIR}/.kubeconfig}"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/config.env"
fi

NAMESPACE="${NAMESPACE:-}"
CLUSTER_API="${CLUSTER_API:-}"
VM_NAME="ubuntu-noble-vm"
DATAVOLUME="ubuntu-noble-image"
DATAVOLUME_SIZE="20Gi"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_FILE="noble-server-cloudimg-amd64.img"
SSH_KEY="${HOME}/.ssh/id_rsa"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' not found. Install it first (see README.md)." >&2
    exit 1
  fi
}

require_config() {
  if [[ -z "${CLUSTER_API}" || -z "${NAMESPACE}" ]]; then
    echo "ERROR: Set CLUSTER_API and NAMESPACE in config.env (see config.env.example)." >&2
    exit 1
  fi
}

step_login() {
  if oc whoami >/dev/null 2>&1; then
    echo "Already logged in as: $(oc whoami)"
    return
  fi

  echo "Get a token from the ITUP console:"
  echo "  username (top right) -> Copy login command -> Display token"
  echo
  read -r -s -p "Paste oc login token: " TOKEN
  echo
  oc login --token="${TOKEN}" --server="${CLUSTER_API}" --insecure-skip-tls-verify
}

step_project() {
  oc project "${NAMESPACE}"
}

step_quota() {
  echo "=== Namespace quota ==="
  oc describe limitrange limits -n "${NAMESPACE}" || true
  echo
}

step_download_image() {
  if [[ -f "${SCRIPT_DIR}/${IMAGE_FILE}" ]]; then
    echo "Image already downloaded: ${IMAGE_FILE}"
    return
  fi

  echo "Downloading Ubuntu Noble cloud image (~700MB)..."
  curl -L -o "${SCRIPT_DIR}/${IMAGE_FILE}" "${IMAGE_URL}"
}

step_upload_image() {
  if oc get dv "${DATAVOLUME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "DataVolume '${DATAVOLUME}' already exists, skipping upload."
    return
  fi

  echo "Uploading image to cluster (this can take several minutes)..."
  virtctl image-upload dv "${DATAVOLUME}" \
    --image-path="${SCRIPT_DIR}/${IMAGE_FILE}" \
    -n "${NAMESPACE}" \
    --size="${DATAVOLUME_SIZE}" \
    --insecure
}

step_apply_vm() {
  if oc get vm "${VM_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "VM '${VM_NAME}' already exists."
  else
    oc apply -f "${SCRIPT_DIR}/ubuntu-vm.yaml"
    echo "Waiting for VM to start..."
    virtctl start "${VM_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
  fi

  echo "VM status:"
  oc get vm,vmi -n "${NAMESPACE}" -l app="${VM_NAME}" 2>/dev/null || oc get vm,vmi -n "${NAMESPACE}"
}

step_apply_egress() {
  if oc get tenantegress default -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "TenantEgress 'default' already exists, skipping."
    return
  fi
  if ! oc auth can-i create tenantegresses -n "${NAMESPACE}" | grep -q yes; then
    echo "Cannot create TenantEgress; ensure egress rules exist or ask an admin."
    return
  fi
  oc apply -f "${SCRIPT_DIR}/tenant-egress-domains.yaml"
  echo "TenantEgress applied."
}

step_ssh_hint() {
  echo
  echo "=== Done ==="
  echo "SSH into the VM with:"
  echo "  virtctl -n ${NAMESPACE} ssh ubuntu@vmi/${VM_NAME} \\"
  echo "    --identity-file=\"${SSH_KEY}\" \\"
  echo "    --local-ssh-opts='-o IdentitiesOnly=yes'"
  echo
  echo "Check VM status:"
  echo "  oc get vmi -n ${NAMESPACE}"
  echo "  virtctl console ${VM_NAME} -n ${NAMESPACE}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|login|quota|image|upload|vm|egress|ssh]

  all     Run full setup (default)
  login   Authenticate to ITUP cluster
  quota   Show namespace limits
  image   Download Ubuntu cloud image locally
  upload  Upload image to cluster DataVolume
  vm      Create/start the VirtualMachine
  egress  Apply TenantEgress rules for outbound access
  ssh     Print SSH command
EOF
}

main() {
  local step="${1:-all}"
  require_cmd oc
  require_cmd virtctl
  require_cmd curl

  case "${step}" in
    login)  require_config; step_login ;;
    quota)  require_config; step_login; step_project; step_quota ;;
    image)  step_download_image ;;
    upload) require_config; step_login; step_project; step_download_image; step_upload_image ;;
    vm)     require_config; step_login; step_project; step_apply_vm ;;
    egress) require_config; step_login; step_project; step_apply_egress ;;
    ssh)    step_ssh_hint ;;
    all)
      require_config
      step_project
      step_quota
      step_download_image
      step_upload_image
      step_apply_vm
      step_apply_egress
      step_ssh_hint
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
