variable "sops_private_key" {
  description = "Private SOPS GPG key for flux/kubernetes to decrypt secrets"
  type = string
}
variable "kube_hostname" {
  description = "Kubernetes cluster hostname"
  type = string
}
variable "kube_host" {
  description = "Kubernetes cluster host"
  type = string
}
variable "physical_hostname" {
  description = "Host name of the physical host for the kubernetes VM"
  type = string
}
