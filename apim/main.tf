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
# portal da APIM) por cobertura total sem manutencao manual por endpoint. A
# excecao e /health/ready e /metrics, que a policy de cada API de negocio
# bloqueia com 404 (ver o local bloqueio_endpoints_internos abaixo).
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

# Guard compartilhado pelas tres APIs de negocio (esta e as do for_each
# ingress_services; a do Seguranca fica de fora porque la nao existe
# /health/ready nem /metrics). A operacao coringa "/*" repassa qualquer path, e
# /health/ready (abre conexao com banco e broker) e /metrics (contadores) sao
# anonimos nos servicos, entao a internet os alcancaria pela APIM. Optei por um
# arquivo so, incluido em cada policy, em vez de repetir o XML por servico. As
# probes do Kubernetes batem direto no pod e nao passam por aqui.
#
# O guard fica logo depois do <base /> (herda o que vier de escopos mais amplos)
# e antes do set-backend-service: responde 404 sem chamar o backend. A policy da
# API roda depois das de escopo mais amplo, e o path do backend (/billing,
# /execucao) so e somado a requisicao ao backend, depois da secao inbound.
# Mesmo assim testo o FINAL do path, nao um caminho completo: sem apply nao sei
# se context.Request.Url.Path chega com o prefixo da API (/billingserver/...),
# e o final do path e o mesmo com ou sem prefixo. A query string nao entra em
# Url.Path (a APIM expoe Query/QueryString a parte). A decodificacao (%XX) e a
# tolerancia a "//" e "/." existem porque o ingress-nginx e o ASP.NET Core
# normalizam o path depois da APIM: sem isso "/health/%72eady" chegaria ao pod
# como /health/ready.
#
# Rollout em duas etapas: Billing e Execucao (sem trafego em producao) recebem
# o guard sempre; o oficinaserver (OS Service, em producao) so quando
# var.bloquear_endpoints_internos_no_oficinaserver for true. Uma policy
# expression so e validada em execucao, e um erro nela derrubaria TODAS as
# rotas da API, entao o primeiro apply prova o guard nas APIs novas e so
# depois eu ligo a variavel. Com false o texto da policy do oficinaserver
# fica identico ao de antes do guard (a quebra de linha antes do guard faz
# parte do trecho condicional), entao o plan nao propoe mudanca nela.
locals {
  bloqueio_endpoints_internos = trimspace(file("${path.module}/bloqueio-health-ready-e-metrics.xml"))

  bloqueio_oficinaserver = var.bloquear_endpoints_internos_no_oficinaserver ? "\n    ${indent(4, local.bloqueio_endpoints_internos)}" : ""
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
    <base />${local.bloqueio_oficinaserver}
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

# Billing e Execucao: mesmos modelos wildcard/passthrough das APIs acima, mas
# atras do MESMO ingress-nginx do monolito, diferenciados por prefixo de path
# (o monolito segue catch-all em "/"). Optei por for_each sobre um mapa (e nao
# por copiar os blocos como fiz com oficinamecanica/seguranca) porque os dois
# so diferem em nome/path/prefixo - um servico novo atras do ingress-nginx e
# uma entrada nesse mapa.
locals {
  ingress_services = {
    billing = {
      api_name     = "billing-api"
      display_name = "OficinaMecanica Billing"
      path         = "billingserver"
      backend_path = "/billing"
    }
    execucao = {
      api_name     = "execucao-api"
      display_name = "OficinaMecanica Execucao"
      path         = "execucaoserver"
      backend_path = "/execucao"
    }
  }

  http_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
}

# A URL do backend inclui o PREFIXO DE PATH roteado pelo ingress-nginx
# (http://<ip>/billing, http://<ip>/execucao): o Ingress de cada servico
# (repo do servico, k8s/) casa esse prefixo e remove com rewrite-target antes
# de entregar ao pod. PREMISSA PENDENTE DE CONFIRMACAO no ambiente real (nao
# da pra provar sem apply): que a APIM concatena o path do backend com o path
# da operacao, ou seja, GET /billingserver/health chega no ingress como
# GET /billing/health. Se nao concatenar (o path chegaria sem o prefixo e cairia
# na regra catch-all do monolito), a alternativa e deixar o backend so com o
# IP e reescrever na policy: <rewrite-uri template="@("/billing" +
# context.Request.Url.Path.Substring(context.Api.Path.Length + 1))" />.
resource "azurerm_api_management_backend" "ingress_services" {
  for_each = local.ingress_services

  name                = each.key
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "http://${local.ingress_ip}${each.value.backend_path}"
}

# subscription_required = false pelo mesmo motivo da API do monolito: cada
# servico valida o proprio JWT, e o webhook do Mercado Pago do Billing
# (https://<apim>.azure-api.net/billingserver/webhooks/mercadopago) entra
# anonimo - quem o autentica e a assinatura HMAC (x-signature) validada pelo
# proprio Billing.
resource "azurerm_api_management_api" "ingress_services" {
  for_each = local.ingress_services

  name                = each.value.api_name
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = each.value.display_name
  revision            = "1"

  path      = each.value.path
  protocols = ["https"]

  subscription_required = false
}

resource "azurerm_api_management_api_operation" "ingress_services_wildcard" {
  for_each = {
    for pair in setproduct(keys(local.ingress_services), local.http_methods) :
    "${pair[0]}-${lower(pair[1])}" => {
      service = pair[0]
      method  = pair[1]
    }
  }

  operation_id        = "${each.value.service}-passthrough-${lower(each.value.method)}"
  api_name            = azurerm_api_management_api.ingress_services[each.value.service].name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "${local.ingress_services[each.value.service].display_name} (passthrough ${each.value.method})"
  method              = each.value.method
  url_template        = "/*"
}

resource "azurerm_api_management_api_policy" "ingress_services" {
  for_each = local.ingress_services

  api_name            = azurerm_api_management_api.ingress_services[each.key].name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    ${indent(4, local.bloqueio_endpoints_internos)}
    <set-backend-service backend-id="${azurerm_api_management_backend.ingress_services[each.key].name}" />
    <!-- Mesmos X-Forwarded-* da API do monolito: o servico le esses headers
         pra montar o servers[] do OpenAPI e o Swagger UI com a URL publica
         da APIM e o prefixo do gateway (${each.value.path}), nao com o
         scheme/host/path internos que o pod recebe. O prefixo do ingress
         (${each.value.backend_path}) e removido pelo rewrite do Ingress, entao
         nao aparece aqui. -->
    <set-header name="X-Forwarded-Proto" exists-action="override">
      <value>https</value>
    </set-header>
    <set-header name="X-Forwarded-Host" exists-action="override">
      <value>${var.apim_name}.azure-api.net</value>
    </set-header>
    <set-header name="X-Forwarded-Prefix" exists-action="override">
      <value>/${each.value.path}</value>
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

resource "azurerm_api_management_product_api" "ingress_services" {
  for_each = local.ingress_services

  api_name            = azurerm_api_management_api.ingress_services[each.key].name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
}
