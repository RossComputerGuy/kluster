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

provider "cloudflare" {
  api_token            = var.cloudflare_token
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
  url      = "https://cluster.tristanxr.com/argo-cd"
  username = "admin"
  password = resource.random_password.argo-cd-admin-password.result
}

resource "random_password" "keycloak-admin-password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "lastpass_secret" "keycloak-admin-password" {
  name     = "Kubernetes Cluster: Keycloak Admin Password"
  url      = "https://cluster.tristanxr.com/keycloak"
  username = "admin"
  password = resource.random_password.keycloak-admin-password.result
}

resource "random_password" "argo-tunnel-secret" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "keycloak-tls-key-password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "keycloak-tls-trust-password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

##
## Cloudflare Argo Tunnel
##
resource "cloudflare_argo_tunnel" "argo-tunnel" {
  account_id = var.cloudflare_account_id
  name       = "cluster.tristanxr.com"
  secret     = base64encode(resource.random_password.argo-tunnel-secret.result)
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

resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = "keycloak"
  }
}

resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "prometheus"
  }
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

###
### Keycloak setup
###
resource "helm_release" "keycloak" {
  name = "keycloak"

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  version    = "9.6.9"
  namespace  = "keycloak"

  set {
    name  = "httpRelativePath"
    value = "/keycloak/"
  }

  set_sensitive {
    name  = "auth.tls.keystorePassword"
    value = resource.random_password.keycloak-tls-key-password.result
  }

  set_sensitive {
    name  = "auth.tls.truststorePassword"
    value = resource.random_password.keycloak-tls-trust-password.result
  }

  set {
    name  = "auth.adminUser"
    value = "admin"
  }

  set_sensitive {
    name  = "auth.adminPassword"
    value = resource.lastpass_secret.keycloak-admin-password.password
    type  = "string"
  }

  set {
    name  = "service.type"
    value = "ClusterIP"
  }

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "ingress.path"
    value = "/keycloak"
  }

  set {
    name  = "ingress.hostname"
    value = "cluster.tristanxr.com"
  }

  set {
    name  = "metrics.enabled"
    value = "true"
  }

  set {
    name  = "metrics.serviceMonitor.enabled"
    value = "true"
  }

  set_sensitive {
    name  = "postgresql.auth.postgresPassword"
    value = resource.lastpass_secret.keycloak-admin-password.password
  }

  set_sensitive {
    name  = "postgresql.auth.password"
    value = resource.lastpass_secret.keycloak-admin-password.password
  }

  depends_on = [
    resource.lastpass_secret.keycloak-admin-password,
    resource.kubernetes_namespace.keycloak
  ]
}

provider "keycloak" {
  client_id     = "admin-cli"
  username      = "admin"
  password      = resource.lastpass_secret.keycloak-admin-password.password
  url           = "https://cluster.tristanxr.com"
  base_path     = "/keycloak"
  initial_login = false
}

data "keycloak_realm" "master" {
  realm      = "master"
  depends_on = [resource.helm_release.keycloak]
}

resource "keycloak_openid_client" "argo-cd" {
  realm_id  = data.keycloak_realm.master.id
  client_id = "argo-cd"

  name                         = "ArgoCD"
  enabled                      = true
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  access_type                  = "CONFIDENTIAL"
  root_url                     = "https://cluster.tristanxr.com/argo-cd"
  admin_url                    = "https://cluster.tristanxr.com/argo-cd"
  base_url                     = "/applications"

  valid_redirect_uris = [
    "https://cluster.tristanxr.com/argo-cd/auth/callback"
  ]

  web_origins = [
    "https://cluster.tristanxr.com/argo-cd/",
    "https://cluster.tristanxr.com/argo-cd/*",
    "https://cluster.tristanxr.com/argo-cd/*/*"
  ]

  depends_on = [data.keycloak_realm.master]
}

resource "keycloak_openid_client_scope" "groups" {
  realm_id = data.keycloak_realm.master.id
  name     = "groups"
}

resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id        = data.keycloak_realm.master.id
  client_scope_id = resource.keycloak_openid_client_scope.groups.id
  name            = "groups"
  claim_name      = "groups"

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

resource "keycloak_openid_client_default_scopes" "argo-cd" {
  realm_id  = data.keycloak_realm.master.id
  client_id = resource.keycloak_openid_client.argo-cd.id

  default_scopes = [
    "email",
    "profile",
    "roles",
    "web-origins",
    resource.keycloak_openid_group_membership_protocol_mapper.groups.name
  ]
}

data "kubernetes_service_account" "keycloak" {
  metadata {
    name = "keycloak"
    namespace = "keycloak"
  }
}

data "kubernetes_secret" "keycloak-token" {
  metadata {
    name = "${data.kubernetes_service_account.keycloak.default_secret_name}"
    namespace = "keycloak"
  }
}

##
## ArgoCD
##
resource "helm_release" "argo-cd" {
  name = "argo-cd"

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "4.10.7"
  namespace  = "argo-cd"

  values = [
    yamlencode({
      server = {
        config = {
          "oidc.config" = yamlencode({
            name = "Keycloak"
            issuer = "https://cluster.tristanxr.com/keycloak/realms/master"
            clientID = "argo-cd"
            clientSecret = "$oidc.keycloak.clientSecret"
            requestedScopes = ["openid", "profile", "email", "groups"]
            rootCA = data.kubernetes_secret.keycloak-token.data["ca.crt"]
          })
          "dex.config" = yamlencode({
            connectors = [{
              type = "oidc"
              id = "keycloak"
              name = "Keycloak"
              config = {
                issuer = "https://cluster.tristanxr.com/keycloak/realms/master"
                clientID = "argo-cd"
                clientSecret = "$oidc.keycloak.clientSecret"
                requestedScopes = ["openid", "profile", "email", "groups"]
                rootCA = data.kubernetes_secret.keycloak-token.data["ca.crt"]
              }
            }]
          })
        }
      }
    })
  ]

  set_sensitive {
    name  = "configs.tlsCerts.data.cluster\\.tristanxr\\.com"
    value = data.kubernetes_secret.keycloak-token.data["ca.crt"]
    type  = "string"
  }

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(resource.lastpass_secret.argo-cd-admin-password.password)
    type  = "string"
  }

  set_sensitive {
    name = "configs.secret.extra.oidc\\.keycloak\\.clientSecret"
    value = resource.keycloak_openid_client.argo-cd.client_secret
    type = "string"
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

  depends_on = [
    resource.kubernetes_namespace.argo-cd,
    resource.helm_release.prometheus,
    resource.keycloak_openid_client.argo-cd
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

  set_sensitive {
    name  = "networking.originKey"
    value = var.cloudflare_origin_ca_key
  }

  set_sensitive {
    name  = "networking.cloudflared.auth.tunnelSecret"
    value = base64encode(resource.random_password.argo-tunnel-secret.result)
    type  = "string"
  }

  set_sensitive {
    name  = "networking.cloudflared.auth.accountTag"
    value = var.cloudflare_account_id
    type  = "string"
  }

  set {
    name  = "networking.cloudflared.auth.tunnelName"
    value = "cluster.tristanxr.com"
  }

  set_sensitive {
    name  = "networking.cloudflared.tunnelID"
    value = resource.cloudflare_argo_tunnel.argo-tunnel.id
    type  = "string"
  }

  depends_on = [resource.helm_release.argo-cd, resource.cloudflare_argo_tunnel.argo-tunnel]
}
