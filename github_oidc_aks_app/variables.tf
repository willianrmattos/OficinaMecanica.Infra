variable "app_display_name" {
  description = "Nome de exibicao da App Registration usada pelo GitHub Actions deste servico (ex: github-actions-oficinamecanica-billing). Sem valor padrao de proposito: o modulo e instanciado uma vez por servico e cada instancia precisa de um nome distinto."
  type        = string
}

variable "github_repo" {
  description = "Repositorio GitHub do servico no formato 'owner/repo', usado para restringir as Federated Identity Credentials (push em main/release) a esse repositorio especifico."
  type        = string
}

variable "github_owner_id" {
  description = "ID numerico imutavel da conta dona do repositorio no GitHub (obtido via `gh api users/<owner>` campo id) - ver comentario em main.tf sobre o formato de subject OIDC com IDs imutaveis."
  type        = string
}

variable "github_repo_id" {
  description = "ID numerico imutavel do repositorio do servico no GitHub (obtido via `gh api repos/<owner>/<repo> --jq .id`) - so existe depois que o repositorio e criado no GitHub. Ver github_owner_id."
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

variable "key_vault_secret_scopes" {
  description = "Mapa nome-do-secret => ID de recurso (ARM) do secret no Key Vault, ex: azurerm_key_vault_secret.x.resource_versionless_id ou \"<id do vault>/secrets/<nome>\". O Service Principal recebe Key Vault Secrets User (leitura) SOMENTE em cada um desses secrets - o step de migration do CI do servico le a connection string do proprio banco. As chaves precisam ser conhecidas no plan (use o nome do secret); os valores podem ser conhecidos so no apply."
  type        = map(string)
  default     = {}
}
