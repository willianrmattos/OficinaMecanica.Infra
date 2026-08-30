variable "app_display_name" {
  description = "Nome de exibicao da App Registration usada pelo CI (validate + apply) do OficinaMecanica.Banco."
  type        = string
  default     = "github-actions-banco"
}

variable "github_repo" {
  description = "Repositorio GitHub do OficinaMecanica.Banco no formato 'owner/repo', usado para restringir a Federated Identity Credential a esse repositorio especifico."
  type        = string
}

variable "resource_group_id" {
  description = "ID do resource group (modulo rg) - o principal recebe Reader nele inteiro, pra terraform plan conseguir ler o estado atual de qualquer recurso gerenciado."
  type        = string
}

variable "storage_account_id" {
  description = "ID da storage account (modulo storage) que guarda o tfstate remoto."
  type        = string
}

variable "tfstate_container_name" {
  description = "Nome do container de blob que guarda o tfstate."
  type        = string
  default     = "tfstate"
}

variable "subscription_id" {
  description = "Subscription ID da assinatura Azure atual - usado so pra montar o escopo do role assignment Contributor (ID do SQL Server)."
  type        = string
}

variable "resource_group_name" {
  description = "Nome do resource group (rgfiap) onde o SQL Server do Banco vive - usado so pra montar o escopo do role assignment Contributor (ID do SQL Server)."
  type        = string
}

variable "sql_server_name" {
  description = "Nome do SQL Server logico do OficinaMecanica.Banco (svsfiap) - usado so pra montar o escopo do role assignment Contributor."
  type        = string
}
