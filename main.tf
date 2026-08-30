data "azurerm_client_config" "current" {}

module "rg" {
  source = "./rg"

  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

module "storage" {
  source = "./storage"

  location             = module.rg.location
  resource_group_name  = module.rg.resource_group_name
  storage_account_name = var.storage_account_name
  admin_object_id      = var.admin_object_id
  tags                 = var.tags
}

module "acr" {
  source = "./acr"

  location            = module.rg.location
  resource_group_name = module.rg.resource_group_name
  registry_name       = var.registry_name
  tags                = var.tags
}

module "aks" {
  source = "./aks"

  location            = module.rg.location
  resource_group_name = module.rg.resource_group_name
  cluster_name        = var.aks_cluster_name
  acr_id              = module.acr.registry_id
  tags                = var.tags
}

module "keyvault" {
  source = "./keyvault"

  location            = module.rg.location
  resource_group_name = module.rg.resource_group_name
  key_vault_name      = var.key_vault_name
  admin_object_id     = var.admin_object_id
  tags                = var.tags
}

module "helm" {
  source = "./helm"

  newrelic_license_key = var.newrelic_license_key

  depends_on = [module.aks]
}

module "github_oidc" {
  source = "./github_oidc"

  github_repo  = var.github_repo
  acr_id       = module.acr.registry_id
  aks_id       = module.aks.cluster_id
  key_vault_id = module.keyvault.key_vault_id
}

module "github_oidc_infra" {
  source = "./github_oidc_infra"

  github_repo     = var.github_repo_infra
  github_owner_id = var.infra_github_owner_id
  github_repo_id  = var.infra_github_repo_id

  resource_group_id  = module.rg.resource_group_id
  storage_account_id = module.storage.storage_account_id
  key_vault_id       = module.keyvault.key_vault_id
}

module "github_oidc_banco" {
  source = "./github_oidc_banco"

  github_repo     = var.banco_github_repo
  github_owner_id = var.banco_github_owner_id
  github_repo_id  = var.banco_github_repo_id

  resource_group_id  = module.rg.resource_group_id
  storage_account_id = module.storage.storage_account_id

  subscription_id     = data.azurerm_client_config.current.subscription_id
  resource_group_name = module.rg.resource_group_name
  sql_server_name     = var.sql_server_name
}

module "functionapp" {
  source = "./functionapp"

  location            = module.rg.location
  resource_group_name = module.rg.resource_group_name
  service_plan_name   = var.seguranca_service_plan_name
  function_app_name   = var.seguranca_function_app_name

  storage_account_name       = module.storage.storage_account_name
  storage_account_access_key = module.storage.primary_access_key

  # Todas as tres URIs abaixo sao construidas a partir de variaveis simples
  # (nao module.keyvault.key_vault_uri / azurerm_key_vault_secret.*.id) de
  # proposito - evita uma dependencia circular entre os modulos keyvault e
  # functionapp (a Function App precisa da managed identity do Key Vault
  # resolvida, mas o Key Vault em si nao depende de nada da Function App
  # desde que o acesso virou RBAC puro, sem firewall por IP - ver keyvault/
  # main.tf). Os nomes dos secrets aqui tem que bater exatamente com os
  # definidos em seguranca_keyvault.tf.
  key_vault_uri                    = "https://${var.key_vault_name}.vault.azure.net/"
  rsa_key_name                     = var.seguranca_rsa_key_name
  sql_connection_string_secret_uri = "https://${var.key_vault_name}.vault.azure.net/secrets/seguranca-sql-connection-string/"
  seed_admin_senha_secret_uri      = "https://${var.key_vault_name}.vault.azure.net/secrets/seguranca-seed-admin-senha/"
  seed_admin_usuario               = var.seguranca_seed_admin_usuario

  jwt_issuer   = var.seguranca_jwt_issuer
  jwt_audience = var.seguranca_jwt_audience

  apim_name = var.apim_name

  tags = var.tags
}

module "github_oidc_seguranca" {
  source = "./github_oidc_seguranca"

  github_repo     = var.seguranca_github_repo
  github_owner_id = var.seguranca_github_owner_id
  github_repo_id  = var.seguranca_github_repo_id
  function_app_id = module.functionapp.function_app_id
}

module "apim" {
  source = "./apim"

  location                   = module.rg.location
  resource_group_name        = module.rg.resource_group_name
  apim_name                  = var.apim_name
  publisher_name             = var.apim_publisher_name
  publisher_email            = var.apim_publisher_email
  ingress_nginx_namespace    = module.helm.release_namespace
  seguranca_backend_hostname = module.functionapp.default_hostname
  tags                       = var.tags
}
