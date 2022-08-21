output "argocd-admin-password" {
  description = "ArgoCD Admin Password: use this for CLI"
  value       = resource.lastpass_secret.argo-cd-admin-password.password
  sensitive   = true
}
