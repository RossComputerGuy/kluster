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
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "3.11.0-rc.0"
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

module "lastpass" {
  source = "./lastpass"
}

module "bootstrap" {
  source = "./bootstrap"

  cloudflare_account_id    = var.cloudflare_account_id
  cloudflare_token         = var.cloudflare_token
  cloudflare_origin_ca_key = var.cloudflare_origin_ca_key
  keycloak_admin_password  = module.lastpass.keycloak-admin-password
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
  url      = "https://cluster.tristanxr.com/argo-cd"
  username = "admin"
  password = resource.random_password.argo-cd-admin-password.result
}

##
## ArgoCD
##
resource "helm_release" "argo-cd" {
  name = "argo-cd"

  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "4.10.7"
  namespace        = "argo-cd"
  create_namespace = true

  values = [
    yamlencode({
      server = {
        config = {
          "oidc.tls.insecure.skip.verify" = "true"
          "oidc.config" = yamlencode({
            name            = "Keycloak"
            issuer          = "https://cluster.tristanxr.com/keycloak/realms/master"
            clientID        = "argo-cd"
            clientSecret    = "$oidc.keycloak.clientSecret"
            requestedScopes = ["openid", "profile", "email", "groups"]
          })
          "dex.config" = yamlencode({
            connectors = [{
              type = "oidc"
              id   = "keycloak"
              name = "Keycloak"
              config = {
                issuer          = "https://cluster.tristanxr.com/keycloak/realms/master"
                clientID        = "argo-cd"
                clientSecret    = "$oidc.keycloak.clientSecret"
                requestedScopes = ["openid", "profile", "email", "groups"]
              }
            }]
          })
        }
      }
    })
  ]

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(resource.lastpass_secret.argo-cd-admin-password.password)
    type  = "string"
  }

  set_sensitive {
    name  = "configs.secret.extra.oidc\\.keycloak\\.clientSecret"
    value = module.bootstrap.argo-cd-keycloak-client-secret
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
    name  = "server.config.url"
    value = "https://cluster.tristanxr.com/argo-cd/"
  }

  set {
    name  = "server.extraArgs"
    value = "{--basehref,/argo-cd,--rootpath,/argo-cd}"
  }

  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.annotations.cert-manager\\.io/issuer"
    value = "public-issuer"
    type  = "string"
  }

  set {
    name  = "server.ingress.annotations.cert-manager\\.io/issuer-kind"
    value = "OriginIssuer"
    type  = "string"
  }

  set {
    name  = "server.ingress.annotations.cert-manager\\.io/issuer-group"
    value = "cert-manager.k8s.cloudflare.com"
    type  = "string"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/force-ssl-redirect"
    value = "true"
    type  = "string"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/backend-protocol"
    value = "HTTPS"
    type  = "string"
  }

  set {
    name  = "server.ingress.annotations.nginx\\.ingress\\.kubernetes\\.io/rewrite-target"
    value = "/argo-cd/$2"
    type  = "string"
  }

  set {
    name  = "server.ingress.hosts"
    value = "{cluster.tristanxr.com}"
  }

  set {
    name  = "server.ingress.paths"
    value = "{/argo-cd(/|$)(.*)}"
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

  depends_on = [resource.helm_release.argo-cd]
}
