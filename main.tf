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

  depends_on = [resource.helm_release.argo-cd]
}