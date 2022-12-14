###
### Keycloak setup
###
resource "helm_release" "keycloak" {
  name = "keycloak"

  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "keycloak"
  version          = "9.6.9"
  namespace        = "keycloak"
  create_namespace = true

  set {
    name  = "httpRelativePath"
    value = "/keycloak/"
  }

  set {
    name  = "auth.adminUser"
    value = "admin"
  }

  set_sensitive {
    name  = "auth.adminPassword"
    value = var.keycloak_admin_password
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
    value = var.keycloak_admin_password
  }

  set_sensitive {
    name  = "postgresql.auth.password"
    value = var.keycloak_admin_password
  }

  depends_on = [
    resource.helm_release.cloudflared
  ]
}

provider "keycloak" {
  client_id     = "admin-cli"
  username      = "admin"
  password      = var.keycloak_admin_password
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
    "https://cluster.tristanxr.com",
  ]

  depends_on = [resource.helm_release.keycloak, data.keycloak_realm.master]
}

resource "keycloak_openid_client" "argo-workflows" {
  realm_id  = data.keycloak_realm.master.id
  client_id = "argo-workflows"

  name                         = "Argo Workflows"
  enabled                      = true
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  access_type                  = "CONFIDENTIAL"
  root_url                     = "https://cluster.tristanxr.com/argo-workflows"
  admin_url                    = "https://cluster.tristanxr.com/argo-workflows"
  base_url                     = "/applications"

  valid_redirect_uris = [
    "https://cluster.tristanxr.com/argo-workflows/oauth2/callback"
  ]

  web_origins = [
    "https://cluster.tristanxr.com",
  ]

  depends_on = [resource.helm_release.keycloak, data.keycloak_realm.master]
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

resource "keycloak_group" "argo-cd-admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "argo-cd-admin"
}

resource "keycloak_group" "argo-workflows-admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "argo-workflows-admin"
}
