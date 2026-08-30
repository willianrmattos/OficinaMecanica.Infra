variable "app_display_name" {
  description = "Nome de exibicao da App Registration usada pelo CI (validate + apply) do OficinaMecanica.Infra."
  type        = string
  default     = "github-actions-infra"
}

variable "github_repo" {
  description = "Repositorio GitHub do OficinaMecanica.Infra no formato 'owner/repo', usado para restringir as Federated Identity Credentials (PR e push em main/release) a esse repositorio especifico."
  type        = string
}

variable "github_owner_id" {
  description = "ID numerico imutavel da conta dona do repositorio no GitHub - ver comentario em main.tf sobre o formato de subject OIDC com IDs imutaveis."
  type        = string
}

variable "github_repo_id" {
  description = "ID numerico imutavel do repositorio OficinaMecanica.Infra no GitHub - ver github_owner_id."
  type        = string
}

variable "resource_group_id" {
  description = "ID do resource group (modulo rg) - o principal recebe Contributor nele inteiro, cobrindo tanto plan/validate quanto apply de verdade."
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
