<h1 align="center">
homeprod
</h1>
<div align="center">
Personal home production environment mono-repo
</div>

### Hardware and operating systems

<img align="left" width="100" src="https://vhaudiquet.fr/public/github_assets/homeprod/p330_sff.png"/>

#### Lenovo ThinkStation P330 SFF

Specifications :
```
Intel Xeon E-2134 @ 3.50GHz (4 cores, 8 threads)
64 GiB DDR4 ECC RAM
1 TiB nVME SSD
Intel X520-DA2 SFP+ 10Gbps network card
nVIDIA Quadro P620 graphics card
```

Running as single-node Proxmox

### Software stack(s)

#### Docker swarm machine

| Icon | Software   | Description            |
|------|------------|------------------------|
| <img width=32 src="https://avatars.githubusercontent.com/u/1854028"> | Debian Linux | Operating system |
| <img width=32 src="https://avatars.githubusercontent.com/u/5429470"> | Docker Swarm | Container orchestrator |
| <img width=32 src="https://avatars.githubusercontent.com/u/82976448"><img width=32 src="https://avatars.githubusercontent.com/u/76623657"> | Infrastructure applications | Authentik, Stalwart Mail for authentication and internal emails |
| <img width=32 src="https://avatars.githubusercontent.com/u/12724356"><img width=32 src="https://avatars.githubusercontent.com/u/40275816"> | Repository applications | Gitea, Harbor to store code and images |
| <img width=30 src="https://buildpath.win/_ipx/w_60&f_webp/buildpath-high-resolution-logo-transparent.png"> <img width=32 src="https://avatars.githubusercontent.com/u/13844975"> | Production applications | Personal applications running on the server |

Debian and docker / docker swarm are deployed by Terraform, which also deploys [SwarmCD](https://github.com/m-adawi/swarm-cd) ; then the stacks are deployed by SwarmCD.

#### Kubernetes one-node cluster

| Icon | Software   | Description            |
|------|------------|------------------------|
| <img width=32 src="https://avatars.githubusercontent.com/u/13804887"> | Talos Linux | Kubernetes operating system
| <img width=32 src="https://raw.githubusercontent.com/kubernetes/kubernetes/refs/heads/master/logo/logo.png">    | Kubernetes | Container orchestrator |
| <img width=32 src="https://avatars.githubusercontent.com/u/21054566"> | Cilium | Container Network solution |
| <img width=32 src="https://avatars.githubusercontent.com/u/52158677"> | Flux | GitOps CD controller |
| <img width=32 src="https://avatars.githubusercontent.com/u/33050221"> | csi-driver-nfs | NFS Container Storage solution |
| <img width=32 src="https://raw.githubusercontent.com/kubernetes-sigs/external-dns/refs/heads/master/docs/img/external-dns.png"> | external-dns | Automatic ingress DNS mapping |
| <img width=32 src="https://avatars.githubusercontent.com/u/82976448"><img width=32 src="https://avatars.githubusercontent.com/u/76623657"> | Infrastructure applications | Authentik, Stalwart Mail for authentication and internal emails |
| <img width=32 src="https://avatars.githubusercontent.com/u/12724356"><img width=32 src="https://avatars.githubusercontent.com/u/40275816"> | Repository applications | Gitea, Harbor to store code and images |
| <img width=30 src="https://buildpath.win/_ipx/w_60&f_webp/buildpath-high-resolution-logo-transparent.png"> <img width=32 src="https://avatars.githubusercontent.com/u/13844975"> | Production applications | Personal applications running on the cluster |

Talos Linux, Cilium and flux are deployed using Terraform ; then flux takes over and deploys the whole `kubernetes` folder of this repository.

### Production/personal applications

This setup allows running multiple applications, either self-hosted applications for home/self usage or to run my own applications as production.

#### Production

| Icon | Software     | Description |
|------|--------------|-------------|
| <img width=30 src="https://buildpath.win/_ipx/w_60&f_webp/buildpath-high-resolution-logo-transparent.png"> | BuildPath | https://buildpath.win, website for League of Legends champion builds |
| <img width=32 src="https://vhaudiquet.fr/assets/favicon.ico_256x256.png"> | vhaudiquet.fr | https://vhaudiquet.fr, personal website |

#### Personal applications

| Icon | Software     | Description |
|------|--------------|-------------|
| <img width=32 src="https://avatars.githubusercontent.com/u/13844975"> | Home Assistant | Home automation software |
| <img width=32 src="https://avatars.githubusercontent.com/u/45698031"> | Jellyfin | Personal media system |
| <img width=32 src="https://avatars.githubusercontent.com/u/99562962"> | Paperless | Personal document manager |
| <img width=32 src="https://avatars.githubusercontent.com/u/32436079"> | Photoprism | Personal photo gallery |
| <img width=32 src="https://avatars.githubusercontent.com/u/67865462"> | Hedgedoc | Shared markdown notes |
| <img width=32 src="https://avatars.githubusercontent.com/u/59452120"> | Excalidraw | Hand-draw like diagrams |
| <img width=32 src="https://avatars.githubusercontent.com/u/139791695"> | Stirling PDF | PDF multi-tool |
| <img width=32 src="https://avatars.githubusercontent.com/u/86065214"> | Tandoor Recipes | Personal recipes manager |
| <img width=32 src="https://avatars.githubusercontent.com/u/7628018"> | Syncthing | File synchronization |
| <img width=32 src="https://avatars.githubusercontent.com/u/10428818"> | Gramps | Personal genealogical tool |
| <img width=32 src="https://avatars.githubusercontent.com/u/26692192"> | Navidrome | Personal music streaming service |
| <img width=32 src="https://avatars.githubusercontent.com/u/102734415"> | TubeArchivist | YouTube archiver |
| <img width=24 src="https://radicale.org/assets/logo.svg"> | Radicale | Calendar and contacts server |
