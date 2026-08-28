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
| `helm` | Helm Releases (ingress-nginx, kube-prometheus-stack, Loki, Alloy) | Ingress Controller e observabilidade (metricas via Prometheus + Grafana, logs via Loki + Alloy) |
| `sqldb` | Azure SQL Database | Banco de dados relacional gerenciado (tier serverless), bancos `OficinaMecanicaDb` e `SegurancaDb` no mesmo servidor logico |
| `github_oidc` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica` no Azure via OIDC, sem secrets de longa duracao |
| `functionapp` | Azure Function App (Consumption) | Hospeda o `OficinaMecanica.Seguranca` (autenticacao/autorizacao, emissao de JWT RS256) |
| `github_oidc_seguranca` | Azure AD App Registration + Federated Identity Credential | Autenticacao do GitHub Actions do repo `OficinaMecanica.Seguranca` no Azure via OIDC |
| `apim` | Azure API Management (Consumption) | Gateway de API na frente do `ingress-nginx` e da Function App (ver [API Gateway](#api-gateway) abaixo) |

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
terraform output -raw sql_server_fqdn     # ex: valor especifico, sem aspas
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

> **O que vem no pacote `kube-prometheus-stack`** para observabilidade em Kubernetes:
>
> | Componente | Finalidade |
> |------------|------------|
> | Prometheus | Coleta e armazena as metricas (banco de dados de series temporais) |
> | Prometheus Operator | Controller que gerencia o Prometheus via CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, etc.) |
> | Grafana | Dashboards e visualizacao das metricas |
> | kube-state-metrics | Metricas sobre o estado dos objetos do Kubernetes (Deployments, Pods, HPAs, etc.) |
> | node-exporter | Metricas de sistema operacional/hardware de cada node |
> | Alertmanager | Roteamento de alertas (Slack, e-mail, etc.) — **desabilitado** neste projeto, sem canal de alerta configurado ainda |
>
> Cada componente ja vem com seu proprio `Deployment`/`StatefulSet`, `Service`
> e permissoes de RBAC do Kubernetes — nada disso precisou ser escrito na
> mao, so configurado via `helm/monitoring.yaml.tpl`.

> **Logs agregados via Loki + Grafana Alloy** (`helm/loki.tf`):
>
> | Componente | Finalidade |
> |------------|------------|
> | Loki | Armazena e indexa os logs (modo `Monolithic` — um unico binario, sem os componentes read/write/backend separados do modo distribuido, que so fariam sentido em escala maior) |
> | Grafana Alloy | Le o log de cada container do node (DaemonSet, 1 pod ja que o cluster tem 1 node so) e envia pro Loki |
>
> O Loki roda com storage em filesystem (PVC de 10Gi na mesma StorageClass
> do Prometheus/Grafana, sem object storage tipo Azure Blob Storage) e
> retencao de 72h — mais longa que as 6h do Prometheus. Caches de
> chunks/resultados do Loki (baseados em Memcached) e o canary de teste E2E
> ficam desabilitados de proposito: o cluster tem 1 node so
> (`Standard_D4as_v4`, 4 vCPU/16GiB), e cada um desses componentes
> adicionaria outro Pod competindo pelo mesmo recurso escasso, sem
> necessidade real no volume de log baixo deste projeto.

## API Gateway

O [Azure API Management](https://azure.microsoft.com/products/api-management)
(`apim`, tier **Consumption** — sempre gratis ate 1M chamadas/mes) fica
**na frente** do `ingress-nginx`, nao o substitui: o `ingress-nginx` continua
servindo Grafana/Prometheus/Jaeger/Mailpit diretamente e vira so o *backend*
que a APIM chama pra rotear. Do ponto de vista de quem consome a API (ou o
Grafana), o gateway da APIM passa a ser o novo endereco publico:

```bash
terraform output -raw apim_gateway_url   # https://<nome>.azure-api.net
```

- `https://<nome>.azure-api.net/oficinaserver/...` → API do repo `OficinaMecanica` (Swagger UI incluso, em `/oficinaserver/index.html`)
- `https://<nome>.azure-api.net/grafana/...` → Grafana
- `https://<nome>.azure-api.net/segurancaserver/...` → Function App do `OficinaMecanica.Seguranca` (emissao/JWKS de JWT RS256), backend diferente dos dois acima: aponta direto pro hostname publico da Function (`<nome>.azurewebsites.net`), sem passar pelo `ingress-nginx`/AKS

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

Pra Swagger UI, "Try it out" e os links do Grafana funcionarem corretamente
atras do prefixo da APIM, a policy de cada API injeta
`X-Forwarded-Proto`/`-Host`/`-Prefix` antes de encaminhar. Dois pontos sao
necessarios pra esses headers chegarem intactos ate o pod:

1. **`ingress-nginx` com `controller.config.use-forwarded-headers: true`**
   (`helm/main.tf`) — o default do chart e `false`, que faz o nginx
   **descartar** os headers recebidos e preencher com o que ele mesmo
   enxerga.
2. **`Program.cs`** (repositorio `OficinaMecanica`) registra
   `app.UseForwardedHeaders(...)` + um middleware proprio lendo
   `X-Forwarded-Prefix` na mao pra setar `HttpRequest.PathBase`.

Grafana usa `serve_from_sub_path: false` (nao `true`) em
`helm/monitoring.yaml.tpl` de proposito: a policy da APIM ja tira o
`/grafana` antes de encaminhar pro backend — com `true` o Grafana entrava
num loop infinito de redirect.
