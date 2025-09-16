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
  host = "ssh://root@docker-machine.lan"
}

resource "docker_image" "swarm-cd" {
  name = "ghcr.io/m-adawi/swarm-cd:latest"
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

  depends_on = [ docker_image.swarm-cd ]
}
