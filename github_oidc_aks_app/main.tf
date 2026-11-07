# Identidade OIDC de um servico que roda no AKS e e entregue por imagem no
# ACR (Billing, Execucao, e os proximos). Modulo PARAMETRIZADO por servico:
# uma instancia por repositorio, cada uma com App Registration/Service
# Principal proprios, pra que o pipeline de um servico nunca consiga agir com
# a identidade de outro (requisito de independencia - docs/adr/0006). Mesmo
# padrao dos modulos github_oidc_banco/github_oidc_seguranca (sem client
# secret, Federated Identity Credential por branch), com uma diferenca
# deliberada: NAO ha credencial pra "pull_request" - o job de deploy tem
# AcrPush e Cluster Admin, entao so push em main/release pode autenticar.
# Modulo separado do github_oidc (monolito) por escolha minha: aquele ja esta
# aplicado com subject no formato antigo e nao devo mexer nele.

resource "azuread_application" "github_actions" {
  display_name = var.app_display_name
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

locals {
  # Subject com IDs imutaveis embutidos (owner@ownerId/repo@repoId), o
  # formato que as contas/repos novos do GitHub emitem por padrao (mesmo dos
  # modulos github_oidc_seguranca/github_oidc_banco). Alem de ser o formato
  # que o Azure AD recebe, o ID nao muda se o repositorio for renomeado ou
  # transferido e recriado com o mesmo nome por outra pessoa.
  github_subject_prefix = "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}"
}

resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-main-branch"
  description    = "Permite ao workflow do GitHub Actions autenticar via OIDC, restrito a branch main de ${var.github_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${local.github_subject_prefix}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "release_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-release-branch"
  description    = "Permite ao workflow do GitHub Actions autenticar via OIDC, restrito a branch release de ${var.github_repo}."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${local.github_subject_prefix}:ref:refs/heads/release"
}

# Estagio de build+push: so envia imagens ao ACR. AcrPush e o menor papel
# built-in que permite push; o escopo e o registry inteiro porque restringir
# por repositorio exige o modo ABAC do ACR, que nao habilitei neste registry
# - limitacao registrada no ADR 0006.
resource "azurerm_role_assignment" "acr_push" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPush"
  principal_id                     = azuread_service_principal.github_actions.object_id
  skip_service_principal_aad_check = true
}

# Estagio de deploy: busca o kubeconfig (az aks get-credentials --admin) pra
# rodar kubectl. "Cluster Admin Role" porque o cluster usa contas locais (sem
# Azure RBAC pra autorizacao dentro do Kubernetes) - mesmo motivo do
# github_oidc. Esse papel so libera buscar o kubeconfig; nao ha papel Azure
# mais fino que ainda permita o kubectl apply.
resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                            = var.aks_id
  role_definition_name             = "Azure Kubernetes Service Cluster Admin Role"
  principal_id                     = azuread_service_principal.github_actions.object_id
  skip_service_principal_aad_check = true
}

# Key Vault Secrets User (RBAC de dados, so leitura) escopado em CADA secret
# que o servico consome (id de recurso do secret), nao no vault inteiro: e o
# que faz "segredos no Key Vault: so os seus" valer tambem pro pipeline - o
# step de migration le a connection string do proprio banco e nada alem.
# for_each sobre mapa com chaves estaticas (nome do secret): os valores
# (ids) podem ser conhecidos so no apply.
resource "azurerm_role_assignment" "keyvault_secret_reader" {
  for_each = var.key_vault_secret_scopes

  scope                            = each.value
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azuread_service_principal.github_actions.object_id
  skip_service_principal_aad_check = true
}
