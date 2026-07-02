# ITUP Ubuntu VM — Setup and Access Guide

End-to-end guide for building an Ubuntu Noble VM on ITUP (OpenShift + KubeVirt)
in your ITUP **pipeline** namespace, then connecting from the command line or
Cursor IDE.

> **Public repo note:** Do not commit internal cluster API URLs, namespace names,
> or tokens. Copy `config.env.example` to `config.env` locally (gitignored).

Based on the [ITUP primer for RHOSO engineers](https://docs.google.com/document/d/1WUF7VEQOTDluWPIvi4umQNLe_E4q2V2zmiZsdAz0Fzs).

## What you get

| Item | Value |
|------|-------|
| VM name | `ubuntu-noble-vm` |
| Namespace | your ITUP pipeline namespace (see `config.env`) |
| Cluster API | from ITUP console copy-login-command (see `config.env`) |
| OS | Ubuntu Noble 24.04 |
| Resources | 3 CPU, 8 GiB RAM |
| Disk | 20 GiB DataVolume |
| Login user | `ubuntu` (SSH key only) |

---

## Step 0 — Configure cluster details (local only)

```bash
cd /path/to/itup-vm-setup
cp config.env.example config.env
```

Edit `config.env` with values from the ITUP web console
(**username → Copy login command**):

```bash
CLUSTER_API=https://<CLUSTER_API_SERVER>:6443
NAMESPACE=your-team--pipeline
```

Also update `namespace:` in `ubuntu-vm.yaml`, `tenant-egress-domains.yaml`,
and the namespace in `ssh-config.snippet` to match.

`config.env` is gitignored and must **never** be pushed to GitHub.

---

## Prerequisites

1. Access to your ITUP **pipeline** namespace (not a `--config` namespace)
2. RHOS / ITUP onboarding completed (see internal RHOS Guidance for ITUP & CMDBs)
3. macOS or Linux workstation

---

## Step 1 — Install CLI tools

```bash
brew install openshift-cli virtctl
```

Verify:

```bash
oc version --client
virtctl version --client
```

---

## Step 2 — Log in to the cluster

### Get a token

1. Open the ITUP web console for your cluster
2. Click your **username** (top right)
3. **Copy login command** → **Display token**
4. Copy the token value (starts with `sha256~`)

Tokens expire after a few hours. You will need to refresh when SSH or
`virtctl` stops working.

### Log in

```bash
cd /path/to/itup-vm-setup
cp config.env.example config.env   # if not done already
# shellcheck disable=SC1091
source config.env
export KUBECONFIG="$(pwd)/.kubeconfig"

oc login --token=<YOUR_TOKEN> \
  --server="${CLUSTER_API}" \
  --insecure-skip-tls-verify
```

Verify:

```bash
oc whoami
oc whoami --show-server
```

Expected server: value of `CLUSTER_API` from your `config.env`

---

## Step 3 — Select your namespace

```bash
oc project "${NAMESPACE}"
```

Verify access:

```bash
oc auth can-i create virtualmachines -n "${NAMESPACE}"
oc auth can-i create datavolumes -n "${NAMESPACE}"
```

Both should return `yes`.

List your projects:

```bash
oc projects
```

---

## Step 4 — Configure your SSH key (before creating the VM)

The VM cloud-init config injects your public SSH key at first boot. Edit
`ubuntu-vm.yaml` and replace the `ssh_authorized_keys` entry with your own
public key:

```bash
cat ~/.ssh/id_rsa.pub
```

Update this section in `ubuntu-vm.yaml`:

```yaml
ssh_authorized_keys:
  - ssh-rsa AAAA... your-email@example.com
```

---

## Step 5 — Download the Ubuntu cloud image

```bash
curl -L -O https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

The image is ~600 MB. This file is gitignored and stays on your laptop.

---

## Step 6 — Upload the image to the cluster

Create a DataVolume and upload the image (takes a few minutes):

```bash
export KUBECONFIG="$(pwd)/.kubeconfig"

virtctl image-upload dv ubuntu-noble-image \
  --image-path=noble-server-cloudimg-amd64.img \
  -n "${NAMESPACE}" \
  --size=20Gi \
  --insecure
```

Wait until the DataVolume reports success:

```bash
oc get dv ubuntu-noble-image -n "${NAMESPACE}"
```

Expected phase: `Succeeded`

**Note:** Use `20Gi`, not `100Gi`. Larger sizes consume more tenant NFS
storage quota and can fail with `ErrExceededQuota`.

---

## Step 7 — Create the virtual machine

```bash
oc apply -f ubuntu-vm.yaml
```

Check status:

```bash
oc get vm,vmi -n "${NAMESPACE}"
```

Wait until the VMI shows `Running` and `READY=True`:

```bash
oc get vmi ubuntu-noble-vm -n "${NAMESPACE}"
```

---

## Step 8 — Outbound network (TenantEgress)

The pipeline namespace may already have a `TenantEgress` named `default`. Check:

```bash
oc get tenantegress -n "${NAMESPACE}"
```

If none exists and you have permission, apply the allowlist:

```bash
oc apply -f tenant-egress-domains.yaml
```

This permits outbound access to GitHub, PyPI, Ubuntu mirrors, Quay, OpenDev,
and Red Hat internal networks.

---

## Step 9 — SSH from the command line

### Option A: virtctl (simplest)

```bash
export KUBECONFIG="$(pwd)/.kubeconfig"

virtctl -n "${NAMESPACE}" ssh ubuntu@vmi/ubuntu-noble-vm \
  --identity-file="$HOME/.ssh/id_rsa" \
  --local-ssh-opts="-o IdentitiesOnly=yes" \
  --local-ssh-opts="-o StrictHostKeyChecking=no"
```

### Option B: native SSH via port-forward

Add to `~/.ssh/config`:

```
Include /path/to/itup-vm-setup/ssh-config.snippet
```

Then connect:

```bash
ssh itup-ubuntu-noble
```

Verify:

```bash
ssh itup-ubuntu-noble hostname
# ubuntu-noble-vm
```

### Serial console (fallback)

```bash
virtctl -n "${NAMESPACE}" console ubuntu-noble-vm
```

Exit with `Ctrl+]`.

---

## Step 10 — Connect from Cursor IDE

Cursor uses the same Remote SSH mechanism as VS Code. The VM is not reachable
by IP from your laptop; traffic is tunneled through `virtctl port-forward`.

### 10.1 — Add SSH config (one time)

Add this line to `~/.ssh/config`:

```
Include /path/to/itup-vm-setup/ssh-config.snippet
```

The snippet defines host `itup-ubuntu-noble` with a `ProxyCommand` that runs
`virtctl port-forward` using your local `.kubeconfig`.

### 10.2 — Ensure you are logged in

```bash
export KUBECONFIG=/path/to/itup-vm-setup/.kubeconfig
oc whoami   # must succeed
```

If not, get a fresh token from the ITUP console and re-run `oc login` (Step 2).

### 10.3 — Connect in Cursor

1. `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Linux)
2. **Remote-SSH: Connect to Host...**
3. Select **`itup-ubuntu-noble`**
4. When connected: **File → Open Folder** → `/home/ubuntu`

You now have a full remote workspace on the VM.

### 10.4 — Token refresh

Console tokens expire. When Cursor SSH fails:

```bash
export KUBECONFIG=/path/to/itup-vm-setup/.kubeconfig
source /path/to/itup-vm-setup/config.env
oc login --token=<NEW_TOKEN> \
  --server="${CLUSTER_API}" \
  --insecure-skip-tls-verify
```

There is no unlimited-lifetime user token. For long-running automation, ask
your ITUP admin about a service account token.

---

## Automated setup (optional)

Instead of Steps 5–8 manually, run the helper script:

```bash
export KUBECONFIG="$(pwd)/.kubeconfig"
chmod +x setup.sh
./setup.sh
```

Individual steps:

```bash
./setup.sh login    # authenticate
./setup.sh image    # download Ubuntu image
./setup.sh upload   # upload to cluster
./setup.sh vm       # create VM
./setup.sh egress   # apply TenantEgress (if permitted)
./setup.sh ssh      # print SSH command
```

---

## Troubleshooting

### Check VM and image status

```bash
oc get dv,vm,vmi -n "${NAMESPACE}"
oc describe vmi ubuntu-noble-vm -n "${NAMESPACE}"
```

### Upload stuck or quota error

```bash
oc describe dv ubuntu-noble-image -n "${NAMESPACE}"
oc get appliedclusterresourcequota -n "${NAMESPACE}"
```

Common fix: delete failed upload resources and retry with `--size=20Gi`:

```bash
oc delete dv ubuntu-noble-image -n "${NAMESPACE}"
oc delete pvc ubuntu-noble-image -n "${NAMESPACE}"
# also delete any prime-* PVCs left behind
```

### SSH / Cursor connection fails

| Symptom | Fix |
|---------|-----|
| `Unauthorized` or `connection refused` | Refresh `oc login` token |
| `Permission denied (publickey)` | Key in `ubuntu-vm.yaml` must match `~/.ssh/id_rsa.pub` |
| `virtctl: command not found` | `brew install virtctl` |
| Host not in Cursor list | Confirm `Include` line in `~/.ssh/config` |

### Check tenant storage usage

```bash
oc get appliedclusterresourcequota \
  -n "${NAMESPACE}" \
  -o jsonpath='{.status.total.used}{"\n"}{.status.total.hard}{"\n"}'
```

---

## Repository files

| File | Purpose |
|------|---------|
| `README.md` | This guide |
| `ubuntu-vm.yaml` | KubeVirt VirtualMachine manifest |
| `tenant-egress-domains.yaml` | Outbound network allowlist (optional) |
| `config.env.example` | Template for local cluster/namespace config |
| `setup.sh` | Automated setup script |
| `ssh-config.snippet` | SSH config for CLI and Cursor Remote SSH |
| `.gitignore` | Ignores credentials, images, and `config.env` |

Local files (not committed):

| File | Purpose |
|------|---------|
| `config.env` | Your cluster API URL and namespace |
| `.kubeconfig` | Cluster credentials (created by `oc login`) |
| `noble-server-cloudimg-amd64.img` | Downloaded Ubuntu cloud image |

---

## Customization

| Setting | Where to change |
|---------|-----------------|
| Cluster API / namespace | `config.env` (from ITUP console) |
| VM name | `metadata.name` in `ubuntu-vm.yaml`, `VM_NAME` in `setup.sh` |
| CPU / memory | `spec.template.spec.domain` in `ubuntu-vm.yaml` |
| Disk size | `--size` in upload command, `DATAVOLUME_SIZE` in `setup.sh` |
| SSH key | `ssh_authorized_keys` in `ubuntu-vm.yaml` |
| SSH host alias | `Host itup-ubuntu-noble` in `ssh-config.snippet` |
