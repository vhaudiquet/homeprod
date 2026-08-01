# Talos control-plane node for the Raspberry Pi 4 — joins the r740 "kube" cluster
# as a third etcd member to restore quorum (2-of-3 majority). Unlike the p330
# failover node, this node is tainted "quorum" so no user workloads are ever
# scheduled on it; only essential DaemonSets (Cilium, etc.) that tolerate the
# taint land here for cluster networking.
#
# Secret handling: the cluster machine secrets are provided via
# var.machine_secrets_file (a local, gitignored JSON file in the provider's
# machine_secrets format). They are consumed by EPHEMERAL resources and
# WRITE-ONLY attributes so they never land in Terraform state. See
# variables.tf and scripts/extract-talos-secrets.sh for how to produce the
# file from the live r740 node.
terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.3"
    }
  }
}

locals {
  # Load the machine secrets from the gitignored JSON file. This local is only
  # ever referenced by ephemeral resources / write-only attributes, so the
  # values are never persisted to state.
  machine_secrets = jsondecode(file(var.machine_secrets_file))

  # Network config: static if node_subnet is provided, otherwise Talos DHCPs.
  # The rpi4 uses DHCP (node_subnet = null), so only nameservers are patched in.
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
    network = local.network_patch_merged
    # NOTE: no Longhorn iSCSI/ext4 kernel modules here. This is a quorum-only
    # node: the quorum taint keeps user workloads (and Longhorn replicas) off
    # it, so the storage stack is not needed. Essential DaemonSets such as
    # Cilium still run here for cluster networking and tolerate the taint.
    sysctls = {
      "fs.inotify.max_user_instances" = "1024"
      "fs.inotify.max_user_watches"   = "1048576"
    }
    kubelet = {
      # Register the node already tainted so the scheduler never admits user
      # workloads even before the null_resource below runs. NoSchedule is
      # sufficient: essential DaemonSets (Cilium, etc.) tolerate it, but no
      # user pods are admitted.
      extraArgs = {
        "register-with-taints" = "${var.quorum_taint_key}=${var.quorum_taint_value}:${var.quorum_taint_effect}"
      }
    }
  }
}

# --- Ephemeral resources: secrets never stored in state ---------------------
#
# talos_machine_configuration generates the control-plane join config from the
# provided machine_secrets. The output (machine_configuration) is an ephemeral
# value — it can only flow into write-only attributes or provisioners, never
# into a persisted resource attribute.
ephemeral "talos_machine_configuration" "rpi4" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = local.machine_secrets
  config_patches = [
    yamlencode({
      machine = local.machine_patch
    }),
    # Pin the Kubernetes node name via a HostnameConfig document (Talos v1.13+).
    # The old machine.network.hostname field conflicts with the default
    # HostnameConfig document ("static hostname is already set"), so we use the
    # document-based config with auto: off + an explicit hostname instead.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = var.rpi4_node_name
      auto       = "off"
    })
  ]
}

# talos_client_configuration generates a Talos client config (talosconfig) from
# the machine_secrets, scoped to the rpi4 node. Also ephemeral — used only to
# drive the write-only client_configuration_wo on the apply resource.
ephemeral "talos_client_configuration" "rpi4" {
  cluster_name    = var.cluster_name
  machine_secrets = local.machine_secrets
  nodes           = [var.rpi4_host]
}

# --- Apply the config to the node (write-only attrs → no secrets in state) --
#
# machine_configuration_input_wo and client_configuration_wo are write-only:
# Terraform uses them during apply but does NOT persist them to state. Only a
# hash of the machine config (machine_configuration_hash) is stored, for drift
# detection. Because the config patch contains a `machine.install` block, when
# Talos receives this config on a node booted from the SD card (maintenance)
# image it installs itself to install.disk and reboots into the installed
# system. As a controlplane node it then joins the existing etcd cluster as a
# new member and runs the control-plane components. With r740 + p330 + rpi4 the
# etcd cluster reaches 3 members → 2-of-3 quorum.
resource "talos_machine_configuration_apply" "rpi4" {
  node                           = var.rpi4_host
  client_configuration_wo        = ephemeral.talos_client_configuration.rpi4.client_configuration
  machine_configuration_input_wo = ephemeral.talos_machine_configuration.rpi4.machine_configuration
}

# --- Write the rendered config to disk for manual use ----------------------
#
# local_file.content cannot accept an ephemeral value (it would persist to
# state), so we use a null_resource local-exec provisioner instead —
# provisioners do not persist their arguments to state. This writes rpi4.yaml
# so the config can also be applied manually with
# `talosctl apply-config --nodes <rpi4_host> --file rpi4.yaml` if needed.
resource "null_resource" "rpi4_machine_config_file" {
  triggers = {
    # Re-run only when the (non-secret) inputs that shape the config change.
    node            = var.rpi4_node_name
    install_disk    = var.install_disk
    installer_image = var.installer_image
    taint           = "${var.quorum_taint_key}=${var.quorum_taint_value}:${var.quorum_taint_effect}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      cat > "${path.module}/rpi4.yaml" <<'YAMLEOF'
${ephemeral.talos_machine_configuration.rpi4.machine_configuration}
YAMLEOF
      echo "Wrote ${path.module}/rpi4.yaml"
    EOT
  }

  depends_on = [talos_machine_configuration_apply.rpi4]
}

# --- Wait for the node, then label + taint ---------------------------------
#
# Wait for the node to register with Kubernetes (kubelet creates the Node
# object after Talos installs and reboots), then label it and (re)apply the
# quorum taint. This is idempotent: kubectl exits 0 if the label/taint already
# exists. The taint is also set via kubelet `register-with-taints`, so this
# null_resource is a safety net for manual edits / drift. The kubeconfig path
# is only used inside the provisioner (not persisted to state).
resource "null_resource" "rpi4_node_label_and_taint" {
  triggers = {
    node       = var.rpi4_node_name
    key        = var.quorum_taint_key
    value      = var.quorum_taint_value
    effect     = var.quorum_taint_effect
    kubeconfig = var.kubeconfig_path
  }

  provisioner "local-exec" {
    # Wait for the node to show up, then label + taint. The wait loop is bounded
    # by kubectl --timeout; tune it via TF_LOG / re-run if the node is slow to
    # join (a controlplane node must first complete the etcd join handshake).
    command = <<-EOT
      set -euo pipefail
      KUBECONFIG="${var.kubeconfig_path}"
      export KUBECONFIG
      NODE="${var.rpi4_node_name}"

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

      # Quorum marker + taint (applied to the controlplane node).
      kubectl label --overwrite node "$NODE" homeprod.io/quorum=true

      # Apply the taint idempotently (kubectl taint --overwrite is a no-op if it exists).
      kubectl taint --overwrite node "$NODE" \
        "${var.quorum_taint_key}=${var.quorum_taint_value}:${var.quorum_taint_effect}"

      echo "Node $NODE ready, labeled and tainted for quorum-only scheduling."
    EOT
  }

  depends_on = [talos_machine_configuration_apply.rpi4]
}
