# Talos node for the P330 — joins the r740 "kube" cluster.
terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.3"
    }
  }
}

# Read the r740 kube module state to reuse the cluster secrets & endpoint.
# The r740 module exposes: client_configuration, machine_secrets, cluster_name,
# cluster_endpoint, kube_host.
data "terraform_remote_state" "r740_kube" {
  backend = var.r740_backend

  config = var.r740_backend == "local" ? {
    path = "${var.r740_state_path}/terraform.tfstate"
  } : var.r740_backend_config
}

locals {
  cluster_name     = data.terraform_remote_state.r740_kube.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.r740_kube.outputs.cluster_endpoint
  machine_secrets  = data.terraform_remote_state.r740_kube.outputs.machine_secrets
  client_config    = data.terraform_remote_state.r740_kube.outputs.client_configuration

  # kubeconfig produced by the r740 kube module — used to wait for the node and
  # apply labels/taints. There is no in-tree kubernetes provider here on
  # purpose: managing a `kubernetes_node` resource conflicts with the node
  # object that kubelet itself creates, so we use a null_resource with kubectl
  # to wait + label + taint idempotently.
  kubeconfig_path = "${var.r740_state_path}/kubeconfig"

  # Network config: static if node_subnet is provided, otherwise Talos DHCPs.
  static_network = var.node_subnet == null ? {} : {
    interfaces = [{
      interface = var.network_interface
      addresses = [var.node_subnet]
      routes    = var.node_gateway == null ? [] : [{ gateway = var.node_gateway }]
    }]
  }

  network_patch = {
    nameservers = var.nameservers
  }
  network_patch_merged = merge(local.network_patch, local.static_network)

  machine_patch = {
    install = {
      image = var.installer_image
      disk  = var.install_disk
    }
    network = merge(local.network_patch_merged, {
      # Pin the Kubernetes node name. Talos otherwise auto-generates a hostname
      # (e.g. "talos-8ec-vd1"), so the node registers with that random name
      # instead of var.p330_node_name — and our label/taint null_resource waits
      # for the wrong node. Setting machine.network.hostname fixes the node name.
      hostname = var.p330_node_name
    })
    # Kernel modules required by Longhorn (iSCSI + ext4) — must match the
    # control-plane nodes so Longhorn can schedule replicas on the failover node.
    kernel = {
      modules = [
        { name = "iscsi_tcp" },
        { name = "libiscsi" },
        { name = "scsi_transport_iscsi" },
        { name = "ext4" },
      ]
    }
    sysctls = {
      "fs.inotify.max_user_instances" = "1024"
      "fs.inotify.max_user_watches"   = "1048576"
    }
    kubelet = {
      # Keep the failover node from accumulating non-essential DaemonSet pods
      # via the regular scheduler; the taint does the heavy lifting, this is
      # belt-and-braces.
      extraArgs = {
        "register-with-taints" = "${var.failover_taint_key}=${var.failover_taint_value}:${var.failover_taint_effect}"
      }
    }
  }
}

# Control-plane machine configuration. machine_type = "controlplane" makes
# Talos generate a join config that runs the apiserver/controller-manager/
# scheduler AND joins the existing etcd cluster as a new member (the cluster
# was already bootstrapped by the r740 module's talos_machine_bootstrap).
data "talos_machine_configuration" "p330" {
  cluster_name     = local.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = local.machine_secrets
  config_patches = [
    yamlencode({
      machine = local.machine_patch
    })
  ]
}

# Rendered config is written to disk so it can also be applied manually with
# `talosctl apply-config --nodes <p330_host> --file p330.yaml` if needed.
resource "local_file" "p330_machine_config" {
  filename = "${path.module}/p330.yaml"
  content  = data.talos_machine_configuration.p330.machine_configuration
}

# Apply the machine config to the running (maintenance-mode) node over the
# Talos API. Because the config patch contains a `machine.install` block, when
# Talos receives this config on a node booted from the USB (maintenance) image
# it installs itself to install.disk and reboots into the installed system.
# For a controlplane node it then joins the existing etcd cluster as a new
# member and runs the control-plane components; for a worker it just registers
# via kubelet.
resource "talos_machine_configuration_apply" "p330" {
  client_configuration        = local.client_config
  machine_configuration_input = data.talos_machine_configuration.p330.machine_configuration
  node                        = var.p330_host
  depends_on                  = [local_file.p330_machine_config]
}

# Emit a talosconfig scoped to this node for ad-hoc `talosctl` use.
data "talos_client_configuration" "p330" {
  cluster_name         = local.cluster_name
  client_configuration = local.client_config
  nodes                = [var.p330_host]
}

resource "local_file" "talosconfig" {
  content    = data.talos_client_configuration.p330.talos_config
  filename   = "${path.module}/talosconfig"
  depends_on = [data.talos_client_configuration.p330]
}

# Wait for the node to register with Kubernetes (kubelet creates the Node
# object after Talos installs and reboots), then label it and (re)apply the
# failover taint. This is idempotent: kubectl exits 0 if the label/taint already
# exists. The taint is also set via kubelet `register-with-taints`, so this
# null_resource is a safety net for manual edits / drift.
resource "null_resource" "p330_node_label_and_taint" {
  triggers = {
    node       = var.p330_node_name
    key        = var.failover_taint_key
    value      = var.failover_taint_value
    effect     = var.failover_taint_effect
    kubeconfig = local.kubeconfig_path
  }

  provisioner "local-exec" {
    # Wait for the node to show up, then label + taint. The wait loop is bounded
    # by kubectl --timeout; tune it via TF_LOG / re-run if the node is slow to
    # join (a controlplane node must first complete the etcd join handshake).
    command = <<-EOT
      set -euo pipefail
      KUBECONFIG="${local.kubeconfig_path}"
      export KUBECONFIG
      NODE="${var.p330_node_name}"

      echo "Waiting for node $NODE to be registered (kubelet creates the Node object once Talos has installed, rebooted and joined etcd)..."
      # kubectl wait --for=condition=Ready fails instantly with NotFound if the
      # node object doesn't exist yet, so poll for existence first.
      # /bin/sh (dash) has no $SECONDS, so count iterations with a bounded loop.
      tries=240   # 240 * 5s = 20 minutes max
      until kubectl get node "$NODE" >/dev/null 2>&1; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then
          echo "Timed out waiting for node $NODE to register." >&2
          exit 1
        fi
        sleep 5
      done
      echo "Node $NODE registered. Waiting for it to become Ready..."

      # Now wait for Ready (a controlplane node needs etcd joined + apiserver up).
      kubectl wait --for=condition=Ready "node/$NODE" --timeout=20m || \
        kubectl wait --for=jsonpath='{.status.conditions[?(@.reason=="KubeletReady")].status}'=True "node/$NODE" --timeout=20m

      # Failover marker + taint (applied to both controlplane and worker nodes).
      kubectl label --overwrite node "$NODE" homeprod.io/failover=true

      # Apply the taint idempotently (kubectl taint --overwrite is a no-op if it exists).
      kubectl taint --overwrite node "$NODE" \
        "${var.failover_taint_key}=${var.failover_taint_value}:${var.failover_taint_effect}"

      echo "Node $NODE ready, labeled and tainted for failover-only scheduling."
    EOT
  }

  depends_on = [talos_machine_configuration_apply.p330]
}
