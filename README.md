# OficinaMecanica.Infra

Infraestrutura como codigo (Terraform) para o ecossistema OficinaMecanica —
provisiona todos os recursos Azure usados pelos repositorios de aplicacao
(`OficinaMecanica`, `OficinaMecanica.Seguranca`, `OficinaMecanica.Billing`,
`OficinaMecanica.Execucao` e futuros), num unico lugar centralizado.

Migrado do repositorio `OficinaMecanica` (onde vivia em `infra/`) — mesmo
backend de state remoto, nenhum recurso foi recriado no Azure durante a
migracao.

## Diagramas

| Documento | Arquivo |
|-----------|---------|
| Visao de Componentes (nuvem, APIs, banco, monitoramento) | [docs/diagramas/diagrama-de-componentes.jpg](docs/diagramas/diagrama-de-componentes.jpg) |

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
| `github_oidc_banco` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica.Banco` no Azure via OIDC (tambem `Key Vault Secrets Officer` escopado so no secret `execucao-mongo-connection-string`, que o Banco grava com o host do MongoDB Atlas) |
| `github_oidc_aks_app` | Azure AD App Registration + Federated Identity Credential | Modulo **parametrizado por servico** (AcrPush + AKS Cluster Admin + Key Vault Secrets User por secret), instanciado pra `OficinaMecanica.Billing` e `OficinaMecanica.Execucao` - so criado quando o ID do repo e informado (ver [Microsservicos](#microsservicos-billing-execucao-e-rabbitmq)) |
| `apim` | Azure API Management (Consumption) | Gateway de API na frente do `ingress-nginx` (monolito, Billing, Execucao) e da Function App (ver [API Gateway](#api-gateway) abaixo) |

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

Pre-requisitos: [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5, Azure CLI autenticado (`az login`) com permissao na assinatura.

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

> **Ordem entre repositorios: `OficinaMecanica.Banco` ANTES deste.** As
> connection strings do Key Vault passam a usar os usuarios dedicados
> (`app_os`/`app_seguranca`/`app_billing`) que o Banco cria; aplicar este
> repo antes aponta o monolito e o Seguranca pra logins que ainda nao
> existem. Detalhes em [Microsservicos](#microsservicos-billing-execucao-e-rabbitmq).
> As tres senhas `sql_app_*_password` sao as mesmas nos dois repos.
>
> **Cuidado com o CI:** o merge de um PR em `release`/`main` dispara
> `terraform apply -auto-approve` **automaticamente** (job `apply`). Mergear o
> PR do Infra **antes** de o Banco ter criado os usuarios dedicados troca as
> connection strings do Key Vault por logins que ainda nao existem e derruba o
> monolito e o Seguranca - a ordem Banco -> Infra e obrigatoria tambem pro merge.

> **Nota sobre o backend remoto**: o state fica em uma Storage Account
> (`storage`, ver `backend.tf`) que e ela mesma criada pelo Terraform — na
> pratica isso significa que a primeira vez que o projeto foi provisionado
> precisou de um bootstrap (aplicar `module.storage` com state local antes
> de configurar o backend remoto). Como a storage account ja existe hoje,
> um `terraform init` normal e suficiente para quem for rodar a partir
> daqui.

O `terraform apply` cria todos os modulos na ordem correta de dependencias
(o proprio Terraform monta esse grafo a partir das referencias entre
`module.*`, sem precisar de flags especiais) — do Resource Group ate o
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

- `https://<nome>.azure-api.net/oficinaserver/...` → API do repo `OficinaMecanica` (Swagger UI incluso, em `/oficinaserver/index.html`)
- `https://<nome>.azure-api.net/segurancaserver/...` → Function App do `OficinaMecanica.Seguranca` (emissao/JWKS de JWT RS256), backend diferente do acima: aponta direto pro hostname publico da Function (`<nome>.azurewebsites.net`), sem passar pelo `ingress-nginx`/AKS
- `https://<nome>.azure-api.net/billingserver/...` → `OficinaMecanica.Billing` (backend `http://<ip-ingress>/billing`); o webhook do Mercado Pago entra **anonimo** em `/billingserver/webhooks/mercadopago` (`terraform output mercadopago_webhook_url`)
- `https://<nome>.azure-api.net/execucaoserver/...` → `OficinaMecanica.Execucao` (backend `http://<ip-ingress>/execucao`)

(O New Relic, usado pra observabilidade, e um SaaS externo — acessado direto, sem passar pela APIM.)

Cada backend novo entra com o mesmo padrao de path (`<nome>server`) — mesma
convencao ja usada por `oficinaserver`/`segurancaserver`.

Modelo **wildcard/passthrough**, nao import de OpenAPI: cada API e criada
"em branco" na APIM, com uma operacao coringa (`url_template = "/*"`) por
metodo HTTP real (`GET`/`POST`/`PUT`/`DELETE`/`PATCH`), repassando qualquer
path para o backend — inclusive o que nenhum OpenAPI documentaria (a propria
Swagger UI, `/health`, `/metrics`).

> **Por que nao `method = "*"`?** A APIM nao tem um metodo HTTP curinga de
> verdade — o provider Terraform aceita `method = "*"` sem erro, mas o
> runtime da Azure nunca casa nenhuma request contra ele (404 silencioso
> sempre). `apim/main.tf` usa `for_each` sobre os metodos reais em vez
> disso.

O tier Consumption funciona aqui sem VNet porque so precisa alcancar
backends publicos pela internet (nao suporta VNet integration) — exatamente
o que o LoadBalancer publico do `ingress-nginx` ja fornece.

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

## Microsservicos (Billing, Execucao) e RabbitMQ

O monolito virou um conjunto de microsservicos (`OficinaMecanica` = OS Service,
`OficinaMecanica.Billing`, `OficinaMecanica.Execucao`, alem do
`OficinaMecanica.Seguranca` ja existente) coordenados por uma Saga sobre
RabbitMQ. A parte de infraestrutura que mora aqui:

| Recurso | Onde | Resumo |
|---------|------|--------|
| RabbitMQ | `helm/rabbitmq.tf` | StatefulSet de 1 replica, imagem oficial `rabbitmq:4.2.9-management`, PVC 2Gi, namespace `messaging`, endereco interno `rabbitmq.messaging.svc.cluster.local:5672` (`terraform output rabbitmq_host`). Sem Ingress: management so por `kubectl -n messaging port-forward svc/rabbitmq 15672:15672` ([ADR 0004](docs/adr/0004-rabbitmq-no-aks-statefulset-com-imagem-oficial.md)) |
| Credenciais do RabbitMQ | `messaging_keyvault.tf` | usuario `oficina` + `random_password`, guardados no Key Vault (`rabbitmq-username`/`rabbitmq-password`) e no Secret nativo do namespace `messaging` |
| Identidades OIDC | `github_oidc_aks_app/` | uma por servico (Billing, Execucao), so push em `main`/`release`, sem `pull_request` ([ADR 0006](docs/adr/0006-modulo-oidc-parametrizado-por-servico-e-criacao-condicional.md)) |
| Segredos | `keyvault_secrets.tf`, `seguranca_keyvault.tf`, `billing_keyvault.tf`, `messaging_keyvault.tf` | ver tabela abaixo |
| Rotas APIM | `apim/main.tf` | `billingserver` e `execucaoserver` (wildcard, mesmo padrao do `oficinaserver`) |

Segredos no Key Vault (`kvfiap`) e quem deve le-los:

| Secret | Criado por | Consumidor |
|--------|------------|------------|
| `sql-connection-string` (usuario `app_os`) | este repo | OS Service (`OficinaMecanica`) |
| `seguranca-sql-connection-string` (usuario `app_seguranca`) | este repo | `OficinaMecanica.Seguranca` |
| `billing-sql-connection-string` (usuario `app_billing`) | este repo | `OficinaMecanica.Billing` |
| `mercadopago-access-token`, `mercadopago-webhook-secret` | este repo (valor via `TF_VAR_*`) | `OficinaMecanica.Billing` |
| `rabbitmq-username`, `rabbitmq-password` | este repo | os tres servicos |
| `execucao-mongo-connection-string` | **`OficinaMecanica.Banco`** (o host do Atlas so existe apos criar o cluster; este repo so da ao `github_oidc_banco` o `Key Vault Secrets Officer` escopado nesse secret) | `OficinaMecanica.Execucao` |

### Ordem de aplicacao: Banco -> Infra

O merge de um PR em `release`/`main` dispara `terraform apply -auto-approve` automaticamente (job `apply` do CI). Mergear o PR do Infra ANTES de o Banco ter criado os usuarios dedicados troca as connection strings do Key Vault por logins que ainda nao existem e derruba o monolito e o Seguranca - a ordem Banco -> Infra vale tambem pro merge.

1. **`OficinaMecanica.Banco`, LOCALMENTE na primeira vez**, com o admin humano
   (que tem `Key Vault Administrator`): cria `BillingDb`, os usuarios SQL
   dedicados (`app_os`, `app_seguranca`, `app_billing`) e o cluster MongoDB
   Atlas, e grava `execucao-mongo-connection-string` no Key Vault. O CI do
   Banco ainda nao tem permissao nesse secret.
2. **Este repositorio** (merge do PR, que aplica pelo CI, ou apply local):
   monta as connection strings com os usuarios que ja existem, cria o
   RabbitMQ, as rotas da APIM, (se os IDs estiverem preenchidos) as
   identidades OIDC e a role `Key Vault Secrets Officer` do `github_oidc_banco`,
   escopada **so** no secret `execucao-mongo-connection-string` - escopo que
   so pode ser criado com o secret ja existente (passo 1).
3. Reiniciar quem consome connection string antiga: `kubectl rollout restart`
   do monolito (le o secret via `secretKeyRef`, so no start) e reinicio da
   Function App do Seguranca.
4. Dai em diante o CI do Banco consegue atualizar o secret, e as proximas
   aplicacoes do Banco podem ir pelo CI.

Se o ARM recusar o escopo de secret (inexistente ou criado por outro repo), o
apply deste repo falha nessa role **sem destruir nada**: reordene (Banco local
primeiro) e reaplique. A role fica escopada num unico secret, e nao no vault,
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

### Depois de criar os repositorios Billing/Execucao no GitHub

As identidades OIDC so sao criadas quando o ID numerico do repositorio e
informado (`default = null` em `billing_github_repo_id`/`execucao_github_repo_id`
mantem `validate`/`plan` verdes enquanto os repos nao existem):

```bash
gh api repos/willianrmattos/OficinaMecanica.Billing --jq .id    # -> billing_github_repo_id
gh api repos/willianrmattos/OficinaMecanica.Execucao --jq .id   # -> execucao_github_repo_id
```

Gravar o valor no `default` da variavel em `variables.tf` (via PR - **nao so
num `.tfvars` local**: o CI nao le `.tfvars` e um `plan` sem o ID propoe
destruir a identidade), aplicar e configurar no repositorio do servico a
variavel `AZURE_CLIENT_ID` com `terraform output billing_github_actions_client_id`
(ou `execucao_github_actions_client_id`), alem de `AZURE_TENANT_ID` e
`AZURE_SUBSCRIPTION_ID`. Para a Execucao, o secret `execucao-mongo-connection-string`
precisa ja existir (criado pelo Banco) quando o modulo for criado.

### Contrato com os repositorios dos servicos

- Cada servico traz seu proprio Ingress com **prefixo de path** e rewrite
  (monolito segue catch-all em `/`): `/billing(/|$)(.*)` e `/execucao(/|$)(.*)`
  com `nginx.ingress.kubernetes.io/use-regex: "true"` e
  `rewrite-target: /$2`, pra o pod receber o path sem o prefixo.
- Cada servico le so os seus secrets via `SecretProviderClass` (CSI Secrets
  Store, `keyvaultName: kvfiap`), mesmo padrao do monolito.
- Os pods usam o RabbitMQ em `rabbitmq.messaging.svc.cluster.local:5672` com
  `rabbitmq-username`/`rabbitmq-password` do Key Vault.

### Pendente de confirmacao no ambiente real

- **Concatenacao de path na APIM**: os backends `billing`/`execucao` tem URL
  com prefixo (`http://<ip-ingress>/billing`). A premissa e que a APIM
  concatena o path do backend com o path da operacao
  (`/billingserver/health` -> `http://<ip>/billing/health`). Nao da pra provar
  sem `apply`. Se nao concatenar, a request chegaria sem prefixo e cairia no
  catch-all do monolito; a alternativa e manter o backend so com o IP e
  reescrever na policy com `<rewrite-uri template="@("/billing" +
  context.Request.Url.Path.Substring(context.Api.Path.Length + 1))" />`
  (comentario em `apim/main.tf`).
- **Escopo de secret criado por outro repo**: as roles do `github_oidc_banco`
  (Secrets Officer) e do `github_oidc_execucao` (Secrets User) usam o escopo
  `<vault>/secrets/execucao-mongo-connection-string`, que depende de o secret
  existir; se o ARM recusar, ver o bootstrap acima.
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
| Nuvem | Azure (AKS, ACR, Key Vault, Azure SQL Database, API Management, Function App, Storage Account) | — |
| Orquestracao | Kubernetes (AKS) + Helm (`ingress-nginx`, OpenTelemetry Collector, `nri-bundle`) | — |
| Mensageria | RabbitMQ 4.x (imagem oficial, StatefulSet, namespace `messaging`) | `4.2.9-management` |
| Gateway | Azure API Management (tier Consumption) na frente do `ingress-nginx` e da Function App | — |
| Observabilidade | New Relic (SaaS) via OpenTelemetry Collector, sem agente proprietario | — |
| CI/CD | GitHub Actions + OIDC (Federated Identity Credentials, sem client secret) | — |
