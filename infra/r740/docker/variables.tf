variable "sops_private_key" {
  description = "Private SOPS GPG key for SwarmCD to decrypt secrets"
  type = string
}
variable "docker_host" {
  description = "Docker machine hostname"
  type = string
}