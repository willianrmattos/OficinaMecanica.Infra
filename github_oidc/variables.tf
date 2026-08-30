variable "app_display_name" {
  description = "Nome de exibicao da App Registration usada pelo GitHub Actions."
  type        = string
  default     = "github-actions-oficinamecanica"
}

variable "github_repo" {
  description = "Repositorio GitHub no formato 'owner/repo', usado para restringir a Federated Identity Credential a esse repositorio especifico."
  type        = string
}

variable "acr_id" {
  description = "ID do Container Registry (modulo acr), usado para dar permissao de push ao Service Principal do GitHub Actions."
  type        = string
}

variable "aks_id" {
  description = "ID do cluster AKS (modulo aks), usado para dar permissao de buscar credenciais do cluster (az aks get-credentials --admin) ao Service Principal do GitHub Actions."
  type        = string
}

variable "key_vault_id" {
  description = "ID do Key Vault (modulo keyvault), usado para dar permissao de leitura de secrets ao Service Principal do GitHub Actions - o step de migracao do ci.yml (dotnet ef database update) busca a connection string via 'az keyvault secret show' antes do deploy."
  type        = string
}
