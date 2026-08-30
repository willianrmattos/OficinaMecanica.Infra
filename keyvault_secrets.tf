# Optei por guardar os segredos da aplicacao no Key Vault (modulo keyvault),
# em vez de aplicados manualmente via k8s/oficinamecanica-api/secret.yaml. O
# CSI Secrets Store driver (addon do modulo aks) sincroniza esses valores pro
# Secret nativo do Kubernetes automaticamente - ver
# k8s/oficinamecanica-api/secret-provider-class.yaml.
#
# Deixei esses recursos na raiz (nao dentro do modulo keyvault) de proposito:
# o modulo keyvault so cuida do vault em si (recurso generico e reutilizavel);
# quem sabe quais segredos esta aplicacao especifica precisa e a raiz.

resource "azurerm_key_vault_secret" "sql_connection_string" {
  name = "sql-connection-string"
  # FQDN montado a partir de var.sql_server_name (nao module.sqldb.server_fqdn) -
  # o banco foi extraido pro repositorio irmao OficinaMecanica.Banco (state
  # proprio), essas variaveis aqui so descrevem "fatos conhecidos" sobre um
  # recurso que este repo nao gerencia mais - mesmo padrao ja usado pro Key
  # Vault (key_vault_uri montado a partir de var.key_vault_name, ver
  # functionapp/main.tf).
  value        = "Server=tcp:${var.sql_server_name}.database.windows.net,1433;Database=${var.sql_database_name};User Id=${var.sql_administrator_login};Password=${var.sql_administrator_login_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = module.keyvault.key_vault_id
}

# Guardo aqui so como fonte da verdade auditavel (mesmo padrao dos demais
# segredos deste arquivo) - quem realmente consome o valor e o
# kubernetes_secret criado direto em helm/otel-collector.tf, a partir da
# mesma var.newrelic_license_key (nao ha sincronizacao KeyVault->K8s via CSI
# aqui: nem o Collector nem o nri-bundle rodam no namespace da API, e o
# Terraform ja tem o valor em maos pra criar o Secret nativo diretamente).
resource "azurerm_key_vault_secret" "newrelic_license_key" {
  name         = "newrelic-license-key"
  value        = var.newrelic_license_key
  key_vault_id = module.keyvault.key_vault_id
}
