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

variable "billing_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Billing (terceiro banco no mesmo servidor logico svsfiap, provisionado pelo OficinaMecanica.Banco)."
  type        = string
  default     = "BillingDb"
}

# As apps NUNCA usam o administrador do SQL Server: o OficinaMecanica.Banco
# cria um usuario contido dedicado por banco (db_owner so no proprio banco) e
# este repo monta as connection strings do Key Vault com esses usuarios. Os
# nomes das tres variaveis de senha sao um contrato com o Banco (mesmos nomes
# nos dois repos); o administrador do servidor ficou so la.
variable "sql_app_os_login" {
  description = "Login do usuario SQL contido dedicado do OS Service (OficinaMecanica) no banco OficinaMecanicaDb - criado pelo OficinaMecanica.Banco."
  type        = string
  default     = "app_os"
}

variable "sql_app_os_password" {
  description = "Senha do usuario SQL dedicado do OS Service (mesmo valor usado pelo OficinaMecanica.Banco pra cria-lo). Sem valor padrao: definir via TF_VAR_sql_app_os_password ou um .tfvars nao versionado. Minimo 8 caracteres, sem ponto e virgula nem aspas (quebrariam a connection string)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_app_os_password) >= 8 && !can(regex("[;'\"]", var.sql_app_os_password))
    error_message = "sql_app_os_password precisa ter pelo menos 8 caracteres e nao pode conter ponto e virgula nem aspas."
  }
}

variable "sql_app_seguranca_login" {
  description = "Login do usuario SQL contido dedicado do OficinaMecanica.Seguranca no banco SegurancaDb - criado pelo OficinaMecanica.Banco."
  type        = string
  default     = "app_seguranca"
}

variable "sql_app_seguranca_password" {
  description = "Senha do usuario SQL dedicado do OficinaMecanica.Seguranca (mesmo valor usado pelo OficinaMecanica.Banco pra cria-lo). Sem valor padrao: definir via TF_VAR_sql_app_seguranca_password ou um .tfvars nao versionado. Minimo 8 caracteres, sem ponto e virgula nem aspas."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_app_seguranca_password) >= 8 && !can(regex("[;'\"]", var.sql_app_seguranca_password))
    error_message = "sql_app_seguranca_password precisa ter pelo menos 8 caracteres e nao pode conter ponto e virgula nem aspas."
  }
}

variable "sql_app_billing_login" {
  description = "Login do usuario SQL contido dedicado do OficinaMecanica.Billing no banco BillingDb - criado pelo OficinaMecanica.Banco."
  type        = string
  default     = "app_billing"
}

variable "sql_app_billing_password" {
  description = "Senha do usuario SQL dedicado do OficinaMecanica.Billing (mesmo valor usado pelo OficinaMecanica.Banco pra cria-lo). Sem valor padrao: definir via TF_VAR_sql_app_billing_password ou um .tfvars nao versionado. Minimo 8 caracteres, sem ponto e virgula nem aspas."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_app_billing_password) >= 8 && !can(regex("[;'\"]", var.sql_app_billing_password))
    error_message = "sql_app_billing_password precisa ter pelo menos 8 caracteres e nao pode conter ponto e virgula nem aspas."
  }
}

variable "rabbitmq_username" {
  description = "Usuario administrativo do RabbitMQ (namespace messaging), criado no primeiro boot do broker e guardado no Key Vault como rabbitmq-username. A senha e gerada por random_password (messaging_keyvault.tf), nao e variavel."
  type        = string
  default     = "oficina"
}

variable "mercadopago_access_token" {
  description = "Access Token da aplicacao do Mercado Pago (credencial de teste/sandbox ou producao, conforme o ambiente), guardado no Key Vault como mercadopago-access-token e lido so pelo OficinaMecanica.Billing. Sem valor padrao: definir via TF_VAR_mercadopago_access_token ou um .tfvars nao versionado - o valor real nunca vai pro repositorio."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mercadopago_access_token) > 0
    error_message = "mercadopago_access_token nao pode ser vazio."
  }
}

variable "mercadopago_webhook_secret" {
  description = "Chave secreta da assinatura de webhook (x-signature, HMAC-SHA256) configurada na aplicacao do Mercado Pago, guardada no Key Vault como mercadopago-webhook-secret e lida so pelo OficinaMecanica.Billing. Sem valor padrao: definir via TF_VAR_mercadopago_webhook_secret ou um .tfvars nao versionado."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mercadopago_webhook_secret) > 0
    error_message = "mercadopago_webhook_secret nao pode ser vazio."
  }
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
  description = "CPF do admin inicial seedado pelo OficinaMecanica.Seguranca - login passou a ser por CPF, nao nome de usuario (nao sensivel - so a senha e). Sem valor padrao: definir via TF_VAR_seguranca_seed_admin_cpf ou um .tfvars nao versionado."
  type        = string
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

# Os repositorios Billing e Execucao ainda nao existem no GitHub, entao nao ha
# repo_id pra preencher: default = null faz o modulo OIDC correspondente nao
# ser criado (count = 0 em main.tf), mantendo validate/plan verdes ate a
# publicacao. Depois de criar o repositorio:
#   gh api repos/willianrmattos/OficinaMecanica.Billing --jq .id
# e gravar o valor no default abaixo (e nao so num .tfvars local: o CI nao
# enxerga .tfvars, e um plan sem o id proporia destruir a identidade).
variable "billing_github_repo" {
  description = "Repositorio GitHub do OficinaMecanica.Billing no formato 'owner/repo' - usado pelo modulo github_oidc_aks_app pra restringir as Federated Identity Credentials (push em main/release) a esse repositorio."
  type        = string
  default     = "willianrmattos/OficinaMecanica.Billing"
}

variable "billing_github_owner_id" {
  description = "ID numerico imutavel da conta 'willianrmattos' no GitHub - mesmo valor de seguranca_github_owner_id (mesma conta, repositorio diferente)."
  type        = string
  default     = "33045692"
}

variable "billing_github_repo_id" {
  description = "ID numerico imutavel do repositorio OficinaMecanica.Billing no GitHub (`gh api repos/willianrmattos/OficinaMecanica.Billing --jq .id`), so conhecido depois que o repositorio e criado. null (padrao) = repositorio ainda nao existe: a identidade OIDC do Billing nao e criada. Quando preenchido, o modulo passa a existir e o output billing_github_actions_client_id passa a ter valor."
  type        = string
  default     = null

  validation {
    condition     = var.billing_github_repo_id == null || can(regex("^[0-9]+$", var.billing_github_repo_id))
    error_message = "billing_github_repo_id deve ser o ID numerico do repositorio (so digitos) ou null."
  }
}

variable "execucao_github_repo" {
  description = "Repositorio GitHub do OficinaMecanica.Execucao no formato 'owner/repo' - usado pelo modulo github_oidc_aks_app pra restringir as Federated Identity Credentials (push em main/release) a esse repositorio."
  type        = string
  default     = "willianrmattos/OficinaMecanica.Execucao"
}

variable "execucao_github_owner_id" {
  description = "ID numerico imutavel da conta 'willianrmattos' no GitHub - mesmo valor de seguranca_github_owner_id (mesma conta, repositorio diferente)."
  type        = string
  default     = "33045692"
}

variable "execucao_github_repo_id" {
  description = "ID numerico imutavel do repositorio OficinaMecanica.Execucao no GitHub (`gh api repos/willianrmattos/OficinaMecanica.Execucao --jq .id`), so conhecido depois que o repositorio e criado. null (padrao) = repositorio ainda nao existe: a identidade OIDC da Execucao nao e criada. Quando preenchido, o modulo passa a existir e o output execucao_github_actions_client_id passa a ter valor."
  type        = string
  default     = null

  validation {
    condition     = var.execucao_github_repo_id == null || can(regex("^[0-9]+$", var.execucao_github_repo_id))
    error_message = "execucao_github_repo_id deve ser o ID numerico do repositorio (so digitos) ou null."
  }
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
