resource "proxmox_virtual_environment_download_file" "debian-latest-cloudimg" {
  content_type = "iso"
  datastore_id = "local"
  file_name = "debian-13-generic-amd64.qcow2.img"
  node_name = var.proxmox_node_name
  url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

resource "proxmox_virtual_environment_file" "docker-machine-cloud-config" {
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
      - nfs-common
    runcmd:
      - systemctl enable --now qemu-guest-agent
      - install -m 0755 -d /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
      - chmod a+r /etc/apt/keyrings/docker.asc
      - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      - apt-get update
      - apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      - docker swarm init
      - git clone https://github.com/vhaudiquet/homeprod /root/homeprod
      - mkdir /app
      - echo "truenas.lan:/mnt/fast_app_data/docker-homeprod      /app     nfs     defaults,_netdev    0 0" >>/etc/fstab
      - mount -t nfs truenas.lan:/mnt/fast_app_data/docker-homeprod /app
    EOF
    file_name = "docker-machine-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "docker-machine" {
  name = "docker-${var.proxmox_node_name}"
  node_name = var.proxmox_node_name
  on_boot = true

  agent {
    enabled = true
  }

  tags = ["debian", "debian-latest", "docker", "terraform"]

  cpu {
    type = "host"
    cores = 40
    sockets = 2
    flags = []
  }

  memory {
    floating = 16192
    dedicated = 38768
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
    size = 128
    discard = "ignore"
    file_id = proxmox_virtual_environment_download_file.debian-latest-cloudimg.id
  }

  vm_id = 701

  initialization {
    datastore_id = "local-lvm"
    interface = "ide2"
    
    ip_config {
      ipv4 {
        address = "10.1.2.212/24"
        gateway = "10.1.2.1"
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
      password = var.machine_root_password
      username = "root"
    }

    vendor_data_file_id = proxmox_virtual_environment_file.docker-machine-cloud-config.id
  }

  operating_system {
    type = "l26"
  }

  tpm_state {
    version = "v2.0"
  }

  serial_device {}
}
