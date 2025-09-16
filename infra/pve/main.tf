# Terraform providers configuration
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.83.2"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    helm = {
      source = "hashicorp/helm"
      version = "2.17.0"
    }
  }
}

# Proxmox configuration
provider "proxmox" {
  endpoint = "https://pve.lan:8006/"
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
