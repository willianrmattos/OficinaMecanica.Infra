# Recursos do OficinaMecanica.Billing no Key Vault existente (kvfiap) - na
# raiz, mesmo padrao de seguranca_keyvault.tf/keyvault_secrets.tf. Cada secret
# aqui e lido SO pelo Billing (SecretProviderClass do repo do servico + a role
# por secret do modulo github_oidc_aks_app) - os valores reais de
# mercadopago-* nunca estao em arquivo versionado, chegam via TF_VAR_* (CI) ou
# variavel de ambiente local.

# Usuario dedicado do Billing (app_billing, db_owner so no BillingDb), criado
# pelo OficinaMecanica.Banco antes deste apply. FQDN montado de variaveis
# simples pelo mesmo motivo de keyvault_secrets.tf (o banco nao e gerenciado
# neste state).
resource "azurerm_key_vault_secret" "billing_sql_connection_string" {
  name         = "billing-sql-connection-string"
  key_vault_id = module.keyvault.key_vault_id
  value        = "Server=tcp:${var.sql_server_name}.database.windows.net,1433;Database=${var.billing_database_name};User Id=${var.sql_app_billing_login};Password=${var.sql_app_billing_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

resource "azurerm_key_vault_secret" "mercadopago_access_token" {
  name         = "mercadopago-access-token"
  key_vault_id = module.keyvault.key_vault_id
  value        = var.mercadopago_access_token
}

resource "azurerm_key_vault_secret" "mercadopago_webhook_secret" {
  name         = "mercadopago-webhook-secret"
  key_vault_id = module.keyvault.key_vault_id
  value        = var.mercadopago_webhook_secret
}
