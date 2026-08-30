# Identidade OIDC unica do proprio repositorio (OficinaMecanica.Infra) -
# cobre tanto "terraform plan" em Pull Requests quanto "terraform apply"
# de verdade em push (main/release). Optei por 1 identidade so (nao uma
# pra plan e outra pra apply, como cheguei a fazer): PR passa a rodar com
# um token tecnicamente capaz de escrever, nao so ler - aceito
# conscientemente pra um projeto pessoal, sem colaborador externo abrindo
# PR. Mesmo padrao de "uma identidade por repo" ja usado no modulo
# github_oidc_banco/ (equivalente do OficinaMecanica.Banco).
#
# required_resource_access + azuread_app_role_assignment concedem
# Application.ReadWrite.All (Microsoft Graph, permissao de aplicativo) -
# necessario porque os modulos github_oidc*/github_oidc_seguranca deste
# repo criam/gerenciam App Registrations e Service Principals via
# Terraform. O "admin consent" dessa app role assignment exige que quem
# roda o apply (localmente, com az login, ou via CI usando esta mesma
# identidade depois de o consent inicial ja ter sido dado) seja Global
# Administrator ou equivalente no tenant.

resource "azuread_application" "github_actions" {
  display_name = var.app_display_name

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9" # Application.ReadWrite.All (App role, nao delegated)
      type = "Role"
    }
  }
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-pull-request"
  description    = "Permite ao workflow de terraform plan (PR) do OficinaMecanica.Infra autenticar via OIDC."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-main-branch"
  description    = "Permite ao workflow de terraform apply (push em main) do OficinaMecanica.Infra autenticar via OIDC."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "release_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-release-branch"
  description    = "Permite ao workflow de terraform apply (push em release) do OficinaMecanica.Infra autenticar via OIDC."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/release"
}

# Contributor no resource group inteiro - cobre tudo que o Terraform deste
# repo realmente gerencia (AKS, ACR, Key Vault, Storage, APIM, Function
# App). Antes era so Reader (quando essa identidade so fazia plan); agora
# tambem precisa aplicar de verdade.
resource "azurerm_role_assignment" "resource_group_contributor" {
  scope                            = var.resource_group_id
  role_definition_name             = "Contributor"
  principal_id                     = azuread_service_principal.github_actions.object_id
  skip_service_principal_aad_check = true
}

# Storage Blob Data CONTRIBUTOR (nao so Reader) escopado no container
# "tfstate" - Contributor (control-plane, acima) NAO inclui acesso de
# dados a blob; sem essa role especifica de dados, "terraform apply"
# conseguiria ler o state mas falharia ao tentar escrever o state
# atualizado de volta no final.
resource "azurerm_role_assignment" "tfstate_container_contributor" {
  scope                            = "${var.storage_account_id}/blobServices/default/containers/${var.tfstate_container_name}"
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azuread_service_principal.github_actions.object_id
  skip_service_principal_aad_check = true
}

data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

resource "azuread_app_role_assignment" "graph_application_readwrite_all" {
  app_role_id         = "1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9"
  principal_object_id = azuread_service_principal.github_actions.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
