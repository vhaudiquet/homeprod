/* 
* Docker machine terraform file
*/

resource "proxmox_virtual_environment_file" "docker-machine-cloud-config" {
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
      - install -m 0755 -d /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
      - chmod a+r /etc/apt/keyrings/docker.asc
      - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      - apt-get update
      - apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      - docker swarm init
    EOF
    file_name = "docker-machine-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "docker-machine" {
  name = "docker-machine"
  node_name = "pve"
  on_boot = true

  agent {
    enabled = true
  }

  tags = ["debian", "debian-latest", "docker", "terraform"]

  cpu {
    type = "kvm64"
    cores = 4
    sockets = 1
    flags = []
  }

  memory {
    dedicated = 16192
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

  disk {
    interface = "scsi0"
    iothread = true
    datastore_id = "local-lvm"
    size = 8
    discard = "ignore"
  }

  clone {
    vm_id = data.proxmox_virtual_environment_vms.debian_vm_template.vms[0].vm_id
  }

  vm_id = 701

  initialization {
    datastore_id = "local-lvm"
    interface = "ide2"
    vendor_data_file_id = proxmox_virtual_environment_file.docker-machine-cloud-config.id
  }
}
