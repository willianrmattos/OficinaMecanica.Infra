variable "app_display_name" {
  description = "Nome de exibicao da App Registration usada pelo GitHub Actions do repositorio OficinaMecanica.Seguranca."
  type        = string
  default     = "github-actions-oficinamecanica-seguranca"
}

variable "github_repo" {
  description = "Repositorio GitHub no formato 'owner/repo' (OficinaMecanica.Seguranca), usado para restringir a Federated Identity Credential a esse repositorio especifico."
  type        = string
}

variable "function_app_id" {
  description = "ID da Function App (modulo functionapp) - escopo da role Contributor concedida ao Service Principal do GitHub Actions."
  type        = string
}
