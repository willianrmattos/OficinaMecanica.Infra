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
