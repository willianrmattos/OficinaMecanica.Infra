# Mesmo padrao de OIDC do modulo github_oidc (App Registration + Federated
# Identity Credential, sem secret de longa duracao) - modulo SEPARADO (nao
# uma segunda instancia do github_oidc existente) porque a permissao
# necessaria e bem diferente: aqui e so "Contributor" escopado na propria
# Function App (deploy via zip), sem ACR nem AKS - nao faz sentido forcar o
# github_oidc existente (feito sob medida pra imagem+cluster) a acomodar
# essa segunda forma de deploy.

resource "azuread_application" "github_actions_seguranca" {
  display_name = var.app_display_name
}

resource "azuread_service_principal" "github_actions_seguranca" {
  client_id = azuread_application.github_actions_seguranca.client_id
}

resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.github_actions_seguranca.id
  display_name   = "github-actions-main-branch"
  description    = "Permite ao workflow do GitHub Actions autenticar via OIDC, restrito a branch main de ${var.github_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # Subject com IDs imutaveis embutidos (owner@ownerId/repo@repoId), NAO o
  # formato classico "repo:owner/repo:ref:..." usado no modulo github_oidc
  # (OficinaMecanica) - essa conta/repo do GitHub ja nasceu com o novo default de
  # subject com IDs imutaveis (confirmado via
  # `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`, campo
  # sub_claim_prefix - nao da pra reverter pelo endpoint do proprio
  # repositorio, `use_default: false` nao muda o prefixo retornado). Sem
  # isso, o login OIDC falha com AADSTS700213 (subject nao bate com
  # nenhuma credencial federada).
  subject = "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "release_branch" {
  application_id = azuread_application.github_actions_seguranca.id
  display_name   = "github-actions-release-branch"
  description    = "Permite ao workflow do GitHub Actions autenticar via OIDC, restrito a branch release de ${var.github_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # Mesmo formato de subject com IDs imutaveis da credential "main_branch"
  # acima - so troca o nome da branch.
  subject = "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}:ref:refs/heads/release"
}

# So Contributor na propria Function App (nao no resource group inteiro) -
# suficiente pra "az functionapp deployment source config-zip"/
# "Azure/functions-action", sem precisar de AcrPush nem de role nenhuma no
# cluster AKS (o deploy da Function e so um zip, sem imagem/container).
resource "azurerm_role_assignment" "function_app_contributor" {
  scope                            = var.function_app_id
  role_definition_name             = "Contributor"
  principal_id                     = azuread_service_principal.github_actions_seguranca.object_id
  skip_service_principal_aad_check = true
}

# Permissao pro step "Aplicar migrations" (ci.yml): le a connection string
# via "az keyvault secret show" antes do dotnet ef database update. Key
# Vault Secrets User (RBAC de dados, so leitura) - Contributor na Function
# App (acima) nao inclui acesso de dados ao Key Vault.
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                            = var.key_vault_id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azuread_service_principal.github_actions_seguranca.object_id
  skip_service_principal_aad_check = true
}
