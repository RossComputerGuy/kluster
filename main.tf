terraform {
  required_version = ">= 1.0.1"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.6.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.4.1"
    }
    lastpass = {
      source  = "nrkno/lastpass"
      version = "0.5.3"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }
}

locals {
  repoURL        = "https://github.com/RossComputerGuy/kluster.git"
  targetRevision = "master"
}

##
## Providers
##
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "cloudflare" {
  api_token = var.cloudflare_token
  api_user_service_key = var.cloudflare_origin_ca_key
}

##
## Sensitive data
##
resource "random_password" "argo-cd-admin-password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "lastpass_secret" "argo-cd-admin-password" {
  name     = "Kubernetes Cluster: ArgoCD Admin Password"
  url      = "http://argo-cd.cluster.tristanxr.com"
  username = "admin"
  password = resource.random_password.argo-cd-admin-password.result
}

resource "random_password" "argo-tunnel-secret" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "lastpass_secret" "argo-tunnel-secret" {
  name     = "Kubernetes Cluster: Argo Tunnel Secret"
  url      = "http://cluster.tristanxr.com"
  username = "admin"
  password = resource.random_password.argo-tunnel-secret.result
}

##
## Cloudflare Argo Tunnel
##
resource "cloudflare_argo_tunnel" "argo-tunnel" {
  account_id = var.cloudflare_account_id
  name       = "cluster.tristanxr.com"
  secret     = base64encode(resource.lastpass_secret.argo-tunnel-secret.password)
}

resource "cloudflare_zone" "tristanxr" {
  account_id = var.cloudflare_account_id
  zone       = "tristanxr.com"
}

resource "cloudflare_record" "cluster" {
  zone_id = resource.cloudflare_zone.tristanxr.id
  name    = "cluster"
  type    = "CNAME"
  proxied = true
  value   = "${resource.cloudflare_argo_tunnel.argo-tunnel.id}.cfargotunnel.com"
}

##
## Namespaces
##
resource "kubernetes_namespace" "argo-cd" {
  metadata {
    name = "argo-cd"
  }
}

resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "prometheus"
  }
}

##
## SSL Certificate
##

resource "tls_private_key" "tristanxr" {
  algorithm = "RSA"
}

resource "tls_cert_request" "tristanxr" {
  private_key_pem = resource.tls_private_key.tristanxr.private_key_pem

  subject {
    common_name  = ""
    organization = "Tristan Ross"
  }
}

resource "cloudflare_origin_ca_certificate" "tristanxr" {
  csr                = resource.tls_cert_request.tristanxr.cert_request_pem
  request_type       = "origin-rsa"
  requested_validity = 365
  hostnames          = ["*.cluster.tristanxr.com", "cluster.tristanxr.com"]
}

resource "kubernetes_secret" "argo-cd-tls-certificate" {
  metadata {
    name = "argo-cd-tls-certificate"
    namespace = "argo-cd"
  }

  data = {
    "tls.crt" = resource.cloudflare_origin_ca_certificate.tristanxr.certificate
    "tls.key" = resource.tls_private_key.tristanxr.private_key_pem
  }

  depends_on = [
    resource.kubernetes_namespace.argo-cd,
    resource.cloudflare_origin_ca_certificate.tristanxr,
    resource.tls_private_key.tristanxr
  ]
}

##
## Helm Releases
##
resource "helm_release" "prometheus" {
  name = "prometheus"

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "kube-prometheus"
  version    = "8.0.16"
  namespace  = "prometheus"

  depends_on = [resource.kubernetes_namespace.prometheus]
}

resource "helm_release" "argo-cd" {
  name = "argo-cd"

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "4.10.7"
  namespace  = "argo-cd"

  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(resource.lastpass_secret.argo-cd-admin-password.password)
    type  = "string"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "dex.metrics.enabled"
    value = "true"
  }

  set {
    name  = "dex.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "redis.metrics.enabled"
    value = "true"
  }

  set {
    name  = "redis.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.https"
    value = "true"
  }

  set {
    name  = "server.ingress.tls[0].secretName"
    value = "argo-cd-tls-certificate"
  }

  set {
    name  = "server.ingress.tls[0].hosts"
    value = "{argo-cd.cluster.tristanxr.com}"
  }

  set {
    name  = "server.ingress.hosts"
    value = "{\"argo-cd.cluster.tristanxr.com\"}"
  }

  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  set {
    name  = "server.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "repoServer.metrics.enabled"
    value = "true"
  }

  set {
    name  = "repoServer.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "applicationSet.metrics.enabled"
    value = "true"
  }

  set {
    name  = "applicationSet.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "notifications.metrics.enabled"
    value = "true"
  }

  depends_on = [
    resource.kubernetes_secret.argo-cd-tls-certificate,
    resource.kubernetes_namespace.argo-cd,
    resource.helm_release.prometheus
  ]
}

resource "helm_release" "argo-cd-internal" {
  name = "argo-cd-internal"

  repository = path.module
  chart      = "argo-cd-internal/chart"
  namespace  = "argo-cd"

  set {
    name  = "repoURL"
    value = local.repoURL
    type  = "string"
  }

  set {
    name  = "targetRevision"
    value = local.targetRevision
    type  = "string"
  }

  set {
    name  = "networking.cloudflared.auth.tunnelSecret"
    value = base64encode(resource.lastpass_secret.argo-tunnel-secret.password)
    type  = "string"
  }

  set {
    name = "networking.cloudflared.auth.accountTag"
    value = var.cloudflare_account_id
    type = "string"
  }

  set {
    name = "networking.cloudflared.auth.tunnelName"
    value = "cluster.tristanxr.com"
  }

  set {
    name  = "networking.cloudflared.tunnelID"
    value = resource.cloudflare_argo_tunnel.argo-tunnel.id
    type  = "string"
  }

  depends_on = [resource.helm_release.argo-cd, resource.cloudflare_argo_tunnel.argo-tunnel]
}
