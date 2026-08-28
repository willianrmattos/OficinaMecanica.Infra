# Optei por deixar na raiz (nao dentro de aks/ nem keyvault/): a role
# assignment abaixo precisa do ID do Key Vault (saida do modulo keyvault) e
# do principal do addon CSI (saida do modulo aks) - se vivesse dentro de
# qualquer um dos dois, os module blocks passariam a depender um do outro
# (dependencia circular, que o Terraform recusa).
#
# O Key Vault (keyvault/main.tf) usa network_acls.default_action = "Allow"
# (nao mais restrito por IP) - por isso nao existe mais aqui um data source
# descobrindo o IP de saida do cluster: essa role assignment (RBAC) e o
# unico portao de acesso de verdade pro addon CSI conseguir ler secrets.
resource "azurerm_role_assignment" "aks_keyvault_secrets_user" {
  scope                            = module.keyvault.key_vault_id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = module.aks.key_vault_secrets_provider_object_id
  skip_service_principal_aad_check = true
}
