#!/bin/sh
# Reconcile Talos cluster infrastructure
# Environment needed:
# - SOPS_KEY: sops private key
set -euo pipefail

if [ -z "${SOPS_KEY:-}" ]; then
  echo "Error: SOPS_KEY environment variable is not set" >&2
  exit 1
fi

# Render the Cilium chart for manifest deployment
helm repo add cilium https://helm.cilium.io/
helm repo update
helm template cilium cilium/cilium \
  --version 1.20.1 \
  --namespace kube-system \
  -f manifests/cilium/values.yaml \
  > manifests/cilium.yaml

# Escape shell variables that must be resolved at container runtime, not by talhelper.
# talhelper expands ${VAR} statically; prefixing with $$ (i.e. $${VAR}) tells it to
# preserve the literal ${VAR} in the output so bash can expand it inside the container.
sed -i 's/\${BIN_PATH}/$${BIN_PATH}/g' manifests/cilium.yaml

# Generate Talos machine config
talhelper genconfig

# Apply generated machine config to the nodes, without reboot.
# If it fails, it is safer for reconcile to be done manually:
# the reboot is needed and that might disrupt the node
talhelper gencommand apply --extra-flags="-m no-reboot" | bash

# Obtain kubeconfig and export it for kubectl
talosctl --talosconfig ./clusterconfig/talosconfig kubeconfig -f ./clusterconfig/kubeconfig
export KUBECONFIG=./clusterconfig/kubeconfig

# Show nodes
kubectl get nodes

# Create Flux namespace if it does not already exists
kubectl get ns "flux-system" || kubectl create ns "flux-system"

# Create SOPS secret in the cluster
kubectl create secret generic flux-sops \
  --namespace "flux-system" \
  --from-literal=sops.asc="$SOPS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Install the Flux operator if not installed already
kubectl get deployment -n flux-system flux-operator || helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace "flux-system" \
  --wait

kubectl apply -f manifests/flux-system/flux-instance.yaml
