# SKU Y1 = Consumption - unico tier serverless de verdade (escala a zero,
# sem custo ocioso), sempre gratis ate 1M execucoes/mes - mesma logica do
# tier Consumption ja usado na APIM.
resource "azurerm_service_plan" "this" {
  name                = var.service_plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = var.tags
}

resource "azurerm_linux_function_app" "this" {
  name                = var.function_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  # Reaproveita a mesma storage account do tfstate (modulo storage) como
  # AzureWebJobsStorage - decisao consciente de nao provisionar uma segunda
  # storage account dedicada so pra isso: o volume de uso da Function
  # (Consumption) e baixo o suficiente pra nao justificar isolar o
  # AzureWebJobsStorage do backend do state do Terraform.
  storage_account_name       = var.storage_account_name
  storage_account_access_key = var.storage_account_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version              = "8.0"
      use_dotnet_isolated_runtime = true
    }

    # O Swagger UI (RenderSwaggerUI, pacote OpenApi) embute a URL absoluta do
    # proprio hostname da Function no HTML (nao da pra sobrescrever isso via
    # DocumentFilter - esse so afeta o conteudo do openapi.json/swagger.json
    # em si, nao a pagina HTML) - quando acessado via APIM
    # (apimfiap.azure-api.net/segurancaserver/swagger/ui), o navegador ve a
    # pagina servida por um origin e tenta buscar o swagger.json de outro
    # (funcsegurancafiap.azurewebsites.net), e o browser bloqueia por CORS
    # sem esse header. Sem support_credentials porque o Swagger UI so faz
    # GET anonimo no proprio spec, sem cookies/credenciais.
    cors {
      allowed_origins = ["https://${var.apim_name}.azure-api.net"]
    }
  }

  app_settings = {
    # URI do Key Vault e nome da chave RS256 - NAO sao segredos em si (so
    # identificam onde buscar a chave), ficam em texto plano. O
    # KeyVaultTokenService/KeyVaultJwksProvider (Infrastructure) usam a
    # managed identity do proprio Function App (System-Assigned) pra
    # autenticar no Key Vault via DefaultAzureCredential - nao precisa de
    # client secret nenhum aqui.
    "KeyVault__Uri"        = var.key_vault_uri
    "KeyVault__RsaKeyName" = var.rsa_key_name

    # Esses dois SAO segredos de verdade - referenciados via Key Vault
    # Reference (sintaxe @Microsoft.KeyVault(...)), resolvidos pelo proprio
    # runtime do App Service/Functions em tempo de execucao usando a mesma
    # managed identity acima. Precisa da role "Key Vault Secrets User" no
    # vault (ver a raiz, seguranca_keyvault.tf) pra resolver com sucesso.
    "ConnectionStrings__DefaultConnection" = "@Microsoft.KeyVault(SecretUri=${var.sql_connection_string_secret_uri})"
    "SeedAdmin__SenhaInicial"              = "@Microsoft.KeyVault(SecretUri=${var.seed_admin_senha_secret_uri})"

    "JwtSettings__Issuer"           = var.jwt_issuer
    "JwtSettings__Audience"         = var.jwt_audience
    "JwtSettings__ExpiracaoMinutos" = tostring(var.jwt_expiracao_minutos)
    "SeedAdmin__NomeUsuario"        = var.seed_admin_usuario
  }

  tags = var.tags

  # WEBSITE_RUN_FROM_PACKAGE/WEBSITE_MOUNT_ENABLED sao adicionados pelo
  # proprio mecanismo de deploy (func azure functionapp publish, ou a Azure/
  # functions-action no CI/CD futuro) por fora do Terraform - sem isso, todo
  # "terraform apply" ficaria querendo apagar a referencia pro pacote de
  # codigo que acabou de ser publicado, derrubando a Function ate o proximo
  # deploy. O Terraform continua dono de todo o resto de app_settings acima.
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
      app_settings["WEBSITE_MOUNT_ENABLED"],
    ]
  }
}
