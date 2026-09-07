# VM Configuration Examples

This directory contains pre-configured VM templates for different workload sizes.

## Available Configurations

| File | CPUs | Memory | Recommended Disk | Use Case |
|------|------|--------|------------------|----------|
| `vm-small.yaml` | 2 | 4 GiB | 20 GiB | Light development, testing, small scripts |
| `vm-medium.yaml` | 4 | 16 GiB | 40 GiB | ML training, data processing, web services |
| `vm-large.yaml` | 8 | 32 GiB | 80 GiB | Heavy workloads, multiple services, large datasets |
| `vm-xlarge.yaml` | 16 | 64 GiB | 160 GiB | Intensive ML/AI, distributed systems, big data |

---

## Quick Start

### 1. Choose a Configuration

Select the VM size that matches your workload:

```bash
# Copy the example to your workspace
cd /path/to/itup-vm-setup
cp examples/vm-medium.yaml my-vm.yaml
```

### 2. Customize the Configuration

Update three key values in `my-vm.yaml`:

1. **VM name** (appears twice):
   ```yaml
   metadata:
     name: my-custom-vm    # Change this
   
   volumes:
     - name: rootdisk
       dataVolume:
         name: my-custom-vm-image    # Change this to match
   ```

2. **Namespace**:
   ```yaml
   metadata:
     namespace: your-team--pipeline    # Update with your namespace
   ```

3. **SSH key** (at the bottom):
   ```yaml
   ssh_authorized_keys:
     - ssh-rsa AAAA... your-email@example.com    # Paste your public key
   ```

### 3. Upload the Image

Upload the Ubuntu cloud image with the appropriate disk size:

```bash
# Source your environment config
source config.env
export KUBECONFIG="$(pwd)/.kubeconfig"

# Download Ubuntu image (if not already done)
curl -L -O https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Upload with the appropriate size for your VM
# Small: 20Gi, Medium: 40Gi, Large: 80Gi, XLarge: 160Gi
virtctl image-upload dv my-custom-vm-image \
  --image-path=noble-server-cloudimg-amd64.img \
  -n "${NAMESPACE}" \
  --size=40Gi \
  --insecure

# Wait for upload to complete
oc get dv my-custom-vm-image -n "${NAMESPACE}" -w
```

### 4. Create the VM

```bash
oc apply -f my-vm.yaml

# Wait for VM to start
oc get vm,vmi -n "${NAMESPACE}" -w
```

### 5. Connect

```bash
virtctl -n "${NAMESPACE}" ssh ubuntu@vmi/my-custom-vm \
  --identity-file="$HOME/.ssh/id_rsa" \
  --local-ssh-opts="-o IdentitiesOnly=yes"
```

---

## Configuration Details

### CPU Configuration

```yaml
cpu:
  cores: 4        # Number of CPU cores
  sockets: 1      # Usually keep at 1
  threads: 1      # Usually keep at 1
```

- **cores**: Total number of vCPUs for the VM
- **sockets**: Number of physical CPU sockets (virtual)
- **threads**: Threads per core (usually 1 for VMs)

### Memory Configuration

```yaml
memory:
  guest: 16Gi     # Memory visible to the VM
resources:
  requests:
    cpu: 4        # Must match cores above
    memory: 16Gi  # Must match guest above
  limits:
    cpu: 4        # Keep same as requests
    memory: 16Gi  # Keep same as requests
```

**Important:** Keep `requests` and `limits` identical to ensure predictable resource allocation.

### Disk Size

Disk size is set during image upload:

```bash
virtctl image-upload dv <name> --size=<SIZE>
```

Common sizes:
- Development: `20Gi` - `40Gi`
- Data processing: `80Gi` - `160Gi`
- Big data: `200Gi` - `500Gi`

**Note:** Larger disks consume more namespace storage quota.

---

## Checking Quota

Before creating a large VM, check your namespace quota:

```bash
# View current quota usage
oc get appliedclusterresourcequota -n "${NAMESPACE}"

# Detailed quota information
oc describe appliedclusterresourcequota -n "${NAMESPACE}"

# Check specifically for CPU and memory
oc get appliedclusterresourcequota -n "${NAMESPACE}" \
  -o jsonpath='{.status.total.used}{"\n"}{.status.total.hard}{"\n"}'
```

Common quota limits:
- CPU: 10-50 cores per namespace
- Memory: 32Gi-128Gi per namespace
- Storage: 100Gi-500Gi per namespace

---

## Customizing Further

### Add More Disk Volumes

To add additional data volumes:

```yaml
volumes:
  - name: rootdisk
    dataVolume:
      name: my-vm-image
  - name: data-disk
    persistentVolumeClaim:
      claimName: my-data-pvc    # Create this PVC first
```

And add the disk device:

```yaml
devices:
  disks:
    - name: rootdisk
      disk:
        bus: virtio
    - name: data-disk
      disk:
        bus: virtio
```

### Adjust Network Settings

Enable multi-queue for better network performance:

```yaml
devices:
  networkInterfaceMultiqueue: true    # Already enabled in examples
```

### Use Different Ubuntu Versions

To use a different Ubuntu version, download the appropriate cloud image:

- Ubuntu 22.04 (Jammy): `jammy-server-cloudimg-amd64.img`
- Ubuntu 20.04 (Focal): `focal-server-cloudimg-amd64.img`

```bash
curl -L -O https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

---

## Troubleshooting

### VM won't start - quota exceeded

```bash
# Check quota
oc describe appliedclusterresourcequota -n "${NAMESPACE}"

# Solution: Use a smaller VM or request quota increase
```

### Image upload fails

```bash
# Check for stuck DataVolumes
oc get dv -n "${NAMESPACE}"

# Delete failed upload
oc delete dv <name> -n "${NAMESPACE}"
oc delete pvc <name> -n "${NAMESPACE}"

# Retry with smaller disk size
virtctl image-upload dv <name> --size=20Gi ...
```

### VM name conflicts

```bash
# Check existing VMs
oc get vm -n "${NAMESPACE}"

# Delete old VM if needed
oc delete vm <old-vm-name> -n "${NAMESPACE}"
```

---

## Best Practices

1. **Start small**: Begin with `vm-small.yaml` and scale up as needed
2. **Match resources**: Ensure `requests` = `limits` for stable performance
3. **Monitor quota**: Check quota before creating large VMs
4. **Disk planning**: Allocate enough disk space upfront (resizing is complex)
5. **Naming convention**: Use descriptive names like `projectname-workload-vm`
6. **SSH keys**: Keep your public key in a secure, accessible location
7. **Clean up**: Delete unused VMs to free up quota:
   ```bash
   oc delete vm <vm-name> -n "${NAMESPACE}"
   oc delete dv <image-name> -n "${NAMESPACE}"
   ```

---

## Multi-VM Deployments

To run multiple VMs simultaneously:

1. Copy and customize each VM file with unique names
2. Ensure total resources don't exceed quota
3. Upload separate images for each VM (with unique DataVolume names)
4. Apply each VM manifest individually

Example:

```bash
# Create three VMs of different sizes
cp examples/vm-small.yaml dev-vm.yaml
cp examples/vm-medium.yaml staging-vm.yaml
cp examples/vm-large.yaml prod-vm.yaml

# Customize names, SSH keys, and namespace in each file

# Upload images
virtctl image-upload dv dev-vm-image --size=20Gi ...
virtctl image-upload dv staging-vm-image --size=40Gi ...
virtctl image-upload dv prod-vm-image --size=80Gi ...

# Create VMs
oc apply -f dev-vm.yaml
oc apply -f staging-vm.yaml
oc apply -f prod-vm.yaml
```

---

## Next Steps

- See [../README.md](../README.md) for complete setup instructions
- See [../docs/vertex-ai-setup.md](../docs/vertex-ai-setup.md) for Vertex AI configuration
- Customize cloud-init settings in the VM YAML for automated package installation
