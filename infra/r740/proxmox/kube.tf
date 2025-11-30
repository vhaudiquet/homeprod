resource "proxmox_virtual_environment_download_file" "talos-cloudimg" {
  content_type = "iso"
  datastore_id = "local"
  file_name = "talos-v1.11.1-nocloud-amd64.iso"
  node_name = var.proxmox_node_name
  url = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.11.1/nocloud-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "kube" {
  name = "kube-${var.proxmox_node_name}"
  description = "Kubernetes Talos Linux"
  tags = ["kubernetes", "talos", "terraform"]

  node_name = var.proxmox_node_name
  vm_id = 702
  machine = "q35"
  keyboard_layout = "fr"

  agent {
    enabled = true
  }
  stop_on_destroy = true

  cpu {
    cores = 40
    sockets = 2
    type = "host"
  }

  memory {
    dedicated = 32768
    floating = 32768
  }

  boot_order = ["scsi0", "ide0"]
  scsi_hardware = "virtio-scsi-single"

  cdrom {
    file_id = proxmox_virtual_environment_download_file.talos-cloudimg.id
    interface = "ide0"
  }

  disk {
    interface = "scsi0"
    iothread = true
    datastore_id = "local-lvm"
    size = 128
    discard = "ignore"
    file_format = "raw"
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
  }

  lifecycle {
    ignore_changes = [ 
      ipv4_addresses, ipv6_addresses, network_interface_names
     ]
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
    # mac_address = "BC:24:11:F6:E1:C9"
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
