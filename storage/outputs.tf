output "storage_account_name" {
  description = "Nome da storage account criada."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "ID da storage account criada."
  value       = azurerm_storage_account.this.id
}

output "container_name" {
  description = "Nome do container de blob criado para guardar o tfstate."
  value       = azurerm_storage_container.tfstate.name
}

output "primary_access_key" {
  description = "Chave de acesso primaria da storage account - usada pelo modulo functionapp pra configurar o AzureWebJobsStorage da Function App que reaproveita esta mesma storage account."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}
