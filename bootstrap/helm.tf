resource "helm_release" "prometheus" {
  name = "prometheus"

  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "kube-prometheus"
  version          = "8.0.16"
  namespace        = "prometheus"
  create_namespace = true
}

resource "helm_release" "cert-manager" {
  name = "cert-manager"

  repository       = path.root
  chart            = "bootstrap/networking/cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  depends_on = [resource.helm_release.prometheus]
}

resource "helm_release" "cloudflared" {
  name = "cloudflared"

  repository       = path.root
  chart            = "bootstrap/networking/cloudflared"
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

resource "helm_release" "origin-ca-issuer" {
  name = "origin-ca-certs"

  repository       = path.root
  chart            = "bootstrap/networking/origin-ca-issuer"
  namespace        = "origin-ca-issuer"
  create_namespace = true

  depends_on = [resource.helm_release.cert-manager]
}
