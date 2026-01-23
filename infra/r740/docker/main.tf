terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

# Docker configuration
provider "docker" {
  host = "ssh://root@${var.docker_host}"
}

resource "docker_image" "swarm-cd" {
  name = "swarm-cd:latest"
  # For now, custom-built image based on custom development branch
  # Once this reaches upstream, back to upstream tag, like:
  # ghcr.io/m-adawi/swarm-cd:1.9.0
}

resource "docker_container" "swarm-cd" {
  name  = "swarm-cd"
  image = docker_image.swarm-cd.image_id
  volumes {
      host_path = "/var/run/docker.sock"
      container_path = "/var/run/docker.sock"
      read_only = true
  }
  volumes {
    host_path = "/root/homeprod/.swarmcd/repos.yaml"
    container_path = "/app/repos.yaml"
    read_only = true
  }
  volumes {
    host_path = "/root/homeprod/.swarmcd/stacks.yaml"
    container_path = "/app/stacks.yaml"
    read_only = true
  }
  volumes {
    host_path = "/app/swarm-cd/data"
    container_path = "/data"
  }
  env = [
    "SOPS_GPG_PRIVATE_KEY=${var.sops_private_key}"
  ]

  depends_on = [ docker_image.swarm-cd ]
}
