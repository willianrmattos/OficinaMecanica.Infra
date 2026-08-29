output "function_app_id" {
  description = "ID (ARM resource ID) da Function App criada - escopo de role assignments (ex: modulo github_oidc_seguranca)."
  value       = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  description = "Nome da Function App criada."
  value       = azurerm_linux_function_app.this.name
}

output "default_hostname" {
  description = "Hostname publico da Function App (<nome>.azurewebsites.net) - usado como backend da APIM (modulo apim)."
  value       = azurerm_linux_function_app.this.default_hostname
}

output "principal_id" {
  description = "Object ID da managed identity (System-Assigned) da Function App - usado para conceder role assignments a ela (Key Vault Crypto User / Secrets User)."
  value       = azurerm_linux_function_app.this.identity[0].principal_id
}
