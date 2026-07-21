# Variables for the P330 Talos worker node that joins the r740 cluster.

variable "p330_host" {
  description = "Reachable IP/hostname of the P330 Talos node (for Talos API access)."
  type        = string
}

variable "p330_node_name" {
  description = "Kubernetes/Talos node name for the P330 (e.g. p330)."
  type        = string
  default     = "p330"
}

variable "r740_state_path" {
  description = <<EOT
Path to the Terraform state of the r740 kube module, used by terraform_remote_state
to read the cluster secrets and endpoint so this node can join the existing cluster.
Path is resolved by terraform_remote_state relative to the working directory where
terraform runs (this module dir). The default points two levels up to the repo
root and back down to the r740 kube module.
EOT
  type        = string
  default     = "../../r740/kube"
}

variable "r740_backend" {
  description = <<EOT
Terraform backend type used by the r740 kube module.
Set to "local" (default) when r740 uses a local tfstate file in its own directory,
or the matching remote backend name ("s3", "remote", ...) if the r740 module uses
a configured backend.
EOT
  type        = string
  default     = "local"
}

variable "r740_backend_config" {
  description = <<EOT
Backend configuration map passed to terraform_remote_state when r740_backend is
not "local". For a local backend this is ignored.
EOT
  type        = map(string)
  default     = {}
}

variable "installer_image" {
  description = <<EOT
Talos installer image to use on the P330 (bare metal).
Must be a **metal** Image Factory build that includes ixgbe.allow_unsupported_sfp=1
in the kernel command line (sd-boot/UKI ignores machine.install.extraKernelArgs, so
the param must be baked into the image). The default is a custom factory build
(a18165114...).
EOT
  type        = string
  default     = "factory.talos.dev/installer/a18165114f80c28601d05bc4ff1f6ea6d6b214882c5b9af7928aaf4d09741beb:v1.13.6"
}

variable "install_disk" {
  description = "Block device path to install Talos on (e.g. /dev/sda, /dev/nvme0n1)."
  type        = string
  default     = "/dev/nvme0n1"
}

variable "node_subnet" {
  description = <<EOT
Static IPv4 address in CIDR notation for the P330 node (e.g. 10.1.2.132/24).
Set to null to use DHCP. A static address is recommended for a failover node so
DNS/affinity rules stay stable.
EOT
  type        = string
  default     = "10.1.2.132/24"
}

variable "node_gateway" {
  description = "IPv4 gateway for the P330 node. Ignored when node_subnet is null."
  type        = string
  default     = "10.1.2.1"
}

variable "network_interface" {
  description = <<EOT
Primary network interface name on the P330. Defaults to enp3s0f1 (the 10G Intel
X520 NIC), which must be on the same L2/subnet as the r740 control plane so etcd
peer traffic (TLS-verified against the r740's etcd cert SANs) doesn't cross a
router. eno1 (1G) is left unconfigured.
EOT
  type        = string
  default     = "enp3s0f1"
}

variable "nameservers" {
  description = "DNS nameservers configured on the node (must work independently of kube)."
  type        = list(string)
  default     = ["10.1.2.148", "1.1.1.1"]
}

variable "failover_taint_key" {
  description = "Taint key applied to the node to reserve it for failover workloads."
  type        = string
  default     = "dedicated"
}

variable "failover_taint_value" {
  description = "Taint value applied to the node."
  type        = string
  default     = "failover"
}

variable "failover_taint_effect" {
  description = "Taint effect applied to the node (NoSchedule / NoExecute)."
  type        = string
  default     = "NoSchedule"

  validation {
    condition     = contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], var.failover_taint_effect)
    error_message = "failover_taint_effect must be NoSchedule, PreferNoSchedule or NoExecute."
  }
}
