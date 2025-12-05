resource "proxmox_virtual_environment_download_file" "ubuntu-questing-cloudimg" {
  content_type = "iso"
  datastore_id = "local"
  file_name = "questing-server-cloudimg-amd64.img"
  node_name = var.proxmox_node_name
  url = "https://cloud-images.ubuntu.com/questing/current/questing-server-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_file" "build-latest-cloud-config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

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
      - build-essential
      - sbuild
      - mmdebstrap
      - qemu-user-binfmt
      - ubuntu-dev-tools
      - micro
    runcmd:
      - systemctl enable --now qemu-guest-agent
      - snap install lxd
      - lxd init --auto
      - snap install snapcraft --classic
      - usermod --add-subuids 100000-165535 --add-subgids 100000-165535 root
      - mkdir -p /root/.config/sbuild/
      - mkdir -p /root/.cache/sbuild/
      - echo -e "\$chroot_mode = 'unshare';\n\$unshare_mmdebstrap_keep_tarball = 1;\n1;\n" >/root/.config/sbuild/config.pl
    EOF
    file_name = "build-latest-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "build-latest" {
  name = "bw-${var.proxmox_node_name}"
  node_name = var.proxmox_node_name
  on_boot = true

  agent {
    enabled = true
  }

  tags = ["ubuntu", "ubuntu-questing", "docker", "terraform", "build"]

  cpu {
    type = "host"
    cores = 20
    sockets = 1
    flags = []
  }

  memory {
    dedicated = 64536
    floating = 16192
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
    vlan_id = 2
  }

  lifecycle {
    ignore_changes = [
      network_interface_names,
      mac_addresses,
      ipv4_addresses,
      ipv6_addresses,
      id,
      disk,
      initialization,
      vga
    ]
  }

  boot_order = ["scsi0"]
  scsi_hardware = "virtio-scsi-single"

  vga {
    type = "serial0"
  }

  disk {
    interface = "scsi0"
    iothread = true
    datastore_id = "local-lvm"
    size = 330
    discard = "ignore"
    file_id = proxmox_virtual_environment_download_file.ubuntu-questing-cloudimg.id
  }

  vm_id = 201

  initialization {
    datastore_id = "local-lvm"
    interface = "ide2"
    
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key), trimspace(var.ssh_secondary_key)]
      password = var.machine_root_password
      username = "root"
    }

    vendor_data_file_id = proxmox_virtual_environment_file.build-latest-cloud-config.id
  }

  operating_system {
    type = "l26"
  }

  tpm_state {
    version = "v2.0"
  }

  serial_device {}
}
