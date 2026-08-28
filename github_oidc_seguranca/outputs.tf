output "client_id" {
  description = "Client ID (Application ID) da App Registration - usar como variavel AZURE_CLIENT_ID no repositorio OficinaMecanica.Seguranca."
  value       = azuread_application.github_actions_seguranca.client_id
}

output "service_principal_object_id" {
  description = "Object ID do Service Principal - util para debugar/consultar role assignments."
  value       = azuread_service_principal.github_actions_seguranca.object_id
}
