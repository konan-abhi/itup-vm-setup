#!/usr/bin/env bash
#
# Helper script to create a custom VM from templates
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="${KUBECONFIG:-${SCRIPT_DIR}/.kubeconfig}"

if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/config.env"
fi

NAMESPACE="${NAMESPACE:-}"
IMAGE_FILE="noble-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
  echo -e "\n${GREEN}=== $1 ===${NC}\n"
}

print_error() {
  echo -e "${RED}ERROR: $1${NC}" >&2
}

print_warning() {
  echo -e "${YELLOW}WARNING: $1${NC}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <vm-name> <size> [disk-size]

Create a custom VM from templates.

Arguments:
  vm-name     Name for your VM (e.g., 'ml-training-vm')
  size        VM size: small, medium, large, xlarge
  disk-size   Optional disk size (default: 20Gi for small, 40Gi for medium, etc.)

VM Sizes:
  small   - 2 CPU,  4 GiB RAM  (default disk: 20Gi)
  medium  - 4 CPU, 16 GiB RAM  (default disk: 40Gi)
  large   - 8 CPU, 32 GiB RAM  (default disk: 80Gi)
  xlarge  - 16 CPU, 64 GiB RAM (default disk: 160Gi)

Examples:
  $(basename "$0") ml-training-vm medium
  $(basename "$0") ml-training-vm medium 100Gi
  $(basename "$0") dev-vm small 30Gi

Environment:
  Requires config.env with NAMESPACE and CLUSTER_API set.
  Run 'oc login' before using this script.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print_error "'$1' not found. Install it first (see README.md)."
    exit 1
  fi
}

check_quota() {
  local cpu=$1
  local memory=$2

  print_header "Checking Namespace Quota"

  if ! oc get appliedclusterresourcequota -n "${NAMESPACE}" >/dev/null 2>&1; then
    print_warning "Cannot check quota. Proceeding anyway."
    return
  fi

  echo "Current quota usage:"
  oc get appliedclusterresourcequota -n "${NAMESPACE}" \
    -o custom-columns=NAME:.metadata.name,CPU-USED:.status.total.used.cpu,CPU-HARD:.status.total.hard.cpu,MEM-USED:.status.total.used.memory,MEM-HARD:.status.total.hard.memory 2>/dev/null || true

  echo
  print_warning "Ensure you have at least ${cpu} CPU and ${memory} memory available."
  echo
}

main() {
  if [[ $# -lt 2 ]]; then
    usage
    exit 1
  fi

  local vm_name="$1"
  local size="$2"
  local disk_size="${3:-}"

  # Validate VM name
  if [[ ! "$vm_name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    print_error "Invalid VM name. Use lowercase alphanumeric with hyphens."
    exit 1
  fi

  # Determine template and defaults
  local template_file
  local default_disk
  local cpu_count
  local memory_size

  case "$size" in
    small)
      template_file="${SCRIPT_DIR}/examples/vm-small.yaml"
      default_disk="20Gi"
      cpu_count="2"
      memory_size="4Gi"
      ;;
    medium)
      template_file="${SCRIPT_DIR}/examples/vm-medium.yaml"
      default_disk="40Gi"
      cpu_count="4"
      memory_size="16Gi"
      ;;
    large)
      template_file="${SCRIPT_DIR}/examples/vm-large.yaml"
      default_disk="80Gi"
      cpu_count="8"
      memory_size="32Gi"
      ;;
    xlarge)
      template_file="${SCRIPT_DIR}/examples/vm-xlarge.yaml"
      default_disk="160Gi"
      cpu_count="16"
      memory_size="64Gi"
      ;;
    *)
      print_error "Invalid size. Choose: small, medium, large, or xlarge"
      usage
      exit 1
      ;;
  esac

  # Use provided disk size or default
  disk_size="${disk_size:-$default_disk}"

  # Check prerequisites
  require_cmd oc
  require_cmd virtctl
  require_cmd curl

  if [[ -z "${NAMESPACE}" ]]; then
    print_error "NAMESPACE not set in config.env"
    exit 1
  fi

  # Check if logged in
  if ! oc whoami >/dev/null 2>&1; then
    print_error "Not logged in. Run 'oc login' first."
    exit 1
  fi

  print_header "Creating VM: ${vm_name}"
  echo "Size:      ${size} (${cpu_count} CPU, ${memory_size} RAM)"
  echo "Disk:      ${disk_size}"
  echo "Namespace: ${NAMESPACE}"
  echo

  # Check quota
  check_quota "${cpu_count}" "${memory_size}"

  # Get SSH key
  local ssh_key
  if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
    ssh_key=$(cat "$HOME/.ssh/id_rsa.pub")
  elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    ssh_key=$(cat "$HOME/.ssh/id_ed25519.pub")
  else
    print_error "No SSH public key found at ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub"
    exit 1
  fi

  # Create customized VM YAML
  local vm_file="${SCRIPT_DIR}/${vm_name}.yaml"
  local image_name="${vm_name}-image"

  print_header "Generating VM Configuration"

  sed -e "s/ubuntu-[a-z]*-vm/${vm_name}/g" \
      -e "s/your-team--pipeline/${NAMESPACE}/g" \
      -e "s|REPLACE_WITH_YOUR_SSH_PUBLIC_KEY|${ssh_key}|g" \
      "${template_file}" > "${vm_file}"

  echo "Created: ${vm_file}"

  # Download image if needed
  print_header "Checking Ubuntu Cloud Image"

  if [[ ! -f "${SCRIPT_DIR}/${IMAGE_FILE}" ]]; then
    echo "Downloading Ubuntu Noble cloud image (~600MB)..."
    curl -L -o "${SCRIPT_DIR}/${IMAGE_FILE}" "${IMAGE_URL}"
  else
    echo "Image already downloaded: ${IMAGE_FILE}"
  fi

  # Upload image
  print_header "Uploading Image to Cluster"

  if oc get dv "${image_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    print_warning "DataVolume '${image_name}' already exists. Skipping upload."
  else
    echo "Uploading ${disk_size} DataVolume (this may take several minutes)..."
    virtctl image-upload dv "${image_name}" \
      --image-path="${SCRIPT_DIR}/${IMAGE_FILE}" \
      -n "${NAMESPACE}" \
      --size="${disk_size}" \
      --insecure

    echo "Waiting for DataVolume to be ready..."
    oc wait --for=condition=Ready dv/"${image_name}" -n "${NAMESPACE}" --timeout=10m || {
      print_warning "DataVolume not ready yet. Check with: oc get dv ${image_name} -n ${NAMESPACE}"
    }
  fi

  # Create VM
  print_header "Creating Virtual Machine"

  if oc get vm "${vm_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    print_warning "VM '${vm_name}' already exists."
  else
    oc apply -f "${vm_file}"
    echo "VM created successfully."
  fi

  # Wait for VM to start
  echo "Waiting for VM to start..."
  sleep 5

  oc get vm,vmi -n "${NAMESPACE}" -l "kubevirt.io/domain=${vm_name}" || {
    oc get vm,vmi "${vm_name}" -n "${NAMESPACE}" 2>/dev/null || true
  }

  # Print connection info
  print_header "VM Created Successfully"

  echo "VM Name:   ${vm_name}"
  echo "Namespace: ${NAMESPACE}"
  echo "Size:      ${size} (${cpu_count} CPU, ${memory_size} RAM, ${disk_size} disk)"
  echo
  echo "Connect with:"
  echo "  virtctl -n ${NAMESPACE} ssh ubuntu@vmi/${vm_name} \\"
  echo "    --identity-file=\"\$HOME/.ssh/id_rsa\" \\"
  echo "    --local-ssh-opts=\"-o IdentitiesOnly=yes\""
  echo
  echo "Check status:"
  echo "  oc get vmi ${vm_name} -n ${NAMESPACE}"
  echo
  echo "Delete VM:"
  echo "  oc delete vm ${vm_name} -n ${NAMESPACE}"
  echo "  oc delete dv ${image_name} -n ${NAMESPACE}"
  echo
}

main "$@"
