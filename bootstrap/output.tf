output "argo-cd-keycloak-client-secret" {
  value = resource.keycloak_openid_client.argo-cd.client_secret
}
