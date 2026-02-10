# Cloud-Init

## YouTube Video
- [Cloud-Init Explained](https://www.youtube.com/watch?v=sb3PuGLT0RM&lc=Ugx_X6r_JHal_YsUUyd4AaABAg)
## What this page contains
Notes and example files used in the Cloud-Init video.

## Files
- Example configs: `videos/cloud-init/`

## Notes

**Proxmox Template Creation Walkthrough**
```bash
# 1) Download cloud image (example: Ubuntu 22.04 Jammy)
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

#####
FOR GUI
cd /ssd-pool/import
qemu-img info jammy-server-cloudimg-amd64.img
qemu-img convert -f qcow2 -O raw jammy-server-cloudimg-amd64.img jammy-server-cloudimg-amd64.raw
#####

# 2) Create VM shell
qm create 9000 \
  --name ubuntu-2204-cloudinit \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0

# 3) Import disk into your VM storage (example: ssd-pool)
qm importdisk 9000 jammy-server-cloudimg-amd64.img ssd-pool

# 4) Attach imported disk
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 ssd-pool:vm-9000-disk-0

# 5) Add Cloud-Init drive
qm set 9000 --ide2 ssd-pool:cloudinit

# 6) Boot config (explicit boot order)
qm set 9000 --boot order=scsi0

# 7) Serial console (cloud images love this)
qm set 9000 --serial0 socket --vga serial0

# Optional but recommended: QEMU guest agent (install it via cloud-init later)
qm set 9000 --agent enabled=1

# 8) Convert to template
qm template 9000
```

---

**Terraform template files**

They use **placeholders** like `REPLACE_ME`, `${ADMIN_USER}`, etc.

---

## `cloudinit.yaml.tftpl` — Cloud-Init user-data template

**What it does:** Creates a user, injects an SSH key, installs packages, enables qemu-guest-agent, and writes a simple MOTD script.

```yaml
#cloud-config
hostname: ${HOSTNAME}

manage_etc_hosts: true

users:
  - default
  - name: ${ADMIN_USER}
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

package_update: true

packages:
  - qemu-guest-agent
  - sl   # example package (replace or remove)

write_files:
  - path: /etc/update-motd.d/99-ip
    permissions: "0755"
    content: |
      #!/bin/bash
      echo ""
      echo "=== YOUR LAB NAME ==="
      echo -n "Hostname: "
      hostname
      echo -n "IPv4: "
      ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | paste -sd "," -
      echo ""

runcmd:
  - systemctl enable --now qemu-guest-agent
```

---

## `providers.tf` — Provider definition + Proxmox connection settings

**What it does:** Pins the Proxmox provider and configures access using variables (endpoint + API token).

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token

  # Template-friendly default:
  # Set to false in real deployments once you have valid TLS
  insecure = var.pve_insecure

  # Optional: lets the provider use SSH for some operations
  ssh {
    username = var.pve_ssh_user
    agent    = true
  }
}
```

---

## `main.tf` — Creates per-VM cloud-init snippet + clones VMs from template

**What it does:**

- Builds a VM list (`lab-01`, `lab-02`, etc.)
- Uploads a _per-VM_ cloud-init snippet to Proxmox    
- Clones VMs from your Cloud-Init template VMID
    

```hcl
locals {
  vm_numbers = [for i in range(var.vm_start_index, var.vm_start_index + var.vm_count) : i]

  vms = {
    for n in local.vm_numbers :
    tostring(n) => {
      number   = n
      name     = format("%s-%02d", var.vm_prefix, n)
      hostname = format("%s-%02d", var.vm_prefix, n)
    }
  }

  ssh_public_key = trimspace(file(pathexpand(var.ssh_pubkey_path)))
}

resource "proxmox_virtual_environment_file" "user_data" {
  for_each     = local.vms
  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = var.node_name
  overwrite    = true

  source_raw {
    file_name = "${each.value.name}-user-data.yaml"
    data = templatefile("${path.module}/cloudinit.yaml.tftpl", {
      hostname       = each.value.hostname
      ssh_public_key = local.ssh_public_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each  = local.vms
  name      = each.value.name
  node_name = var.node_name

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  cpu {
    cores = var.vm_cores
    type  = "host"
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.vm_disk_gb
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  initialization {
    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id

    ip_config {
      ipv4 { address = "dhcp" }
    }

    # NOTE:
    # We intentionally do NOT use user_account here.
    # User + SSH keys are created inside cloud-init user-data (cloudinit.yaml.tftpl),
    # which is more reliable across images/templates.
  }

  agent { enabled = true }

  depends_on = [proxmox_virtual_environment_file.user_data]
}
```

---

## `outputs.tf` — Prints VM IP addresses (from guest agent)

**What it does:** Shows all IPv4s + a “primary” IPv4 for each VM name.

```hcl
output "vm_ipv4s" {
  value = {
    for _, vm in proxmox_virtual_environment_vm.vm :
    vm.name => try(flatten(vm.ipv4_addresses), [])
  }
}

output "vm_primary_ipv4" {
  value = {
    for _, vm in proxmox_virtual_environment_vm.vm :
    vm.name => try(
      [for ip in flatten(vm.ipv4_addresses) : ip if ip != "127.0.0.1"][0],
      null
    )
  }
}
```

---

## `variables.tf`

**What it does:** Declares all inputs and defaults in a safe way.

```hcl
variable "pve_endpoint" {
  type        = string
  description = "Proxmox API endpoint, e.g. https://PVE_HOSTNAME_OR_IP:8006/api2/json"
}

variable "pve_api_token" {
  type        = string
  sensitive   = true
  description = "Token format: user@realm!tokenid=SECRET"
}

variable "pve_insecure" {
  type        = bool
  description = "Set true to skip TLS verification (template-friendly). Prefer false with valid TLS."
  default     = true
}

variable "pve_ssh_user" {
  type        = string
  description = "SSH user for optional provider SSH operations"
  default     = "root"
}

variable "node_name" {
  type        = string
  description = "Proxmox node name (left tree name), e.g. PVE_NODE_NAME"
}

variable "template_vmid" {
  type        = number
  description = "VMID of the Cloud-Init template"
  default     = 9000
}

variable "datastore_id" {
  type        = string
  description = "Storage ID for VM disk + cloud-init drive (e.g. ssd-pool)"
  default     = "DATASTORE_ID_REPLACE_ME"
}

variable "snippets_datastore_id" {
  type        = string
  description = "Storage ID that supports snippets (often 'local')"
  default     = "SNIPPETS_DATASTORE_ID_REPLACE_ME"
}

variable "bridge" {
  type        = string
  description = "Bridge to attach the VM NIC to (e.g. vmbr0)"
  default     = "vmbr0"
}

variable "vm_prefix" {
  type        = string
  description = "Prefix for VM names/hostnames"
  default     = "vm"
}

variable "vm_count" {
  type        = number
  description = "How many VMs to create"
  default     = 1
}

variable "vm_start_index" {
  type        = number
  description = "Start index for numbering (1 => vm-01)"
  default     = 1
}

variable "vm_cores" {
  type        = number
  description = "VM vCPU cores"
  default     = 2
}

variable "vm_memory_mb" {
  type        = number
  description = "VM memory in MB"
  default     = 2048
}

variable "vm_disk_gb" {
  type        = number
  description = "VM disk size in GB"
  default     = 20
}

variable "ssh_pubkey_path" {
  type        = string
  description = "Path to SSH public key to inject (public key only)"
  default     = "~/.ssh/id_ed25519.pub"
}
```

---

## `terraform.tfvars.example`

**What it does:** Gives a clear starting point without exposing your real values.

```hcl
# Proxmox connection
pve_endpoint  = "https://PVE_HOSTNAME_OR_IP:8006/api2/json"
pve_api_token = "USER@REALM!TOKEN_ID=SECRET_REPLACE_ME"
pve_insecure  = true
pve_ssh_user  = "root"

# Proxmox targets
node_name            = "PVE_NODE_NAME"
template_vmid        = 9000
datastore_id         = "DATASTORE_ID_REPLACE_ME"
snippets_datastore_id = "SNIPPETS_DATASTORE_ID_REPLACE_ME"
bridge               = "vmbr0"

# VM batch settings
vm_prefix      = "lab"
vm_count       = 3
vm_start_index = 1

# SSH key injection (public key path)
ssh_pubkey_path = "~/.ssh/id_ed25519.pub"
```

