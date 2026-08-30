# OficinaMecanica.Infra

Infraestrutura como codigo (Terraform) para o ecossistema OficinaMecanica —
provisiona todos os recursos Azure usados pelos repositorios de aplicacao
(`OficinaMecanica`, `OficinaMecanica.Seguranca` e futuros), num unico lugar
centralizado.

Migrado do repositorio `OficinaMecanica` (onde vivia em `infra/`) — mesmo
backend de state remoto, nenhum recurso foi recriado no Azure durante a
migracao.

## Modulos

| Modulo | Recurso Azure | Finalidade |
|--------|---------------|------------|
| `rg` | Resource Group | Agrupa todos os recursos do projeto |
| `storage` | Storage Account | Backend remoto do state do Terraform |
| `acr` | Azure Container Registry | Registro das imagens Docker da API |
| `aks` | Azure Kubernetes Service | Orquestracao dos containers em producao |
| `keyvault` | Azure Key Vault | Armazenamento centralizado de segredos, acesso via RBAC (role assignments), sem restricao de rede |
| `helm` | Helm Releases (ingress-nginx, OpenTelemetry Collector, nri-bundle) | Ingress Controller e observabilidade (traces/metricas/logs via OpenTelemetry Collector, CPU/memoria via New Relic Infrastructure) |
| `github_oidc` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica` no Azure via OIDC, sem secrets de longa duracao |
| `functionapp` | Azure Function App (Consumption) | Hospeda o `OficinaMecanica.Seguranca` (autenticacao/autorizacao, emissao de JWT RS256) |
| `github_oidc_seguranca` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica.Seguranca` no Azure via OIDC |
| `apim` | Azure API Management (Consumption) | Gateway de API na frente do `ingress-nginx` e da Function App (ver [API Gateway](#api-gateway) abaixo) |

O SQL Server (`svsfiap`) e os bancos `OficinaMecanicaDb`/`SegurancaDb` foram
extraidos pro repositorio irmao
[OficinaMecanica.Banco](../OficinaMecanica.Banco) (state proprio, mesma
storage account/container do tfstate deste repo) — este repositorio so
guarda variaveis com os "fatos conhecidos" sobre o banco (nome do servidor,
nomes dos bancos, credenciais) pra montar as connection strings salvas no
Key Vault, sem depender do state do `OficinaMecanica.Banco`.

Tres arquivos na raiz (`keyvault_secrets.tf`, `aks_keyvault_access.tf`,
`seguranca_keyvault.tf`) conectam modulos entre si sem criar dependencia
circular entre eles - cada um precisa enxergar dois (ou mais) modulos ao
mesmo tempo, o que so e possivel na raiz.

## Provisionando a infraestrutura

Pre-requisitos: [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5, Azure CLI autenticado (`az login`) com permissao na assinatura.

```bash
cp terraform.tfvars.example terraform.tfvars   # preencher os valores (nomes de recursos, regiao, etc.)

# Variaveis sensiveis (ou sem default por outro motivo) nao tem default em
# terraform.tfvars.example de proposito (nunca commitadas) - definir via
# variavel de ambiente antes do apply:
export TF_VAR_sql_administrator_login_password="<senha-forte>"
export TF_VAR_apim_publisher_email="<seu-email>"
export TF_VAR_seguranca_seed_admin_senha="<senha-forte>"

terraform init
terraform plan    # revisar o que sera criado/alterado antes de aplicar
terraform apply
```

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
