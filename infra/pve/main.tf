# Terraform providers configuration
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.69.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.1"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.36.0"
    }
    helm = {
      source = "hashicorp/helm"
      version = "2.17.0"
    }
  }
}

# Proxmox configuration
provider "proxmox" {
  endpoint = "https://pve.local:8006/"
  api_token = var.api_token
  insecure = true
  ssh {
    agent    = true
    username = "root"
  }
}

# Talos configuration
provider "talos" {}

# Kubernetes configuration
provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}
# Helm configuration
provider "helm" {
  kubernetes {
    config_path = "${path.module}/kubeconfig"
  }
}

# debian-latest vm template(s), cloned to make other vms
data "proxmox_virtual_environment_vms" "debian_vm_template" {
    node_name = "pve"
    tags = ["template", "debian-latest"]
}
