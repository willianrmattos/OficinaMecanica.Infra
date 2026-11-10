# OficinaMecanica.Infra

Infraestrutura como codigo (Terraform) para o ecossistema OficinaMecanica —
provisiona todos os recursos Azure usados pelos repositorios de aplicacao
(`OficinaMecanica`, `OficinaMecanica.Seguranca`, `OficinaMecanica.Billing`,
`OficinaMecanica.Execucao` e futuros), num unico lugar centralizado.

Migrado do repositorio `OficinaMecanica` (onde vivia em `infra/`) — mesmo
backend de state remoto, nenhum recurso foi recriado no Azure durante a
migracao.

## Ecossistema de microsservicos

O monolito original evoluiu para quatro servicos independentes, cada um com
repositorio, banco, pipeline, identidade OIDC (OpenID Connect) e rota na APIM
(API Management) proprios. Eles so se conectam em runtime (RabbitMQ para a
Saga, HTTP/JWKS para a identidade) e nenhum acessa o banco de outro. Este
repositorio provisiona a plataforma compartilhada que os hospeda; o codigo de
cada servico mora no repositorio dele.

| Repositorio | Papel | Onde se encaixa nesta infraestrutura |
|-------------|-------|--------------------------------------|
| [OficinaMecanica](../OficinaMecanica) (OS Service) | Cadastros, ordens de servico e **orquestrador da Saga** (`MassTransitStateMachine` + outbox/inbox transacionais): OS aberta -> diagnostico -> orcamento -> aprovacao -> pagamento -> reparo -> finalizada, com compensacao em cada etapa | AKS (namespace `default`), rota APIM `oficinaserver`, `OficinaMecanicaDb` (usuario `app_os`), identidade `github_oidc` |
| [OficinaMecanica.Billing](../OficinaMecanica.Billing) | Orcamento e pagamento, integrado ao Mercado Pago (Checkout Pro, webhook assinado, estorno idempotente) | AKS (`default`), rota `billingserver`, `BillingDb` (usuario `app_billing`), secrets `mercadopago-*`, identidade `github_oidc_billing` |
| [OficinaMecanica.Execucao](../OficinaMecanica.Execucao) | Fila de execucao, diagnostico e reparo (o mecanico reivindica itens da fila de forma atomica) | AKS (`default`), rota `execucaoserver`, MongoDB Atlas M0 (provisionado pelo Banco), identidade `github_oidc_execucao` |
| [OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca) | Autenticacao/autorizacao: emite JWT (JSON Web Token) RS256 e expoe `/.well-known/jwks.json` | Function App (Consumption, fora do AKS), rota `segurancaserver`, `SegurancaDb` (usuario `app_seguranca`), chave `seguranca-rs256` no Key Vault, identidade `github_oidc_seguranca` |
| [OficinaMecanica.Banco](../OficinaMecanica.Banco) | Terraform dos bancos (Azure SQL e MongoDB Atlas) | Repositorio irmao com state proprio; este repo so conhece os "fatos" dele (nomes, logins) |

```
Cliente / Admin / Mecanico
        |
        v
Azure API Management (apimfiap, tier Consumption)
   |-- /oficinaserver   --> ingress-nginx --> OS Service (catch-all "/")  --+
   |-- /billingserver   --> ingress-nginx --> Billing   (prefixo /billing)  +--> RabbitMQ (AKS, ns messaging):
   |-- /execucaoserver  --> ingress-nginx --> Execucao  (prefixo /execucao) +    comandos e eventos da Saga
   `-- /segurancaserver --> Function App (Seguranca: emite JWT, expoe JWKS)      (MassTransit)
        (OS Service, Billing e Execucao so validam o JWT, via JWKS do Seguranca)

Dados (OficinaMecanica.Banco): Azure SQL svsfiap (OficinaMecanicaDb | SegurancaDb | BillingDb)
                               e MongoDB Atlas M0 (banco execucao)
Segredos: Key Vault kvfiap (CSI Secrets Store nos pods; Key Vault Reference na Function App)
```

## Diagramas

| Documento | Arquivo |
|-----------|---------|
| Visao de Componentes (nuvem, APIs, banco, monitoramento) - **anterior aos microsservicos**: cobre so o OS Service (o antigo monolito), o Seguranca, o `ingress-nginx`, o Collector/New Relic, `OficinaMecanicaDb`/`SegurancaDb` e o Key Vault; ainda nao mostra Billing, Execucao, RabbitMQ, `BillingDb` nem o MongoDB Atlas (use o diagrama ASCII acima) | [docs/diagramas/diagrama-de-componentes.jpg](docs/diagramas/diagrama-de-componentes.jpg) |

## RFCs (decisoes de "por que essa direcao")

| RFC | Titulo |
|-----|--------|
| 0001 | [Terraform centralizado em repositorio proprio](docs/rfc/0001-terraform-centralizado-em-repositorio-proprio.md) |
| 0002 | [Observabilidade - New Relic + OpenTelemetry Collector](docs/rfc/0002-observabilidade-new-relic-otel-collector.md) |

## ADRs (decisoes tecnicas pontuais)

| ADR | Titulo |
|-----|--------|
| 0001 | [OIDC/Federated Identity em vez de secrets de longa duracao](docs/adr/0001-oidc-federated-identity-github-actions.md) |
| 0002 | [API Management na frente do ingress-nginx](docs/adr/0002-apim-gateway-na-frente-do-ingress-nginx.md) |
| 0003 | [Homologacao e producao no mesmo cluster/aplicacao](docs/adr/0003-homologacao-e-producao-no-mesmo-cluster.md) |
| 0004 | [RabbitMQ no AKS via StatefulSet com imagem oficial](docs/adr/0004-rabbitmq-no-aks-statefulset-com-imagem-oficial.md) |
| 0005 | [Usuario SQL dedicado por banco e secrets por servico](docs/adr/0005-usuario-sql-dedicado-por-banco-e-secrets-por-servico.md) |
| 0006 | [Modulo OIDC parametrizado por servico e criacao condicional](docs/adr/0006-modulo-oidc-parametrizado-por-servico-e-criacao-condicional.md) |
| 0007 | [Bloqueio de `/health/ready` e `/metrics` na APIM](docs/adr/0007-bloqueio-de-health-ready-e-metrics-na-apim.md) |

## Modulos

| Modulo | Recurso Azure | Finalidade |
|--------|---------------|------------|
| `rg` | Resource Group | Agrupa todos os recursos do projeto |
| `storage` | Storage Account | Backend remoto do state do Terraform |
| `acr` | Azure Container Registry | Registro das imagens Docker da API |
| `aks` | Azure Kubernetes Service | Orquestracao dos containers em producao |
| `keyvault` | Azure Key Vault | Armazenamento centralizado de segredos, acesso via RBAC (role assignments), sem restricao de rede |
| `helm` | Helm Releases (ingress-nginx, OpenTelemetry Collector, nri-bundle) + StatefulSet do RabbitMQ | Ingress Controller, observabilidade (traces/metricas/logs via OpenTelemetry Collector, CPU/memoria via New Relic Infrastructure) e o broker de mensageria da Saga (`rabbitmq.tf`, namespace `messaging`, ver [Microsservicos](#microsservicos-billing-execucao-e-rabbitmq)) |
| `github_oidc` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica` no Azure via OIDC, sem secrets de longa duracao |
| `functionapp` | Azure Function App (Consumption) | Hospeda o `OficinaMecanica.Seguranca` (autenticacao/autorizacao, emissao de JWT RS256) |
| `github_oidc_seguranca` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica.Seguranca` no Azure via OIDC |
| `github_oidc_infra` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions deste proprio repositorio (`OficinaMecanica.Infra`) no Azure via OIDC |
| `github_oidc_banco` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica.Banco` no Azure via OIDC (sem role no Key Vault: o secret do Mongo e gravado pelo root `atlas/` do Banco, aplicado so localmente) |
| `github_oidc_aks_app` | Azure AD App Registration + Federated Identity Credential | Modulo **parametrizado por servico** (`AcrPush` no ACR + `Azure Kubernetes Service Cluster Admin Role` no AKS + `Key Vault Secrets User` **por secret**, via `key_vault_secret_scopes`), instanciado na raiz como `github_oidc_billing` (secret `billing-sql-connection-string`) e `github_oidc_execucao` (mapa vazio: nenhuma role no Key Vault). Credenciais federadas so para push em `main`/`release` (sem `pull_request`). Cada instancia so e criada (`count`) quando `billing_github_repo_id`/`execucao_github_repo_id` e informado (ver [Microsservicos](#microsservicos-billing-execucao-e-rabbitmq) e [ADR 0006](docs/adr/0006-modulo-oidc-parametrizado-por-servico-e-criacao-condicional.md)) |
| `apim` | Azure API Management (Consumption) | Gateway de API na frente do `ingress-nginx` (OS Service, Billing, Execucao) e da Function App; as APIs de negocio bloqueiam `/health/ready` e `/metrics` com 404 (Billing e Execucao sempre; o `oficinaserver` so com `bloquear_endpoints_internos_no_oficinaserver = true`; ver [API Gateway](#api-gateway) abaixo) |

O SQL Server (`svsfiap`) e os bancos `OficinaMecanicaDb`/`SegurancaDb`/
`BillingDb` foram extraidos pro repositorio irmao
[OficinaMecanica.Banco](../OficinaMecanica.Banco) (state proprio, mesma
storage account/container do tfstate deste repo) — este repositorio so
guarda variaveis com os "fatos conhecidos" sobre o banco (nome do servidor,
nomes dos bancos, logins e senhas dos **usuarios dedicados por banco**
`app_os`/`app_seguranca`/`app_billing`, nunca o administrador do servidor)
pra montar as connection strings salvas no Key Vault, sem depender do state
do `OficinaMecanica.Banco` (ver [ADR 0005](docs/adr/0005-usuario-sql-dedicado-por-banco-e-secrets-por-servico.md)).

Cinco arquivos na raiz (`keyvault_secrets.tf`, `aks_keyvault_access.tf`,
`seguranca_keyvault.tf`, `billing_keyvault.tf`, `messaging_keyvault.tf`)
conectam modulos entre si sem criar dependencia circular entre eles - cada um
precisa enxergar dois (ou mais) modulos ao mesmo tempo, o que so e possivel
na raiz.

## Provisionando a infraestrutura

Pre-requisitos:

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 (o CI usa 1.15.7) e Azure CLI autenticado (`az login`) com permissao na assinatura.
- `OficinaMecanica.Banco` ja aplicado (bancos e usuarios SQL dedicados) - ver [Ordem de aplicacao](#ordem-de-aplicacao-banco---infra). O MongoDB Atlas (conta, organizacao, API key e o secret `execucao-mongo-connection-string`) vive no root `atlas/` do Banco, aplicado so localmente: nao e pre-requisito deste repositorio, so precisa estar aplicado antes do deploy da Execucao.
- Credenciais da aplicacao do Mercado Pago (access token e chave secreta do webhook, de teste ou producao) e a License Key da conta New Relic.
- As tres senhas `sql_app_*_password` iguais as configuradas no Banco. O Banco aplica uma regra mais estrita que a validacao deste repo (16 a 128 caracteres entre letras, digitos e `_ . @ # % ^ * + ~ -`, com maiuscula, minuscula e digito); usar uma senha que atenda as duas.
- Em ambiente novo (sem o cluster), os providers `helm`/`kubernetes` sao configurados a partir dos outputs do `module.aks` (ver o comentario em `providers.tf`): o cluster precisa existir antes, entao aplicar primeiro `-target="module.aks"` e depois o restante. No ambiente atual o `aksfiap` ja existe.

```bash
cp terraform.tfvars.example terraform.tfvars   # preencher os valores (nomes de recursos, regiao, etc.)

# Variaveis sensiveis (ou sem default por outro motivo) nao tem default em
# terraform.tfvars.example de proposito (nunca commitadas) - definir via
# variavel de ambiente antes do apply:
export TF_VAR_sql_app_os_password="<senha-do-usuario-app_os>"
export TF_VAR_sql_app_seguranca_password="<senha-do-usuario-app_seguranca>"
export TF_VAR_sql_app_billing_password="<senha-do-usuario-app_billing>"
export TF_VAR_apim_publisher_email="<seu-email>"
export TF_VAR_seguranca_seed_admin_senha="<senha-forte>"
export TF_VAR_seguranca_seed_admin_cpf="<cpf-valido>"
export TF_VAR_newrelic_license_key="<license-key-da-conta-new-relic>"
export TF_VAR_mercadopago_access_token="<access-token-do-mercado-pago>"
export TF_VAR_mercadopago_webhook_secret="<chave-secreta-do-webhook-mercado-pago>"

terraform init
terraform plan    # revisar o que sera criado/alterado antes de aplicar
terraform apply
```

O usuario do RabbitMQ (`rabbitmq_username`, padrao `oficina`) tem default e a
senha e gerada por `random_password` (`messaging_keyvault.tf`), entao nenhuma
das duas entra por `TF_VAR_*`. `billing_github_repo_id`/`execucao_github_repo_id`
tem como default os ids dos repositorios criados em 2026-11-09 (ver
[Depois de criar os repositorios Billing/Execucao no GitHub](#depois-de-criar-os-repositorios-billingexecucao-no-github)).

> **Ordem entre repositorios: `OficinaMecanica.Banco` ANTES deste.** As
> connection strings do Key Vault passam a usar os usuarios dedicados
> (`app_os`/`app_seguranca`/`app_billing`) que o Banco cria; aplicar este
> repo antes aponta o OS Service e o Seguranca pra logins que ainda nao
> existem. Detalhes em [Microsservicos](#microsservicos-billing-execucao-e-rabbitmq).
> As tres senhas `sql_app_*_password` sao as mesmas nos dois repos.
>
> **Cuidado com o CI:** o merge de um PR em `release`/`main` dispara
> `terraform apply -auto-approve` **automaticamente** (job `apply`). Mergear o
> PR do Infra **antes** de o Banco ter criado os usuarios dedicados troca as
> connection strings do Key Vault por logins que ainda nao existem e derruba o
> OS Service e o Seguranca - a ordem Banco -> Infra e obrigatoria tambem pro merge.

> **Nota sobre o backend remoto**: o state fica em uma Storage Account
> (`storage`, ver `backend.tf`) que e ela mesma criada pelo Terraform — na
> pratica isso significa que a primeira vez que o projeto foi provisionado
> precisou de um bootstrap (aplicar `module.storage` com state local antes
> de configurar o backend remoto). Como a storage account ja existe hoje,
> um `terraform init` normal e suficiente para quem for rodar a partir
> daqui.

O `terraform apply` cria todos os modulos na ordem correta de dependencias
(o proprio Terraform monta esse grafo a partir das referencias entre
`module.*`, sem flags especiais fora do bootstrap do cluster em ambiente novo,
descrito nos pre-requisitos) — do Resource Group ate o
cluster AKS, Key Vault e a federacao OIDC do GitHub Actions. Para aplicar so
uma parte especifica durante o desenvolvimento (ex: iterar num modulo sem
tocar nos demais), use `terraform apply -target="module.<nome>"`.

Os passos acima sao pra rodar manualmente/localmente. O CI/CD
([.github/workflows/ci.yml](.github/workflows/ci.yml)) ja automatiza isso:
`terraform plan` roda em todo PR contra `main`/`release`, e `terraform
apply` roda automaticamente em todo push (ou disparo manual) nessas
branches, autenticando via GitHub OIDC (`github_oidc_infra`).

Depois do apply, alguns outputs sao necessarios pra configurar os
repositorios de aplicacao (`.env` da API, variaveis do GitHub Actions):

```bash
terraform output                          # lista todos os outputs
terraform output -raw apim_gateway_url    # ex: valor especifico, sem aspas
```

Variaveis sensiveis mantidas fora do controle de versao (`terraform.tfvars`,
ignorado pelo Git).

> **Nota sobre o Azure SQL Database**: o tier sempre-gratis (`use-free-limit`)
> so pode ser definido no momento da criacao do banco, via Azure CLI — o
> provider Terraform (`azurerm`) ainda nao expoe esse campo. Por isso o
> banco foi criado com `az sql db create --use-free-limit true` e em
> seguida importado para o state do Terraform (`terraform import`), para
> que continue gerenciado como o restante da infraestrutura. Esse tier so
> vale 1x por assinatura — bancos adicionais (ex: `SegurancaDb`, ja criado
> pra o `OficinaMecanica.Seguranca`) tem custo serverless pequeno, nao
> "sempre gratis".

> **Observabilidade: New Relic, via OpenTelemetry** — este projeto ja teve
> um stack self-hosted completo aqui (`kube-prometheus-stack` + Loki/Alloy +
> Jaeger), removido em favor do New Relic (SaaS, escolha livre de
> ferramenta pro projeto). Dois componentes rodam no cluster (`helm/`):
>
> | Componente | Chart | Finalidade |
> |------------|-------|------------|
> | OpenTelemetry Collector | `open-telemetry/opentelemetry-collector` (`otel-collector.tf`) | Recebe traces/metricas/logs via OTLP da API (repositorio `OficinaMecanica`) e reexporta pra New Relic — gateway "burro" de proposito: trocar de backend de observabilidade no futuro so exige mudar a config do exporter aqui, sem tocar em codigo de aplicacao nem reinstalar agente nenhum |
> | nri-bundle | `helm-charts.newrelic.com` (`newrelic.tf`) | Integracao de Kubernetes da New Relic — CPU/memoria de pods/nodes, com seu proprio `kube-state-metrics` (sem concorrente no cluster desde que o antigo foi removido) |
>
> A license key da New Relic (`azurerm_key_vault_secret.newrelic_license_key`,
> raiz) e sincronizada num `kubernetes_secret` proprio (nao via CSI Secrets
> Store — o Terraform ja tem o valor em maos, sem necessidade de ida-e-volta
> pelo Key Vault so pra esses dois consumidores dentro do proprio cluster),
> referenciado pelo Collector (env var `NEW_RELIC_LICENSE_KEY`) e pelo
> nri-bundle (`global.customSecretName`/`customSecretLicenseKey`). Dashboards
> e alertas sao montados via ferramentas do MCP `newrelic` (`.mcp.json` na
> raiz do workspace, `E:\FIAP\Pos`) ou `newrelic nerdgraph query` (CLI) — nao
> Terraform, nao UI manual.

## API Gateway

Este repositorio e so Terraform — nao expoe nenhuma API HTTP propria, so
provisiona o gateway que fica na frente das APIs dos outros repositorios
(links de Swagger abaixo).

O [Azure API Management](https://azure.microsoft.com/products/api-management)
(`apim`, tier **Consumption** — sempre gratis ate 1M chamadas/mes) fica
**na frente** do `ingress-nginx`, nao o substitui: o `ingress-nginx` continua
servindo Mailpit diretamente e vira so o *backend* que a APIM chama pra
rotear. Do ponto de vista de quem consome a API, o gateway da APIM passa a
ser o novo endereco publico:

```bash
terraform output -raw apim_gateway_url   # https://<nome>.azure-api.net
```

| Rota publica (`https://<nome>.azure-api.net/...`) | API na APIM | Backend (entidade nomeada) | URL do backend | Servico | Bloqueado na borda (404) |
|---------------------------------------------------|-------------|----------------------------|----------------|---------|--------------------------|
| `/oficinaserver/...` | `oficinamecanica-api` | `ingress-nginx` | `http://<ip-ingress>` (catch-all `/` do OS Service) | `OficinaMecanica` (OS Service; Swagger UI em `/oficinaserver/index.html`) | `/health/ready`, `/metrics`, **so com `bloquear_endpoints_internos_no_oficinaserver = true`** (default `false`, ver abaixo) |
| `/segurancaserver/...` | `seguranca-api` | `seguranca` | `https://<nome>.azurewebsites.net` (direto na Function, sem `ingress-nginx`/AKS) | `OficinaMecanica.Seguranca` (emissao de JWT RS256 e JWKS) | nenhum (so expoe `/health`) |
| `/billingserver/...` | `billing-api` | `billing` | `http://<ip-ingress>/billing` (**prefixo de path**) | `OficinaMecanica.Billing`; o webhook do Mercado Pago entra **anonimo** em `/billingserver/webhooks/mercadopago` (`terraform output mercadopago_webhook_url`) | `/health/ready`, `/metrics` |
| `/execucaoserver/...` | `execucao-api` | `execucao` | `http://<ip-ingress>/execucao` (**prefixo de path**) | `OficinaMecanica.Execucao` | `/health/ready`, `/metrics` |

Todas com `subscription_required = false` (cada servico valida o proprio JWT;
o webhook e autenticado pela assinatura HMAC `x-signature`, validada pelo
Billing) e associadas ao Product `gateway`. Billing e Execucao saem de um
`for_each` sobre `local.ingress_services` em `apim/main.tf`: um servico novo
atras do `ingress-nginx` e uma entrada nesse mapa. O Ingress de cada um (no
repositorio do servico) casa o prefixo (`/billing(/|$)(.*)`,
`/execucao(/|$)(.*)`) e o remove com `rewrite-target`.

(O New Relic, usado pra observabilidade, e um SaaS externo — acessado direto, sem passar pela APIM.)

Cada backend novo entra com o mesmo padrao de path (`<nome>server`) — mesma
convencao ja usada por `oficinaserver`/`segurancaserver`.

Modelo **wildcard/passthrough**, nao import de OpenAPI: cada API e criada
"em branco" na APIM, com uma operacao coringa (`url_template = "/*"`) por
metodo HTTP real (`GET`/`POST`/`PUT`/`DELETE`/`PATCH`), repassando qualquer
path para o backend — inclusive o que nenhum OpenAPI documentaria (a propria
Swagger UI, `/health`) — **exceto** `/health/ready` e `/metrics` nas APIs de
negocio, bloqueados com 404 (ver [Bloqueio de `/health/ready` e `/metrics`](#bloqueio-de-healthready-e-metrics-na-borda);
no `oficinaserver` o bloqueio depende de uma variavel, desligada por padrao).

> **Por que nao `method = "*"`?** A APIM nao tem um metodo HTTP curinga de
> verdade — o provider Terraform aceita `method = "*"` sem erro, mas o
> runtime da Azure nunca casa nenhuma request contra ele (404 silencioso
> sempre). `apim/main.tf` usa `for_each` sobre os metodos reais em vez
> disso.

O tier Consumption funciona aqui sem VNet porque so precisa alcancar
backends publicos pela internet (nao suporta VNet integration) — exatamente
o que o LoadBalancer publico do `ingress-nginx` ja fornece.

### Bloqueio de `/health/ready` e `/metrics` na borda

`/health/ready` (abre conexao com banco e broker) e `/metrics` sao anonimos nos
servicos, e o wildcard os repassaria a internet. A policy de cada API de negocio
(`billingserver`, `execucaoserver` e, ligada a variavel abaixo, `oficinaserver`) tem, logo depois do
`<base />` da secao `inbound` e antes do `set-backend-service`, um guard que
responde **404 sem corpo** quando o **final** do path e `/health/ready` ou
`/metrics`: sem distinguir maiusculas, com ou sem barra final, com query string,
decodificando `%XX` e tolerando `//` e `/.` (um segmento `..` tambem responde
404). Testar o final do path vale com ou sem o prefixo da API
(`/billingserver/...`) e independe da premissa de concatenacao do path do
backend, ainda pendente.

- Arquivo: `apim/bloqueio-health-ready-e-metrics.xml`, lido com `file()` em
  `apim/main.tf` (`local.bloqueio_endpoints_internos`) e incluido na policy do
  `for_each` `ingress_services` (Billing e Execucao, sempre; servico novo no mapa
  herda o guard) e na do `oficinamecanica` (so com a variavel ligada). `/health`
  (liveness, sem dependencias) **continua exposto**; o `segurancaserver` fica sem
  o guard porque so tem `/health`.
- **Rollout em duas etapas**: `bloquear_endpoints_internos_no_oficinaserver`
  (`variables.tf`, `default = false`). Uma policy expression so e validada em
  execucao e um erro nela derrubaria a API do OS Service em producao (o merge
  aplica `-auto-approve`). O primeiro apply so mexe nas APIs novas (com `false` a
  policy do `oficinaserver` fica identica a de antes); depois de conferir o
  bloqueio nelas (lista no [ADR 0007](docs/adr/0007-bloqueio-de-health-ready-e-metrics-na-apim.md)),
  o dono troca o `default` para `true` **via PR** (o CI nao le `.tfvars`) e
  aplica de novo. Nao precisa de secret do CI: e so um default no `.tf`.
- As probes do Kubernetes batem direto no pod e nao passam pela APIM. Quem acessa o
  IP do `ingress-nginx` direto ainda alcanca os dois endpoints (limitacao aceita,
  ver [ADR 0007](docs/adr/0007-bloqueio-de-health-ready-e-metrics-na-apim.md)).
- Testes locais (sem Azure): `python -I docs/apim/testar_bloqueio_health_ready_e_metrics.py`
  (a condicao; o CI o roda no job `validate`) e `apim/tests/bloqueio.tftest.hcl`
  (`terraform test` com providers simulados: variavel ligada/desligada; como rodar,
  no cabecalho do arquivo).
- Depois do primeiro apply, conferir `/billingserver/health/ready` e
  `/execucaoserver/metrics` (404), `/billingserver/health` (200) e rotas normais e o
  webhook do Mercado Pago (inalterados); so entao ligar o `oficinaserver` e conferir
  `/oficinaserver/health/ready` (404) e as rotas do OS (inalteradas). Lista completa no ADR 0007.

### Headers `X-Forwarded-*`

Pra Swagger UI e "Try it out" funcionarem corretamente atras do prefixo da
APIM, a policy da API injeta `X-Forwarded-Proto`/`-Host`/`-Prefix` antes de
encaminhar. Dois pontos sao necessarios pra esses headers chegarem intactos
ate o pod:

1. **`ingress-nginx` com `controller.config.use-forwarded-headers: true`**
   (`helm/main.tf`) — o default do chart e `false`, que faz o nginx
   **descartar** os headers recebidos e preencher com o que ele mesmo
   enxerga.
2. **`Program.cs`** (repositorio `OficinaMecanica`) registra
   `app.UseForwardedHeaders(...)` + um middleware proprio lendo
   `X-Forwarded-Prefix` na mao pra setar `HttpRequest.PathBase`.

Billing e Execucao recebem os mesmos tres headers, com o prefixo do gateway
(`/billingserver`, `/execucaoserver`) - o prefixo do Ingress (`/billing`,
`/execucao`) e removido pelo `rewrite-target` e nao aparece neles. A policy do
Seguranca e a unica diferente: injeta `X-Gateway-Proto`/`-Host`/`-Prefix`
(nomes proprios, **nao** `X-Forwarded-*`) porque o App Service descarta
silenciosamente qualquer header `X-Forwarded-*` enviado pelo cliente antes de
ele chegar ao worker.

## Microsservicos (Billing, Execucao) e RabbitMQ

Visao dos servicos e do roteamento em
[Ecossistema de microsservicos](#ecossistema-de-microsservicos). A Saga
(orquestrada pelo OS Service) troca comandos e eventos entre OS Service,
Billing e Execucao via MassTransit sobre RabbitMQ. A parte de infraestrutura
que mora aqui:

| Recurso | Onde | Resumo |
|---------|------|--------|
| RabbitMQ | `helm/rabbitmq.tf` | StatefulSet de 1 replica, imagem oficial `rabbitmq:4.4.0-management`, PVC 2Gi, namespace `messaging`, endereco interno `rabbitmq.messaging.svc.cluster.local:5672` (`terraform output rabbitmq_host`). Sem Ingress: management so por `kubectl -n messaging port-forward svc/rabbitmq 15672:15672` ([ADR 0004](docs/adr/0004-rabbitmq-no-aks-statefulset-com-imagem-oficial.md)); detalhes abaixo |
| Credenciais do RabbitMQ | `messaging_keyvault.tf` | usuario `oficina` + `random_password`, guardados no Key Vault (`rabbitmq-username`/`rabbitmq-password`) e no Secret nativo `rabbitmq-credentials` do namespace `messaging` |
| Identidades OIDC | `github_oidc_aks_app/` | uma por servico (Billing, Execucao), so push em `main`/`release`, sem `pull_request`; criadas so quando o ID do repo e informado ([ADR 0006](docs/adr/0006-modulo-oidc-parametrizado-por-servico-e-criacao-condicional.md)) |
| Segredos | `keyvault_secrets.tf`, `seguranca_keyvault.tf`, `billing_keyvault.tf`, `messaging_keyvault.tf` | ver tabela abaixo |
| Rotas APIM | `apim/main.tf` | `billingserver` e `execucaoserver` (wildcard, backends por prefixo de path; ver [API Gateway](#api-gateway)) |

### RabbitMQ no AKS

Escrito na mao em Terraform (nao via chart Helm: o catalogo Bitnami virou pago
e o operador oficial e pesado demais para o no unico), dentro do modulo `helm`:

- `kubernetes_stateful_set_v1.rabbitmq`: 1 replica (broker unico, sem
  quorum/cluster), imagem **oficial** do Docker Hub
  `rabbitmq:${rabbitmq_image_tag}` (padrao `4.4.0-management`, tag exata
  fixada de proposito em `helm/variables.tf`; a mesma versao dos composes, do
  Testcontainers e do e2e dos servicos, ver [ADR 0004](docs/adr/0004-rabbitmq-no-aks-statefulset-com-imagem-oficial.md)).
- Namespace proprio `messaging` (`messaging_namespace`), separado das
  aplicacoes (`default`) e da observabilidade (`monitoring`).
- Persistencia: PVC 2Gi (`rabbitmq_storage_size`) na StorageClass `managed-csi`
  (Azure Disk), com `Retain` ao apagar/escalar o StatefulSet.
- Recursos: requests 100m/256Mi, limits 500m/512Mi (o no unico nao tem folga).
- Pod nao-root (uid/gid 999), sem escalada de privilegio, `capabilities drop
  ALL`, seccomp `RuntimeDefault`, `automountServiceAccountToken = false`.
- ConfigMap `rabbitmq-config` (`30-oficina.conf` + `enabled_plugins` com
  `rabbitmq_management` e `rabbitmq_prometheus`) montado por `subPath`; a
  annotation `checksum/config` recria o pod quando a configuracao muda.
- Credenciais: `random_password.rabbitmq` (32 caracteres alfanumericos, na raiz)
  vai para o Secret nativo `rabbitmq-credentials` (consumido pelo StatefulSet
  via `secretKeyRef`) e para o Key Vault (`rabbitmq-username`/`rabbitmq-password`),
  de onde os servicos leem via CSI Secrets Store.
- Services: `rabbitmq` (`ClusterIP`: 5672 AMQP, 15672 management, 15692
  metricas Prometheus) e `rabbitmq-headless` (so a "governing service" do
  StatefulSet). Sem Ingress nem LoadBalancer. Outputs: `rabbitmq_namespace`,
  `rabbitmq_host`, `rabbitmq_amqp_port`.

Limitacoes assumidas (detalhadas no ADR 0004): ponto unico de falha (1 no, sem
alta disponibilidade); `RABBITMQ_DEFAULT_USER/PASS` so valem no primeiro boot,
entao rotacionar a senha exige `rabbitmqctl change_password` alem do
`terraform apply -replace=random_password.rabbitmq`; um unico usuario
compartilhado pelos tres servicos (sem vhost por servico); o cluster nao tem
motor de NetworkPolicy (`network_profile` do AKS sem `network_policy`), entao
so a credencial protege o broker, e o AMQP trafega sem TLS pelo ClusterIP
interno; metricas Prometheus habilitadas, mas ainda nao coletadas pelo
OpenTelemetry Collector.

### Segredos no Key Vault (`kvfiap`)

| Item | Tipo | Criado por | Consumidor |
|------|------|------------|------------|
| `sql-connection-string` (usuario `app_os`) | secret | este repo (`keyvault_secrets.tf`) | OS Service (`OficinaMecanica`) |
| `newrelic-license-key` | secret | este repo (`keyvault_secrets.tf`) | so registro auditavel: o Collector e o `nri-bundle` leem o `kubernetes_secret` que o Terraform cria no namespace `monitoring` |
| `seguranca-sql-connection-string` (usuario `app_seguranca`) | secret | este repo (`seguranca_keyvault.tf`) | `OficinaMecanica.Seguranca` (Key Vault Reference na Function App) |
| `seguranca-seed-admin-senha` | secret | este repo (`seguranca_keyvault.tf`) | `OficinaMecanica.Seguranca` (Key Vault Reference) |
| `seguranca-newrelic-otlp-headers` | secret (`api-key=<license key>`) | este repo (`seguranca_keyvault.tf`) | `OficinaMecanica.Seguranca` (Key Vault Reference em `Otel__Headers`, telemetria OTLP direto para o New Relic) |
| `seguranca-rs256` | **chave** RSA-2048 (`sign`/`verify`) | este repo (`seguranca_keyvault.tf`) | `OficinaMecanica.Seguranca` (`Key Vault Crypto User`, so nessa chave; a chave privada nunca sai do vault) |
| `billing-sql-connection-string` (usuario `app_billing`) | secret | este repo (`billing_keyvault.tf`) | `OficinaMecanica.Billing` |
| `mercadopago-access-token`, `mercadopago-webhook-secret` | secret | este repo (`billing_keyvault.tf`; valor via `TF_VAR_*`) | `OficinaMecanica.Billing` |
| `rabbitmq-username`, `rabbitmq-password` | secret | este repo (`messaging_keyvault.tf`) | OS Service, Billing e Execucao |
| `execucao-mongo-connection-string` | secret | **`OficinaMecanica.Banco`**, root `atlas/` aplicado localmente (o host do Atlas so existe apos criar o cluster; este repo nao cria o secret nem concede role nele) | `OficinaMecanica.Execucao` |

### Acesso ao Key Vault por identidade

O cofre usa RBAC puro (sem restricao de rede). Isolamento por servico e
**parcial**: as identidades pre-existentes e a do addon CSI mantem leitura no
vault inteiro (ver [ADR 0005](docs/adr/0005-usuario-sql-dedicado-por-banco-e-secrets-por-servico.md)).

| Identidade | Role | Escopo |
|------------|------|--------|
| Administrador humano (`admin_object_id`) e `github_oidc_infra` | `Key Vault Administrator` | vault |
| Addon CSI do AKS (pods dos tres servicos de negocio, `aks_keyvault_access.tf`) | `Key Vault Secrets User` | vault (cada servico monta so os seus secrets via `SecretProviderClass`, mas o RBAC nao impede mais que isso) |
| Function App do Seguranca (managed identity) | `Key Vault Crypto User` / `Key Vault Secrets User` | so a chave `seguranca-rs256` / vault |
| `github_oidc` (OS Service) e `github_oidc_seguranca` | `Key Vault Secrets User` | vault (step de migration) |
| `github_oidc_billing` | `Key Vault Secrets User` | **so** `billing-sql-connection-string` (step de migration) |
| `github_oidc_execucao` | **nenhuma** | menor privilegio: o pipeline da Execucao nao tem migration (os indices do MongoDB sao criados pela propria aplicacao na subida) e a connection string do Atlas chega ao pod pelo CSI, com a identidade do addon, nao com a do pipeline |
| `github_oidc_banco` | **nenhuma** | o CI do Banco nao grava secret (o Atlas e aplicado so localmente); a identidade tem credencial de `pull_request`, entao nao deve alcancar nenhum secret |

### Ordem de aplicacao: Banco -> Infra

O merge de um PR em `release`/`main` dispara `terraform apply -auto-approve` automaticamente (job `apply` do CI). Mergear o PR do Infra ANTES de o Banco ter criado os usuarios dedicados troca as connection strings do Key Vault por logins que ainda nao existem e derruba o OS Service e o Seguranca - a ordem Banco -> Infra vale tambem pro merge.

1. **`OficinaMecanica.Banco`, LOCALMENTE na primeira vez**, com o admin humano
   (que tem `Key Vault Administrator`): o `terraform apply` do root principal
   cria `BillingDb`. Em seguida (ainda local, recomendado) roda
   `sql/criar-usuarios.sql` nos tres bancos para criar os usuarios dedicados
   `app_os`, `app_seguranca` e `app_billing` - o Terraform nao cria usuario
   contido; a alternativa e esperar o primeiro apply do CI do Banco que termine
   com sucesso. O MongoDB Atlas e outro root do Banco, `atlas/`, aplicado so
   localmente (o CI nao alcanca o Atlas, ver o ADR 0004 do Banco): cria o
   projeto, o cluster M0, o usuario e a access list e grava
   `execucao-mongo-connection-string` no Key Vault. Pre-requisitos dele (conta,
   organizacao, API key de organizacao, `atlas_org_id`, IP de saida do AKS em
   `aks_egress_ip`): [README do Banco](../OficinaMecanica.Banco/README.md).
2. **Este repositorio** (merge do PR, que aplica pelo CI, ou apply local):
   monta as connection strings com os usuarios que ja existem, cria o
   RabbitMQ e as rotas da APIM. As identidades OIDC de Billing/Execucao so
   sao criadas se os respectivos IDs de repositorio estiverem preenchidos (hoje
   o default das variaveis ja e o ID de cada repositorio).
3. Reiniciar quem consome connection string antiga: `kubectl rollout restart`
   do OS Service (le o secret via `secretKeyRef`, so no start) e reinicio da
   Function App do Seguranca.
4. Dai em diante o CI do Banco consegue atualizar o secret, e as proximas
   aplicacoes do Banco podem ir pelo CI.

Se o ARM recusar o escopo de secret (inexistente ou criado por outro repo), o
apply deste repo falha nessa role **sem destruir nada**: reordenar (Banco local
primeiro) e reaplicar. A role fica escopada num unico secret, e nao no vault,
porque a identidade do Banco tem credencial de `pull_request`.

### Segredos do CI (GitHub Secrets deste repositorio)

Os dois jobs (`validate` e `apply`) leem estes secrets (Settings > Secrets
and variables > Actions) e **precisam existir antes do PR/merge**, senao o
`plan`/`apply` falha na validacao das variaveis:

| GitHub Secret | Variavel Terraform | Sensivel |
|---------------|--------------------|----------|
| `TF_VAR_SQL_APP_OS_PASSWORD` | `sql_app_os_password` | sim |
| `TF_VAR_SQL_APP_SEGURANCA_PASSWORD` | `sql_app_seguranca_password` | sim |
| `TF_VAR_SQL_APP_BILLING_PASSWORD` | `sql_app_billing_password` | sim |
| `TF_VAR_MERCADOPAGO_ACCESS_TOKEN` | `mercadopago_access_token` | sim |
| `TF_VAR_MERCADOPAGO_WEBHOOK_SECRET` | `mercadopago_webhook_secret` | sim |

(Ja existentes: `TF_VAR_APIM_PUBLISHER_EMAIL`, `TF_VAR_SEGURANCA_SEED_ADMIN_SENHA`,
`TF_VAR_SEGURANCA_SEED_ADMIN_CPF`, `TF_VAR_NEWRELIC_LICENSE_KEY`. O secret
`TF_VAR_SQL_ADMINISTRATOR_LOGIN_PASSWORD` deixou de ser usado - as variaveis
do administrador do SQL Server foram removidas deste repo - e pode ser
apagado; um `sql_administrator_login` esquecido num `terraform.tfvars` local
gera so um aviso de variavel nao declarada.)

Os mesmos jobs autenticam por OIDC (identidade `github_oidc_infra`, sem client
secret) e leem tres **variaveis** (nao secrets) do repositorio:
`AZURE_CLIENT_ID` (`terraform output infra_client_id`), `AZURE_TENANT_ID`
(`azure_tenant_id`) e `AZURE_SUBSCRIPTION_ID` (`azure_subscription_id`).

### Depois de criar os repositorios Billing/Execucao no GitHub

As identidades OIDC so sao criadas quando o ID numerico do repositorio e
informado. Os ids dos repositorios criados em 2026-11-09 (Billing `1451863424`,
Execucao `1451865555`) ja estao como `default` em `billing_github_repo_id`/
`execucao_github_repo_id`; `null` desliga a criacao e mantem `validate`/`plan`
verdes num ambiente sem esses repos. Para recriar um repositorio (o id muda):

```bash
gh api repos/willianrmattos/OficinaMecanica.Billing --jq .id    # -> billing_github_repo_id
gh api repos/willianrmattos/OficinaMecanica.Execucao --jq .id   # -> execucao_github_repo_id
```

Gravar o valor no `default` da variavel em `variables.tf` (via PR - **nao so
num `.tfvars` local**: o CI nao le `.tfvars` e um `plan` sem o ID propoe
destruir a identidade), aplicar e configurar no repositorio do servico a
variavel `AZURE_CLIENT_ID` com `terraform output billing_github_actions_client_id`
(ou `execucao_github_actions_client_id`), alem de `AZURE_TENANT_ID` e
`AZURE_SUBSCRIPTION_ID`. A identidade da Execucao nao depende de nenhum secret
do Key Vault (nao tem role la, ver [Acesso ao Key Vault por identidade](#acesso-ao-key-vault-por-identidade));
a da Billing recebe `Key Vault Secrets User` em `billing-sql-connection-string`,
secret que este mesmo apply cria.

### Contrato com os repositorios dos servicos

- Cada servico traz seu proprio Ingress com **prefixo de path** e rewrite
  (o OS Service segue catch-all em `/`): `/billing(/|$)(.*)` e `/execucao(/|$)(.*)`
  com `nginx.ingress.kubernetes.io/use-regex: "true"` e
  `rewrite-target: /$2`, pra o pod receber o path sem o prefixo.
- Billing e Execucao rodam no namespace `default` (como o OS Service: o no unico
  nao tem CPU para mais um namespace de aplicacao), cada um com seu Deployment,
  Service e Ingress no `k8s/` do proprio repositorio.
- Cada servico le so os seus secrets via `SecretProviderClass` (CSI Secrets
  Store, `keyvaultName: kvfiap`), mesmo padrao do OS Service, com a identidade do
  addon (`terraform output key_vault_secrets_provider_client_id`). A Execucao
  le `execucao-mongo-connection-string` (gravado pelo root `atlas/` do Banco) e `rabbitmq-*`.
- Os pods usam o RabbitMQ em `rabbitmq.messaging.svc.cluster.local:5672` com
  `rabbitmq-username`/`rabbitmq-password` do Key Vault.
- O pipeline de cada servico (OIDC) so faz build/push no ACR, migration (Billing)
  e deploy no AKS; configurar no repo do servico as variaveis `AZURE_CLIENT_ID`,
  `AZURE_TENANT_ID` e `AZURE_SUBSCRIPTION_ID`.

### Confirmado e pendente no ambiente real (2026-11-10)

- **Concatenacao de path na APIM (confirmada em 2026-11-10)**: os backends
  `billing`/`execucao` tem URL com prefixo (`http://<ip-ingress>/billing`) e a
  premissa era que a APIM concatena o path do backend com o path da operacao
  (`/billingserver/health` -> `http://<ip>/billing/health`). Depois do apply,
  `/billingserver/health` e `/execucaoserver/health` respondem 200 pelo APIM, entao
  a premissa vale. A alternativa (backend so com o IP e `<rewrite-uri>` na policy,
  comentario em `apim/main.tf`) nao foi necessaria. A raiz `/billingserver/` e
  `/execucaoserver/` responde 500 do APIM (o servico em si redireciona para
  `index.html`); o Swagger UI abre em `/billingserver/index.html` e
  `/execucaoserver/index.html`.
- **Bloqueio de `/health/ready` e `/metrics` na APIM (implementado em duas
  etapas; em 2026-11-10 NAO esta bloqueando)**: chamando o APIM publicado,
  `/billingserver/health/ready`, `/billingserver/metrics`, `/execucaoserver/metrics`,
  `/oficinaserver/metrics` e `/segurancaserver/health/ready` respondem 200, inclusive em
  Billing e Execucao, onde o guard e ligado sempre. A causa nao foi investigada
  (conferir a policy publicada no APIM e o ultimo apply). O texto abaixo descreve o
  desenho e o roteiro de conferencia: as rotas `oficinaserver`/`billingserver`/`execucaoserver`
  sao wildcard e repassariam qualquer path a internet, inclusive esses dois endpoints
  anonimos dos servicos (o cache de 5 s do servico limita o custo de
  `/health/ready`, mas nao esconde o endpoint nem o `/metrics`). A policy
  (`apim/bloqueio-health-ready-e-metrics.xml`, ver [Bloqueio de `/health/ready` e
  `/metrics`](#bloqueio-de-healthready-e-metrics-na-borda) e
  [ADR 0007](docs/adr/0007-bloqueio-de-health-ready-e-metrics-na-apim.md)) entra no
  primeiro apply **so em Billing e Execucao**: o `oficinaserver` (OS Service, em
  producao) fica com `/health/ready` e `/metrics` expostos, como hoje, ate o dono
  ligar `bloquear_endpoints_internos_no_oficinaserver` (etapa 2), porque uma
  expressao de policy com erro so aparece em execucao e derrubaria a API inteira.
  Etapa 1: conferir 404 em `/billingserver/health/ready` e `/execucaoserver/metrics`,
  200 em `/billingserver/health` (confirma tambem a concatenacao de path acima) e
  rotas normais e webhook inalterados. Etapa 2 (ligar a variavel via PR): conferir 404
  em `/oficinaserver/health/ready` e as rotas do OS inalteradas. Nao cobre quem
  acessa o IP do ingress direto.
- **Atlas e CI do Banco (decidido)**: o CI do `OficinaMecanica.Banco` nao alcanca a API do
  MongoDB Atlas (o Atlas recusa `0.0.0.0/0` na access list de uma API key e o runner do
  GitHub tem IP variavel); o Atlas fica num root separado, aplicado so localmente
  (ADR 0004 do Banco); ver o [README do Banco](../OficinaMecanica.Banco/README.md).
- **Capacidade do no**: RabbitMQ pede 100m de CPU/256Mi de request num no
  unico (`Standard_D4as_v4`) sem folga; conferir `kubectl describe node`
  antes do apply (o StatefulSet espera o rollout e falha por tempo se o pod
  ficar `Pending`).
- **Quem aplica**: o `github_oidc_infra` tem `Contributor` no resource group,
  que nao inclui criar role assignments. Se o apply do CI falhar com
  `AuthorizationFailed` nas roles novas, aplicar localmente (Owner) ou
  conceder `Role Based Access Control Administrator` a essa identidade
  (decisao nao tomada aqui).
- Metricas Prometheus do RabbitMQ (porta 15692) estao habilitadas, mas o
  OpenTelemetry Collector ainda nao as coleta.

## Stack Tecnologica

| Categoria | Tecnologia | Versao |
|-----------|-----------|--------|
| IaC | Terraform (providers `azurerm`, `azuread`, `kubernetes`, `helm`, `random`) | >= 1.5 |
| Nuvem | Azure (AKS, ACR, Key Vault, API Management, Function App, Storage Account); Azure SQL Database e MongoDB Atlas sao do `OficinaMecanica.Banco` | — |
| Orquestracao | Kubernetes (AKS) + Helm (`ingress-nginx`, OpenTelemetry Collector, `nri-bundle`) | — |
| Mensageria | RabbitMQ 4.x (imagem oficial, StatefulSet, namespace `messaging`) | `4.4.0-management` |
| Gateway | Azure API Management (tier Consumption) na frente do `ingress-nginx` e da Function App | — |
| Observabilidade | New Relic (SaaS) via OpenTelemetry Collector, sem agente proprietario | — |
| CI/CD | GitHub Actions + OIDC (Federated Identity Credentials, sem client secret) | — |
