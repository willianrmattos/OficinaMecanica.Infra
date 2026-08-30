# Identidade OIDC unica do OficinaMecanica.Banco - cobre tanto "terraform
# plan" em Pull Requests quanto "terraform apply" de verdade em push
# (main/release). Modulo gemeo de github_oidc_infra/ - identidade
# dedicada por repo (mesmo padrao ja usado em github_oidc/
# github_oidc_seguranca), nao compartilhada entre os dois. Optei por 1
# identidade so (nao uma pra plan e outra pra apply, como cheguei a
# fazer): PR passa a rodar com um token tecnicamente capaz de escrever,
# nao so ler - aceito conscientemente pra um projeto pessoal, sem
# colaborador externo abrindo PR.
#
# Vive aqui (no repositorio Infra) e nao no proprio Banco pelo mesmo
# motivo de github_oidc_seguranca/: centraliza toda identidade/permissao
# de acesso ao Azure num unico lugar, mesmo quando o repositorio que ela
# protege e outro.

resource "azuread_application" "github_actions" {
  display_name = var.app_display_name
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-pull-request"
  description    = "Permite ao workflow de terraform plan (PR) do OficinaMecanica.Banco autenticar via OIDC."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-main-branch"
  description    = "Permite ao workflow de terraform apply (push em main) do OficinaMecanica.Banco autenticar via OIDC."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "release_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-release-branch"
  description    = "Permite ao workflow de terraform apply (push em release) do OficinaMecanica.Banco autenticar via OIDC."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/release"
}

# Reader no resource group inteiro - so pra resolver o "data
# azurerm_resource_group existing" do Banco (le propriedades do rgfiap
# que o proprio Banco nao gerencia) - nao precisa de mais que isso nesse
# escopo, ja que o Banco nao mexe em mais nada do resource group.
resource "azurerm_role_assignment" "resource_group_reader" {
  scope                            = var.resource_group_id
  role_definition_name             = "Reader"
  principal_id                     = azuread_service_principal.github_actions.object_id
  skip_service_principal_aad_check = true
}

# Contributor escopado so no SQL Server (nao no resource group inteiro) -
# e o unico recurso que este repo de fato gerencia/aplica.
resource "azurerm_role_assignment" "sql_server_contributor" {
  scope                            = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Sql/servers/${var.sql_server_name}"
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
