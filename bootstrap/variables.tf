variable "cloudflare_account_id" {
  type        = string
  description = "The Cloudflare Account ID to use"
  sensitive   = true
  nullable    = false
}

variable "cloudflare_token" {
  type        = string
  description = "The Cloudflare Token to use"
  sensitive   = true
  nullable    = false
}

variable "cloudflare_origin_ca_key" {
  type        = string
  description = "The Cloudflare Origin CA key to use"
  sensitive   = true
  nullable    = false
}

variable "keycloak_admin_password" {
  type        = string
  description = "The admin password to set for Keycloak"
  sensitive   = true
  nullable    = false
}
