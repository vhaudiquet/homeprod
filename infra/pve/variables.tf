variable "api_token" {
  description = "Token to connect Proxmox API"
  type = string
}

variable "machine_root_password" {
  description = "Root password for VMs and containers"
  type = string
}

variable "ssh_public_key" {
  description = "Public SSH key authorized access for VMs and containers"
  type = string
}

variable "sops_private_key" {
  description = "Private SOPS GPG key for flux/kubernetes to decrypt secrets"
  type = string
}