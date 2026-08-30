# Le o IP publico do LoadBalancer do ingress-nginx (modulo helm)
# dinamicamente, em vez de hardcodar - o mesmo IP usado hoje pelos hosts
# nip.io de outros Ingress (k8s/mailpit), que ja muda se o Service for
# recriado.
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = var.ingress_nginx_service_name
    namespace = var.ingress_nginx_namespace
  }
}

locals {
  ingress_ip = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
}

# Consumption_0 e o unico valor aceito pro tier serverless (sem capacidade
# dedicada, escala automatica)
resource "azurerm_api_management" "this" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Consumption_0"
  tags                = var.tags
}

# Entidades de Backend proprias (em vez de "service_url" solto em cada API) -
# pra ter varios backends conforme mais servicos entrarem atras da
# APIM, cada um reutilizavel/gerenciado a parte (util pra circuit breaker,
# TLS customizado, etc. no futuro, mesmo que nao usado ainda).
resource "azurerm_api_management_backend" "ingress_nginx" {
  name                = "ingress-nginx"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "http://${local.ingress_ip}"
}

# Sem import de OpenAPI de proposito: passthrough tipo proxy reverso,
# repassando QUALQUER path/metodo pro backend - inclusive coisas que nao vem
# em nenhum OpenAPI, tipo a propria Swagger UI
# (/swagger/*), /health e /metrics (mapeados fora do MVC, o Swashbuckle nem
# documentaria). Troca a curadoria de operations (visiveis uma a uma no
# portal da APIM) por cobertura total sem manutencao manual por endpoint.
resource "azurerm_api_management_api" "oficinamecanica" {
  name                = "oficinamecanica-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "OficinaMecanica API"
  revision            = "1"

  path      = "oficinaserver"
  protocols = ["https"]

  # A API ja tem seu proprio JWT Bearer pras rotas administrativas, e varias
  # rotas sao publicas de proposito (consulta de OS por numero, aprovacao e
  # recusa de orcamento via link de e-mail). Exigir subscription key da APIM
  # por cima quebraria esse fluxo publico
  subscription_required = false
}

# A APIM nao tem um metodo HTTP "curinga" de verdade, precisa de uma
# operation coringa (url_template = "/*") por metodo. GET/POST/PUT/DELETE/PATCH
# cobre os mesmos 5 metodos que a API ja usa (confirmado nas rotas reais do
# Swagger).
resource "azurerm_api_management_api_operation" "oficinamecanica_wildcard" {
  for_each = toset(["GET", "POST", "PUT", "DELETE", "PATCH"])

  operation_id        = "oficinamecanica-passthrough-${lower(each.key)}"
  api_name            = azurerm_api_management_api.oficinamecanica.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "OficinaMecanica (passthrough ${each.key})"
  method              = each.key
  url_template        = "/*"
}

# O backend de verdade (pra onde o trafego vai) e definido aqui via policy,
# nao no "service_url" da API acima - assim a API referencia uma entidade de
# Backend nomeada e reutilizavel, em vez de uma URL solta.
resource "azurerm_api_management_api_policy" "oficinamecanica" {
  api_name            = azurerm_api_management_api.oficinamecanica.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="${azurerm_api_management_backend.ingress_nginx.name}" />
    <!-- A API le esses headers (Program.cs, ForwardedHeadersMiddleware +
         leitura manual do Prefix) pra montar o servers[] do OpenAPI e o
         link de fetch do Swagger UI com a URL publica certa da APIM, nao
         com o scheme/host/path internos que o pod realmente recebe
         (http, IP do ingress-nginx, sem prefixo). -->
    <set-header name="X-Forwarded-Proto" exists-action="override">
      <value>https</value>
    </set-header>
    <set-header name="X-Forwarded-Host" exists-action="override">
      <value>${var.apim_name}.azure-api.net</value>
    </set-header>
    <set-header name="X-Forwarded-Prefix" exists-action="override">
      <value>/oficinaserver</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Nome generico de proposito: esse Product agrupa TUDO que passa pela APIM
# (a API, e o que mais entrar depois) - so existe porque toda API precisa
# pertencer a um Product pra ficar acessivel pelo gateway, nao porque exista
# controle de acesso de verdade aqui (subscription_required = false).
resource "azurerm_api_management_product" "this" {
  product_id            = "gateway"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = var.resource_group_name
  display_name          = "Gateway OficinaMecanica"
  subscription_required = false
  published             = true
}

resource "azurerm_api_management_product_api" "oficinamecanica" {
  api_name            = azurerm_api_management_api.oficinamecanica.name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
}

# Backend do OficinaMecanica.Seguranca - diferente de ingress_nginx acima,
# NAO passa pelo AKS: e uma Azure Function com endpoint HTTPS publico
# proprio (<nome>.azurewebsites.net, certificado gerenciado pela propria
# Azure), sem IP de LoadBalancer nenhum envolvido. "protocol" aqui e so
# http/soap (protocolo do backend, nao o scheme da URL) - o https de
# verdade vem do "url" abaixo, que ja aponta pro endpoint publico da Function.
resource "azurerm_api_management_backend" "seguranca" {
  name                = "seguranca"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "https://${var.seguranca_backend_hostname}"
}

# Mesmo modelo wildcard/passthrough da API principal. Precisa de
# X-Forwarded-* (ver policy abaixo) desde que o Swagger UI foi adicionado -
# o pacote OpenApi do Functions monta o servers[] do documento a partir desses
# headers (DocumentFilter proprio, ver ServerBasePathDocumentFilter no repo
# OficinaMecanica.Seguranca), senao o "Try it out" aponta pro hostname cru da
# Function em vez do path publico via APIM.
resource "azurerm_api_management_api" "seguranca" {
  name                = "seguranca-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "OficinaMecanica Seguranca"
  revision            = "1"

  path      = "segurancaserver"
  protocols = ["https"]

  subscription_required = false
}

resource "azurerm_api_management_api_operation" "seguranca_wildcard" {
  for_each = toset(["GET", "POST", "PUT", "DELETE", "PATCH"])

  operation_id        = "seguranca-passthrough-${lower(each.key)}"
  api_name            = azurerm_api_management_api.seguranca.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "Seguranca (passthrough ${each.key})"
  method              = each.key
  url_template        = "/*"
}

resource "azurerm_api_management_api_policy" "seguranca" {
  api_name            = azurerm_api_management_api.seguranca.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="${azurerm_api_management_backend.seguranca.name}" />
    <!-- A Function le esses headers (ServerBasePathDocumentFilter, repo
         OficinaMecanica.Seguranca) pra montar o servers[] do OpenAPI e o
         "Try it out" do Swagger UI com a URL publica da APIM, nao com o
         hostname cru da Function (que o backend "seguranca" acessa direto,
         sem passar pelo ingress-nginx). Nomes X-Gateway-* (nao X-Forwarded-*)
         de proposito - confirmado na pratica que o App Service intercepta e
         descarta qualquer header client-supplied comecando com
         "X-Forwarded-" antes mesmo de chegar no worker isolado (sobra so
         X-AppService-Proto/X-Original-* do hop interno host->worker, nada do
         que a policy injeta aqui) - nomes fora dessa convencao reservada
         sobrevivem intactos. -->
    <set-header name="X-Gateway-Proto" exists-action="override">
      <value>https</value>
    </set-header>
    <set-header name="X-Gateway-Host" exists-action="override">
      <value>${var.apim_name}.azure-api.net</value>
    </set-header>
    <set-header name="X-Gateway-Prefix" exists-action="override">
      <value>/segurancaserver</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

resource "azurerm_api_management_product_api" "seguranca" {
  api_name            = azurerm_api_management_api.seguranca.name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
}
