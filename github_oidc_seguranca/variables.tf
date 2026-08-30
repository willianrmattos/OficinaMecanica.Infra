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

variable "key_vault_id" {
  description = "ID do Key Vault (modulo keyvault), usado para dar permissao de leitura de secrets ao Service Principal do GitHub Actions - o step de migracao do ci.yml (dotnet ef database update) busca a connection string via 'az keyvault secret show' antes de rodar."
  type        = string
}

variable "github_owner_id" {
  description = "ID numerico imutavel da conta GitHub dona do repositorio (nao o login/nome) - obtido via `gh api users/<owner>` ou `gh api repos/<owner>/<repo>` campo owner.id. Necessario porque essa conta/repo do GitHub usa por padrao o formato de subject OIDC com IDs imutaveis embutidos (owner@ownerId/repo@repoId), nao o formato classico repo:owner/repo - ver comentario em main.tf."
  type        = string
}

variable "github_repo_id" {
  description = "ID numerico imutavel do repositorio (nao o nome) - obtido via `gh api repos/<owner>/<repo>` campo id. Ver github_owner_id."
  type        = string
}
