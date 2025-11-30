terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.81.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://${var.proxmox_host}:8006/"
  api_token = var.proxmox_api_token
  insecure = true
  ssh {
    agent    = true
    username = "root"
  }
}
