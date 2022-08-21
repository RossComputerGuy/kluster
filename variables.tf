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
