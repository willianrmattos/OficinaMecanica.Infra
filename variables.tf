variable "location" {
  description = "Regiao do Azure onde todos os recursos serao criados. A assinatura Azure for Students so permite: chilecentral, canadacentral, northcentralus, eastus, mexicocentral."
  type        = string
  default     = "northcentralus"
}

variable "resource_group_name" {
  description = "Nome do resource group (modulo rg) que agrupa todos os recursos deste projeto."
  type        = string
  default     = "rgfiap"
}

variable "storage_account_name" {
  description = "Nome da storage account (modulo storage) que vai guardar o tfstate remoto."
  type        = string
  default     = "stfiap"
}

variable "registry_name" {
  description = "Nome do Container Registry (modulo acr)."
  type        = string
  default     = "acrfiap"
}

variable "aks_cluster_name" {
  description = "Nome do cluster AKS (modulo aks)."
  type        = string
  default     = "aksfiap"
}

variable "key_vault_name" {
  description = "Nome do Key Vault (modulo keyvault). Globalmente unico."
  type        = string
  default     = "kvfiap"
}

variable "monitoring_storage_class_name" {
  description = "Nome da StorageClass usada pelos PVCs do Prometheus/Grafana. O default e a StorageClass Premium ja provisionada pelo proprio AKS (disk.csi.azure.com, Premium_LRS, reclaimPolicy Delete), sem necessidade de uma StorageClass customizada."
  type        = string
  default     = "managed-csi-premium"
}

variable "sql_location" {
  description = "Regiao do SQL Server (modulo sqldb), independente da regiao do resource group (o SQL Database e publico, nao precisa estar na mesma regiao/VNet dos demais recursos)."
  type        = string
  default     = "canadacentral"
}

variable "sql_server_name" {
  description = "Nome do SQL Server (modulo sqldb). Globalmente unico."
  type        = string
  default     = "svsfiap"
}

variable "sql_database_name" {
  description = "Nome do banco de dados."
  type        = string
  default     = "OficinaMecanicaDb"
}

variable "sql_administrator_login" {
  description = "Usuario administrador do SQL Server."
  type        = string
  default     = "adminfiap"
}

variable "sql_administrator_login_password" {
  description = "Senha do administrador do SQL Server. Sem valor padrao: definir via TF_VAR_sql_administrator_login_password ou um .tfvars nao versionado."
  type        = string
  sensitive   = true
}

variable "sql_client_ip_address" {
  description = "IP publico autorizado a acessar o SQL Server diretamente (execucao de migrations, ferramentas de administracao). Null nao libera nenhum IP especifico."
  type        = string
  default     = null
}


variable "github_repo" {
  description = "Repositorio GitHub no formato 'owner/repo' (modulo github_oidc), usado para restringir a Federated Identity Credential do GitHub Actions a esse repositorio especifico."
  type        = string
  default     = "willianrmattos/OficinaMecanica"
}

variable "apim_name" {
  description = "Nome da instancia do API Management (modulo apim). Globalmente unico (vira <nome>.azure-api.net)."
  type        = string
  default     = "apimfiap"
}

variable "apim_publisher_name" {
  description = "Nome do publisher exibido no portal da APIM."
  type        = string
  default     = "OficinaMecanica"
}

variable "apim_publisher_email" {
  description = "E-mail do publisher da APIM (usado pela Azure para notificacoes). Sem valor padrao: definir via TF_VAR_apim_publisher_email ou um .tfvars nao versionado."
  type        = string
}

variable "seguranca_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Seguranca (modulo sqldb, segundo banco no mesmo servidor svsfiap)."
  type        = string
  default     = "SegurancaDb"
}

variable "seguranca_service_plan_name" {
  description = "Nome do Service Plan (Consumption) da Function App do OficinaMecanica.Seguranca."
  type        = string
  default     = "planfuncsegurancafiap"
}

variable "seguranca_function_app_name" {
  description = "Nome da Function App do OficinaMecanica.Seguranca. Globalmente unico (vira <nome>.azurewebsites.net)."
  type        = string
  default     = "funcsegurancafiap"
}

variable "seguranca_rsa_key_name" {
  description = "Nome da chave RSA (RS256) no Key Vault usada pelo OficinaMecanica.Seguranca pra assinar/expor via JWKS."
  type        = string
  default     = "seguranca-rs256"
}

variable "seguranca_seed_admin_usuario" {
  description = "Nome de usuario do admin inicial seedado pelo OficinaMecanica.Seguranca (nao sensivel - so a senha e)."
  type        = string
  default     = "admin"
}

variable "seguranca_seed_admin_senha" {
  description = "Senha do admin inicial seedado pelo OficinaMecanica.Seguranca, guardada no Key Vault e resolvida via Key Vault Reference nos app_settings da Function App. Sem valor padrao: definir via TF_VAR_seguranca_seed_admin_senha ou um .tfvars nao versionado."
  type        = string
  sensitive   = true
}

variable "seguranca_jwt_issuer" {
  description = "Claim 'iss' dos tokens JWT emitidos pelo OficinaMecanica.Seguranca."
  type        = string
  default     = "OficinaMecanica.Seguranca"
}

variable "seguranca_jwt_audience" {
  description = "Claim 'aud' dos tokens JWT emitidos pelo OficinaMecanica.Seguranca."
  type        = string
  default     = "OficinaMecanica.Client"
}

variable "seguranca_github_repo" {
  description = "Repositorio GitHub do OficinaMecanica.Seguranca no formato 'owner/repo' (modulo github_oidc_seguranca), usado para restringir a Federated Identity Credential a esse repositorio especifico."
  type        = string
  default     = "willianrmattos/OficinaMecanica.Seguranca"
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
