terraform {
  required_version = ">= 1.0.1"

  required_providers {
    lastpass = {
      source  = "nrkno/lastpass"
      version = "0.5.3"
    }
  }
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

output "keycloak-admin-password" {
  value = resource.lastpass_secret.keycloak-admin-password.password
}
