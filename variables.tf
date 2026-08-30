variable "admin_object_id" {
  description = "Object ID (Azure AD) do usuario humano dono desta assinatura (obtido via `az ad signed-in-user show`) - usado como principal_id fixo nas role assignments de acesso administrativo (Key Vault Administrator, Storage Blob Data Contributor do tfstate) que antes usavam data.azurerm_client_config.current.object_id. Precisou virar uma variavel explicita porque a CI (identidades github_oidc_infra/github_oidc_banco) tambem roda terraform plan/apply nesse mesmo state - com o data source dinamico, cada lado (humano local vs. CI) ficava substituindo o principal_id do outro a cada execucao."
  type        = string
  default     = "9597844b-eab3-418d-a8dd-f938e9dfaba8"
}

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

variable "newrelic_license_key" {
  description = "License Key da conta New Relic (ingest license key, nao a User API Key). Usada pelo OpenTelemetry Collector (helm/otel-collector.tf) pra autenticar a exportacao OTLP e pelo nri-bundle (helm/newrelic.tf) pra integracao de Kubernetes. Sem valor padrao: definir via TF_VAR_newrelic_license_key ou um .tfvars nao versionado."
  type        = string
  sensitive   = true
}

variable "sql_server_name" {
  description = "Nome do SQL Server, provisionado pelo repositorio irmao OficinaMecanica.Banco - so um 'fato conhecido' aqui, usado pra montar o FQDN nas connection strings (keyvault_secrets.tf/seguranca_keyvault.tf). Globalmente unico."
  type        = string
  default     = "svsfiap"
}

variable "sql_database_name" {
  description = "Nome do banco de dados do monolito, provisionado pelo OficinaMecanica.Banco."
  type        = string
  default     = "OficinaMecanicaDb"
}

variable "sql_administrator_login" {
  description = "Usuario administrador do SQL Server, provisionado pelo OficinaMecanica.Banco."
  type        = string
  default     = "adminfiap"
}

variable "sql_administrator_login_password" {
  description = "Senha do administrador do SQL Server (mesmo valor configurado no OficinaMecanica.Banco). Sem valor padrao: definir via TF_VAR_sql_administrator_login_password ou um .tfvars nao versionado."
  type        = string
  sensitive   = true
}


variable "github_repo" {
  description = "Repositorio GitHub no formato 'owner/repo' (modulo github_oidc), usado para restringir a Federated Identity Credential do GitHub Actions a esse repositorio especifico."
  type        = string
  default     = "willianrmattos/OficinaMecanica"
}

variable "github_repo_infra" {
  description = "Repositorio GitHub deste proprio repo (OficinaMecanica.Infra) no formato 'owner/repo' - usado pelo modulo github_oidc_infra pra restringir as Federated Identity Credentials (PR e push em main/release) a esse repositorio."
  type        = string
  default     = "willianrmattos/OficinaMecanica.Infra"
}

variable "banco_github_repo" {
  description = "Repositorio GitHub do OficinaMecanica.Banco no formato 'owner/repo' - usado pelo modulo github_oidc_banco pra restringir as Federated Identity Credentials (PR e push em main/release) a esse repositorio."
  type        = string
  default     = "willianrmattos/OficinaMecanica.Banco"
}

variable "infra_github_owner_id" {
  description = "ID numerico imutavel da conta 'willianrmattos' no GitHub (obtido via `gh api users/willianrmattos` campo id) - ver comentario em github_oidc_infra/main.tf sobre o formato de subject OIDC com IDs imutaveis (esse repo, assim como Banco e Seguranca, ja nasceu com esse default - confirmado empiricamente pelo erro AADSTS700213 apresentando o subject nesse formato)."
  type        = string
  default     = "33045692"
}

variable "infra_github_repo_id" {
  description = "ID numerico imutavel do repositorio OficinaMecanica.Infra no GitHub (obtido via `gh api repos/willianrmattos/OficinaMecanica.Infra` campo id) - ver infra_github_owner_id."
  type        = string
  default     = "1348724486"
}

variable "banco_github_owner_id" {
  description = "ID numerico imutavel da conta 'willianrmattos' no GitHub - mesmo valor de infra_github_owner_id (mesma conta, repositorio diferente)."
  type        = string
  default     = "33045692"
}

variable "banco_github_repo_id" {
  description = "ID numerico imutavel do repositorio OficinaMecanica.Banco no GitHub (obtido via `gh api repos/willianrmattos/OficinaMecanica.Banco` campo id) - ver infra_github_owner_id."
  type        = string
  default     = "1350606167"
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
  description = "Nome do banco de dados do servico OficinaMecanica.Seguranca (segundo banco no mesmo servidor svsfiap, provisionado pelo OficinaMecanica.Banco)."
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

variable "seguranca_seed_admin_cpf" {
  description = "CPF do admin inicial seedado pelo OficinaMecanica.Seguranca - login passou a ser por CPF, nao nome de usuario (nao sensivel - so a senha e). Valor de exemplo (checksum valido, nao e CPF de ninguem real)."
  type        = string
  default     = "74921686084"
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

variable "seguranca_github_owner_id" {
  description = "ID numerico imutavel da conta 'willianrmattos' no GitHub (obtido via `gh api users/willianrmattos` campo id) - ver comentario em github_oidc_seguranca/main.tf sobre o formato de subject OIDC com IDs imutaveis."
  type        = string
  default     = "33045692"
}

variable "seguranca_github_repo_id" {
  description = "ID numerico imutavel do repositorio OficinaMecanica.Seguranca no GitHub (obtido via `gh api repos/willianrmattos/OficinaMecanica.Seguranca` campo id) - ver seguranca_github_owner_id."
  type        = string
  default     = "1348734211"
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
