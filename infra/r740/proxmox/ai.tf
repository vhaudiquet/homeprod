resource "proxmox_virtual_environment_download_file" "ubuntu-latest-cloudimg" {
  content_type = "iso"
  datastore_id = "local"
  file_name = "noble-server-cloudimg-amd64.img"
  node_name = var.proxmox_node_name
  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_file" "ai-cloud-config" {
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
    runcmd:
      - systemctl enable --now qemu-guest-agent
      - install -m 0755 -d /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      - chmod a+r /etc/apt/keyrings/docker.asc
      - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      - apt-get update
      - apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      - apt install ubuntu-drivers-common
      - ubuntu-drivers install --gpgpu
      - curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
      - curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
      - apt-get update
      - export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
      - apt-get install -y nvidia-container-toolkit=$NVIDIA_CONTAINER_TOOLKIT_VERSION nvidia-container-toolkit-base=$NVIDIA_CONTAINER_TOOLKIT_VERSION libnvidia-container-tools=$NVIDIA_CONTAINER_TOOLKIT_VERSION libnvidia-container1=$NVIDIA_CONTAINER_TOOLKIT_VERSION
      - nvidia-ctk runtime configure --runtime=docker
      - systemctl restart docker
    EOF
    file_name = "ai-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "ai" {
  name = "ai-${var.proxmox_node_name}"
  node_name = var.proxmox_node_name
  on_boot = true

  agent {
    enabled = true
  }

  tags = ["ubuntu", "ubuntu-latest", "docker", "terraform", "gpu", "ai"]

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
    # mac_address = "BC:24:11:E2:F5:5B"
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
      vga,
      hostpci
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
    file_id = proxmox_virtual_environment_download_file.ubuntu-latest-cloudimg.id
  }

  vm_id = 101

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

    vendor_data_file_id = proxmox_virtual_environment_file.ai-cloud-config.id
  }

  operating_system {
    type = "l26"
  }

  tpm_state {
    version = "v2.0"
  }

  serial_device {}
}
