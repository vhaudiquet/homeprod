variable "proxmox_host" {
  description = "Hostname of Proxmox server"
  type = string
}

variable "proxmox_node_name" {
  description = "Name of Proxmox node to use"
  type = string
}

variable "proxmox_api_token" {
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

variable "ssh_secondary_key" {
  description = "Secondary SSH key for authorized access to specific VMs and containers"
  type = string
}
