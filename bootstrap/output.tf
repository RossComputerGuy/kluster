output "argo-cd-keycloak-client-secret" {
  value = resource.keycloak_openid_client.argo-cd.client_secret
}

output "argo-workflows-keycloak-client-secret" {
  value = resource.keycloak_openid_client.argo-workflows.client_secret
}
