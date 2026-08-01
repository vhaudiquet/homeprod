# Variables for the Raspberry Pi 4 Talos control-plane node that joins the r740
# "kube" cluster as a third etcd member to restore quorum (2-of-3 majority).
#
# Secret handling: the cluster machine secrets (cluster id/secret, etcd/k8s
# certs, bootstrap token) are NOT read from terraform state (the r740 state is
# stale) and are NOT generated here (that would create a new, incompatible
# cluster). Instead they are provided via `machine_secrets_file` — a local,
# gitignored JSON file in the Talos provider's machine_secrets format. The
# file is produced once from the live r740 node (see
# scripts/extract-talos-secrets.sh) and stored in a real secret manager
# (Bitwarden); you paste it back to disk when running this module. Ephemeral
# resources + write-only attributes ensure the secrets never land in Terraform
# state.

variable "rpi4_host" {
  description = "Reachable IP/hostname of the rpi4 Talos node (for Talos API access). With DHCP this is the leased IP (e.g. 10.1.2.135)."
  type        = string
}

variable "rpi4_node_name" {
  description = "Kubernetes/Talos node name for the rpi4 (e.g. rpi4). Pinned via machine.network.hostname so the node registers with this name regardless of DHCP."
  type        = string
  default     = "rpi4"
}

# --- Cluster identity (no terraform_remote_state — state is stale) ----------

variable "cluster_name" {
  description = "Name of the existing Talos cluster the rpi4 joins. Must match the cluster the r740 bootstrapped (kube-r740)."
  type        = string
  default     = "kube-r740"
}

variable "cluster_endpoint" {
  description = "Endpoint (host:port) of the Talos/Kubernetes API on the cluster. Must match the r740 bootstrap endpoint."
  type        = string
  default     = "https://kube-r740.lan:6443"
}

# --- Secrets (provided manually, never in state) ---------------------------

variable "machine_secrets_file" {
  description = <<EOT
Path to a local, gitignored JSON file containing the cluster machine secrets in
the Talos provider's machine_secrets format (cluster.id, cluster.secret, certs,
secrets.bootstrap_token, secrets.secretbox_encryption_secret, trustdinfo.token).
Generate it once from the live r740 node with
scripts/extract-talos-secrets.sh, store the contents in Bitwarden, and paste it
back to this file when running this module. The file MUST be gitignored — it
contains the cluster root of trust.
EOT
  type        = string
  default     = "secrets.json"
}

# --- Install / network -----------------------------------------------------

variable "installer_image" {
  description = <<EOT
Talos installer image to use on the rpi4 (bare metal, ARM64).
Must be an ARM64 Image Factory build (schematic generated at
https://factory.talos.dev) for the Raspberry Pi 4 platform. Unlike the x86
control-plane nodes, this quorum node does NOT need the iSCSI/Longhorn
extensions because no user workloads or Longhorn replicas are scheduled on it
(the quorum taint keeps it empty); only essential DaemonSets (Cilium, etc.)
land here.
EOT
  type        = string
  default     = "factory.talos.dev/installer/ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9:v1.13.6"
}

variable "install_disk" {
  description = "Block device path to install Talos on. For the rpi4 booting from the SD card this is /dev/mmcblk0."
  type        = string
  default     = "/dev/mmcblk0"
}

variable "node_subnet" {
  description = <<EOT
Static IPv4 address in CIDR notation for the rpi4 node (e.g. 10.1.2.135/24).
Set to null (default) to use DHCP. The rpi4 uses DHCP, so a static address is
not required; the node registers with Kubernetes under rpi4_node_name regardless
of the leased IP.
EOT
  type        = string
  default     = null
}

variable "node_gateway" {
  description = "IPv4 gateway for the rpi4 node. Ignored when node_subnet is null (DHCP)."
  type        = string
  default     = null
}

variable "network_interface" {
  description = <<EOT
Primary network interface name on the rpi4. The built-in Ethernet port is eth0.
EOT
  type        = string
  default     = "eth0"
}

variable "nameservers" {
  description = "DNS nameservers configured on the node (must work independently of kube)."
  type        = list(string)
  default     = ["10.1.2.148", "1.1.1.1"]
}

# --- Quorum taint ----------------------------------------------------------

variable "quorum_taint_key" {
  description = "Taint key applied to the node to reserve it as a quorum-only member (no user workloads)."
  type        = string
  default     = "dedicated"
}

variable "quorum_taint_value" {
  description = "Taint value applied to the node."
  type        = string
  default     = "quorum"
}

variable "quorum_taint_effect" {
  description = "Taint effect applied to the node. NoSchedule is sufficient: essential DaemonSets (Cilium, etc.) tolerate it for networking, but no user workloads are admitted."
  type        = string
  default     = "NoSchedule"

  validation {
    condition     = contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], var.quorum_taint_effect)
    error_message = "quorum_taint_effect must be NoSchedule, PreferNoSchedule or NoExecute."
  }
}

# --- Kubeconfig for the label/taint null_resource --------------------------

variable "kubeconfig_path" {
  description = <<EOT
Path to a kubeconfig for the cluster, used by the null_resource that waits for
the node and applies the quorum label/taint. This is NOT stored in state — it is
only referenced inside a local-exec provisioner. Point it at the r740 kube
module's kubeconfig (../../r740/kube/kubeconfig) or any valid kubeconfig for the
cluster.
EOT
  type        = string
  default     = "../../r740/kube/kubeconfig"
}
