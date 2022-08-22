provider "cloudflare" {
  api_token            = var.cloudflare_token
  api_user_service_key = var.cloudflare_origin_ca_key
}

resource "random_password" "argo-tunnel-secret" {
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
