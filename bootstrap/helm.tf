resource "helm_release" "prometheus" {
  name = "prometheus"

  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "kube-prometheus"
  version          = "8.0.16"
  namespace        = "prometheus"
  create_namespace = true
}

resource "helm_release" "bootstrap-networking-cert-manager" {
  name = "cert-manager"

  repository       = path.module
  chart            = "networking/cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  depends_on = [resource.helm_release.prometheus]
}

resource "helm_release" "bootstrap-networking-cloudflared" {
  name = "cloudflared"

  repository       = path.module
  chart            = "networking/cloudflared"
  namespace        = "cloudflared"
  create_namespace = true

  set_sensitive {
    name  = "cloudflared.auth.tunnelSecret"
    value = base64encode(resource.random_password.argo-tunnel-secret.result)
    type  = "string"
  }

  set_sensitive {
    name  = "cloudflared.auth.accountTag"
    value = var.cloudflare_account_id
    type  = "string"
  }

  set {
    name  = "cloudflared.auth.tunnelName"
    value = "cluster.tristanxr.com"
  }

  set_sensitive {
    name  = "cloudflared.tunnelID"
    value = resource.cloudflare_argo_tunnel.argo-tunnel.id
    type  = "string"
  }

  depends_on = [resource.cloudflare_argo_tunnel.argo-tunnel]
}

resource "helm_release" "bootstrap-networking-origin-ca-certs" {
  name = "origin-ca-certs"

  repository       = path.module
  chart            = "networking/origin-ca-certs"
  namespace        = "origin-ca-certs"
  create_namespace = true
}
