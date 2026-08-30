variable "location" {
  description = "Regiao do Azure onde o Key Vault sera criado. Sempre fornecido pelo main.tf raiz (module.rg.location)."
  type        = string
}

variable "resource_group_name" {
  description = "Nome do resource group (modulo rg) onde o Key Vault sera criado. Sempre fornecido pelo main.tf raiz (module.rg.resource_group_name)."
  type        = string
}

variable "key_vault_name" {
  description = "Nome do Key Vault. Globalmente unico (vira <nome>.vault.azure.net)."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}

variable "admin_object_id" {
  description = "Object ID fixo (Azure AD) de quem recebe Key Vault Administrator pra uso local (az login). Valor explicito, nao data.azurerm_client_config.current.object_id - esse data source resolve pra quem estiver autenticado no momento em que o terraform roda, e a CI (com sua propria identidade OIDC) tambem roda esse plan/apply; usar o caller atual faria cada lado (humano/CI) ficar substituindo o principal_id um do outro a cada execucao."
  type        = string
}
