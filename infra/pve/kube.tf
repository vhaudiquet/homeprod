/* 
* Kubernetes cluster terraform file
*/

resource "proxmox_virtual_environment_download_file" "talos-cloudimg" {
  content_type = "iso"
  datastore_id = "local"
  file_name = "talos-v1.9.4-nocloud-amd64.iso"
  node_name = "pve"
  url = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.9.4/nocloud-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "kube" {
  name = "kube-talos"
  description = "Kubernetes Talos Linux"
  tags = ["kubernetes", "talos", "terraform"]

  node_name = "pve"
  vm_id = 702
  machine = "q35"
  keyboard_layout = "fr"

  agent {
    enabled = true
  }
  stop_on_destroy = true

  cpu {
    cores = 4
    type = "x86-64-v3"
  }

  memory {
    dedicated = 16192
    floating = 16192
  }

  boot_order = ["scsi0", "ide0"]
  scsi_hardware = "virtio-scsi-single"

  cdrom {
    enabled = true
    file_id = proxmox_virtual_environment_download_file.talos-cloudimg.id
    interface = "ide0"
  }

  disk {
    interface = "scsi0"
    iothread = true
    datastore_id = "local-lvm"
    size = 16
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
    mac_address = "BC:24:11:F6:E1:C9"
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

resource "talos_machine_secrets" "kube" {}

data "talos_machine_configuration" "kube" {
  cluster_name = "kube"
  machine_type = "controlplane"
  cluster_endpoint = "https://kube-talos.local:6443"
  machine_secrets = talos_machine_secrets.kube.machine_secrets
  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = "factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.9.4"
        }
        network = {
          nameservers = [
            "10.1.2.3"
          ]
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
        apiServer = {
          certSANs = [
            "kube-talos.local"
          ]
        }
        network = {
          dnsDomain = "kube-talos.local"
          cni = {
            name: "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

data "talos_client_configuration" "kube" {
  cluster_name = "kube"
  client_configuration = talos_machine_secrets.kube.client_configuration
  nodes = ["kube-talos.local"]
}

resource "talos_machine_configuration_apply" "kube" {
  client_configuration = talos_machine_secrets.kube.client_configuration
  machine_configuration_input = data.talos_machine_configuration.kube.machine_configuration
  node = proxmox_virtual_environment_vm.kube.ipv4_addresses[7][0] # lo + 6 talos-created interfaces before eth0
  depends_on = [ proxmox_virtual_environment_vm.kube ]
  lifecycle {
    replace_triggered_by = [ proxmox_virtual_environment_vm.kube ]
  }
}

resource "talos_machine_bootstrap" "kube" {
  node = proxmox_virtual_environment_vm.kube.ipv4_addresses[7][0] # lo + 6 talos-created interfaces before eth0
  client_configuration = talos_machine_secrets.kube.client_configuration
  depends_on = [ talos_machine_configuration_apply.kube ]
  lifecycle {
    replace_triggered_by = [ proxmox_virtual_environment_vm.kube ]
  }
}

resource "talos_cluster_kubeconfig" "kube" {
  node = proxmox_virtual_environment_vm.kube.ipv4_addresses[7][0] # lo + 6 talos-created interfaces before eth0
  depends_on = [ talos_machine_bootstrap.kube ]
  client_configuration = talos_machine_secrets.kube.client_configuration
}

output "kubeconfig" {
  sensitive = true
  value = talos_cluster_kubeconfig.kube.kubeconfig_raw
}

resource "local_file" "kubeconfig" {
    content     = "${talos_cluster_kubeconfig.kube.kubeconfig_raw}"
    filename = "${path.module}/kubeconfig"
    depends_on = [ talos_cluster_kubeconfig.kube ]
}

data "talos_client_configuration" "talosconfig" {
  cluster_name = "homeprod"
  client_configuration = talos_machine_secrets.kube.client_configuration
  nodes = [proxmox_virtual_environment_vm.kube.ipv4_addresses[7][0]]
}

resource "local_file" "talosconfig" {
    content     = "${data.talos_client_configuration.talosconfig.talos_config}"
    filename = "${path.module}/talosconfig"
    depends_on = [ data.talos_client_configuration.talosconfig ]
}

# TODO : Wait for talos_cluster_kubeconfig...
resource "helm_release" "cilium" {
  name = "cilium"
  namespace = "kube-system"
  repository = "https://helm.cilium.io/"
  chart = "cilium"
  wait = false
  depends_on = [ local_file.kubeconfig ]

  set {
    name = "ipam.mode"
    value = "kubernetes"
  }
  set {
    name = "kubeProxyReplacement"
    value = true
  }
  set {
    name = "securityContext.capabilities.ciliumAgent"
    value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
  }
  set {
    name = "securityContext.capabilities.cleanCiliumState"
    value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
  }
  set {
    name = "cgroup.autoMount.enabled"
    value = false
  }
  set {
    name = "cgroup.hostRoot"
    value = "/sys/fs/cgroup"
  }
  set {
    name = "k8sServiceHost"
    value = "localhost"
  }
  set {
    name = "k8sServicePort"
    value = 7445
  }
  set {
    name = "etcd.clusterDomain"
    value = "kube-talos.local"
  }
  set {
    name = "hubble.relay.enabled"
    value = true
  }
  # Enable hubble ui
  set {
    name = "hubble.ui.enabled"
    value = true
  }
  # Gateway API support
  set {
    name = "gatewayAPI.enabled"
    value = true
  }
  set {
    name = "gatewayAPI.enableAlpn"
    value = true
  }
  set {
    name = "gatewayAPI.enableAppProtocol"
    value = true
  }
  # Gateway API trusted hops : for reverse proxy
  set {
    name = "gatewayAPI.xffNumTrustedHops"
    value = 1
  }
  # Single-node cluster, so 1 operator only
  set {
    name = "operator.replicas"
    value = 1
  }
  # L2 announcements
  set {
    name = "l2announcements.enabled"
    value = true
  }
  set {
    name = "externalIPs.enabled"
    value = true
  }
  # Disable ingress controller (traefik will be used for now)
  set {
    name = "ingressController.enabled"
    value = false
  }
  set {
    name = "ingressController.loadbalancerMode"
    value = "shared"
  }
  # Ingress controller for external : behind reverse proxy, trust 1 hop
  set {
    name = "envoy.xffNumTrustedHopsL7PolicyIngress"
    value = 1
  }
  # Set cilium as default ingress controller
  set {
    name = "ingressController.default"
    value = true
  }
  set {
    name = "ingressController.service.externalTrafficPolicy"
    value = "Local"
  }
}

resource "kubernetes_namespace" "flux-system" {
  metadata {
    name = "flux-system"
  }

  lifecycle {
    ignore_changes = [ metadata[0].annotations, metadata[0].labels ]
  }

  depends_on = [ talos_cluster_kubeconfig.kube, local_file.kubeconfig, helm_release.cilium ]
}

resource "kubernetes_secret" "flux-sops" {
  metadata {
    name = "flux-sops"
    namespace = "flux-system"
  }

  type = "generic"

  data = {
    "sops.asc"=var.sops_private_key
  }

  depends_on = [ kubernetes_namespace.flux-system ]
}

resource "helm_release" "flux-operator" {
  name = "flux-operator"
  namespace = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart = "flux-operator"
  wait = true
  depends_on = [ kubernetes_secret.flux-sops ]
}

resource "helm_release" "flux-instance" {
  name = "flux"
  namespace = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart = "flux-instance"

  values = [
    file("values/components.yaml")
  ]
  set {
    name = "instance.distribution.version"
    value = "2.x"
  }
  set {
    name = "instance.distribution.registry"
    value = "ghcr.io/fluxcd"
  }
  set {
    name = "instance.sync.name"
    value = "homeprod"
  }
  set {
    name = "instance.sync.kind"
    value = "GitRepository"
  }
  set {
    name = "instance.sync.url"
    value = "https://github.com/vhaudiquet/homeprod"
  }
  set {
    name = "instance.sync.path"
    value = "kubernetes/"
  }
  set {
    name = "instance.sync.ref"
    value = "refs/heads/main"
  }


  depends_on = [ helm_release.flux-operator ]
}
