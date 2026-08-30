variable "location" {
  description = "Regiao do Azure onde a Function App sera criada."
  type        = string
}

variable "resource_group_name" {
  description = "Nome do resource group (modulo rg) onde a Function App sera criada. Sempre fornecido pelo main.tf raiz (module.rg.resource_group_name)."
  type        = string
}

variable "service_plan_name" {
  description = "Nome do Service Plan (Consumption)."
  type        = string
}

variable "function_app_name" {
  description = "Nome da Function App. Globalmente unico - vira <nome>.azurewebsites.net."
  type        = string
}

variable "storage_account_name" {
  description = "Nome da storage account reaproveitada como AzureWebJobsStorage (modulo storage - a mesma usada pelo tfstate)."
  type        = string
}

variable "storage_account_access_key" {
  description = "Chave de acesso da storage account acima."
  type        = string
  sensitive   = true
}

variable "key_vault_uri" {
  description = "URI do Key Vault (https://<nome>.vault.azure.net/) - construido a partir do nome (variavel simples, nao module.keyvault.key_vault_uri) de proposito, pra nao criar dependencia circular entre os modulos keyvault e functionapp (o Key Vault hoje e RBAC puro, sem firewall por IP - ver keyvault/main.tf - entao a variavel simples so evita o acoplamento entre modulos, nao contorna mais nenhuma dependencia de firewall)."
  type        = string
}

variable "rsa_key_name" {
  description = "Nome da chave RSA (RS256) no Key Vault usada pra assinar/expor via JWKS."
  type        = string
}

variable "sql_connection_string_secret_uri" {
  description = "URI do secret no Key Vault com a connection string do banco SegurancaDb, referenciado via Key Vault Reference (@Microsoft.KeyVault(...))."
  type        = string
}

variable "seed_admin_senha_secret_uri" {
  description = "URI do secret no Key Vault com a senha inicial do admin seedado, referenciado via Key Vault Reference (@Microsoft.KeyVault(...))."
  type        = string
}

variable "seed_admin_cpf" {
  description = "CPF do admin inicial seedado (nao sensivel - so a senha e). Valor de exemplo (checksum valido, nao e CPF de ninguem real)."
  type        = string
  default     = "74921686084"
}

variable "jwt_issuer" {
  description = "Claim 'iss' dos tokens JWT emitidos."
  type        = string
}

variable "jwt_audience" {
  description = "Claim 'aud' dos tokens JWT emitidos."
  type        = string
}

variable "jwt_expiracao_minutos" {
  description = "Minutos de validade de cada token JWT emitido."
  type        = number
  default     = 60
}

variable "apim_name" {
  description = "Nome da instancia da APIM (sem .azure-api.net) - usado so pra liberar CORS na Function App pro host publico da APIM (o backend 'seguranca' da APIM acessa essa Function direto, sem ingress-nginx no meio; sem esse CORS, o Swagger UI servido via APIM falha ao buscar seu proprio swagger.json, que aponta pro hostname cru da Function)."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
