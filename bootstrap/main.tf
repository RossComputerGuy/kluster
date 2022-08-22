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


