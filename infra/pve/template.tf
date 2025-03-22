/*
* Terraform Proxmox templates
* VM and container templates, used to derive others
*/

# Debian Latest CLOUD disk image
resource "proxmox_virtual_environment_download_file" "debian-latest-cloudimg" {
  content_type = "iso"
  datastore_id = "local"
  file_name = "debian-12-generic-amd64.qcow2.img"
  node_name = "pve"
  url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}

# Base cloud-config ('vendor') file for VM templates
resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - git
      - ca-certificates
      - wget
      - curl
      - gnupg2
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF
    file_name = "cloud-config.yaml"
  }
}

# Debian Latest VM template
resource "proxmox_virtual_environment_vm" "debian-latest-template" {
  name = "debian-latest-template"
  description = "Debian latest template VM from Terraform"
  tags = ["debian", "debian-latest", "template", "terraform"]

  node_name = "pve"
  vm_id = 9002
  template = true
  machine = "q35"
  keyboard_layout = "fr"

  agent {
    enabled = true
  }
  stop_on_destroy = true

  cpu {
    cores = 2
    type = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
    floating = 2048
  }

  disk {
    datastore_id = "local-lvm"
    file_id = proxmox_virtual_environment_download_file.debian-latest-cloudimg.id
    interface = "scsi0"
  }

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = "local-lvm"
    interface = "ide2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
      password = var.machine_root_password
      username = "root"
    }

    vendor_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  lifecycle {
    ignore_changes = [ 
      ipv4_addresses, ipv6_addresses, network_interface_names
     ]
  }

  network_device {
    bridge = "vmbr0"
    vlan_id = 2
  }

  operating_system {
    type = "l26"
  }

  tpm_state {
    version = "v2.0"
  }

  serial_device {}
}

# Debian Latest LXC container image
resource "proxmox_virtual_environment_download_file" "debian-latest-lxc-img" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve"
  url = "http://download.proxmox.com/images/system/debian-12-standard_12.7-1_amd64.tar.zst"
}

# Debian Latest LXC container template
resource "proxmox_virtual_environment_container" "debian-latest-container-template" {
  description = "Debian latest template container from Terraform"

  node_name = "pve"
  vm_id = 9003
  template = true

  cpu {
    cores = 2
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size = 4 # 4 Gigabytes
  }

  initialization {
    hostname = "debian-latest-container-template"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
      password = var.machine_root_password
    }
  }

  network_interface {
    name = "veth0"
    vlan_id = 2
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian-latest-lxc-img.id
    type = "debian"
  }
}
