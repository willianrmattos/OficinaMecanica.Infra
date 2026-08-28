data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true

  # Soft-delete e obrigatorio desde 2020 e nao pode ser desabilitado; apenas o
  # periodo de retencao e configuravel. Configurei a retencao minima (7 dias)
  # para reduzir o tempo em que o nome do vault ficaria reservado no estado
  # "soft-deleted", caso seja necessario destruir e recriar o recurso com o
  # mesmo nome.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # default_action = "Allow" (nao Deny + allowlist de IP) de proposito - mesmo
  # raciocinio ja usado no API server do AKS (infra/aks, ver CLAUDE.md): o RBAC
  # (rbac_authorization_enabled acima + as role assignments concedidas a cada
  # identidade que precisa acessar) e o portao de acesso de verdade, nao IP.
  # Tentei restringir por IP primeiro (client_ip_address + aks_outbound_ip_address
  # + additional_ip_rules pros IPs de saida da Function App do
  # OficinaMecanica.Seguranca), mas o Function App em tier Consumption tem
  # egress imprevisivel - o proprio possible_outbound_ip_address_list que a
  # Azure expoe NAO e exaustivo (confirmado na pratica: uma chamada real da
  # Function foi bloqueada vindo de um IP que nao estava nessa lista), e o
  # bypass="AzureServices" abaixo tambem NAO cobre esse cenario (testado,
  # "caller is not a trusted service"). Sem alternativa pratica de allowlist
  # de IP confiavel pra esse caso, sem subir uma VNet so pra isso.
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
