# Recursos especificos do OficinaMecanica.Seguranca no Key Vault existente
# (kvfiap) - na raiz (nao dentro do modulo keyvault, nem do functionapp),
# mesmo padrao ja usado por keyvault_secrets.tf/aks_keyvault_access.tf: cada
# um desses arquivos existe pra conectar dois modulos que nao se conhecem
# diretamente (aqui, keyvault + functionapp), o que so e possivel na raiz.

# Chave RSA-2048 de verdade (nao um secret) - a assinatura RS256 e feita
# remotamente contra essa chave via CryptographyClient (ver
# KeyVaultTokenService/KeyVaultJwksProvider no repo OficinaMecanica.Seguranca);
# a chave privada nunca sai do Key Vault. Software-protected (nao HSM) - o
# tier Standard do Key Vault ja suporta, nao precisa de Premium.
resource "azurerm_key_vault_key" "seguranca_rsa" {
  name         = var.seguranca_rsa_key_name
  key_vault_id = module.keyvault.key_vault_id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["sign", "verify"]

  tags = var.tags
}

resource "azurerm_key_vault_secret" "seguranca_sql_connection_string" {
  name         = "seguranca-sql-connection-string"
  key_vault_id = module.keyvault.key_vault_id
  value        = "Server=tcp:${module.sqldb.server_fqdn},1433;Database=${module.sqldb.seguranca_database_name};User Id=${var.sql_administrator_login};Password=${var.sql_administrator_login_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

resource "azurerm_key_vault_secret" "seguranca_seed_admin_senha" {
  name         = "seguranca-seed-admin-senha"
  key_vault_id = module.keyvault.key_vault_id
  value        = var.seguranca_seed_admin_senha
}

# Role assignments pra managed identity (System-Assigned) da Function App -
# "Key Vault Crypto User" so na chave especifica (assinar/verificar, nunca
# ler/exportar a chave privada em si) e "Key Vault Secrets User" no vault
# inteiro (pra resolver os dois secrets acima via Key Vault Reference nos
# app_settings do modulo functionapp).
resource "azurerm_role_assignment" "seguranca_functionapp_crypto_user" {
  scope                = azurerm_key_vault_key.seguranca_rsa.resource_versionless_id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = module.functionapp.principal_id
}

resource "azurerm_role_assignment" "seguranca_functionapp_secrets_user" {
  scope                = module.keyvault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.functionapp.principal_id
}
