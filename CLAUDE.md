# OficinaMecanica.Infra - Infraestrutura como Codigo (Terraform / Azure)

## Visao Geral

Repositorio dedicado ao Terraform que provisiona toda a infraestrutura
Azure usada pelo ecossistema OficinaMecanica — cluster AKS, banco de dados,
registro de imagens, cofre de segredos, API Gateway, observabilidade e
autenticacao de pipelines CI/CD. Migrou pra ca do repositorio `OficinaMecanica`
(onde vivia em `infra/`) pra centralizar a infra de todos os
servicos/repositorios de codigo do ecossistema (`OficinaMecanica`,
`OficinaMecanica.Seguranca`, futuros) num unico lugar, em vez de cada repo
de aplicacao carregar seu proprio `infra/`.

A migracao foi so de realocacao de arquivos — mesmo backend de state remoto
(Storage Account `stfiap`, container `tfstate`), nenhum recurso foi
recriado no Azure (`terraform plan` saiu vazio antes/depois da mudanca de
repositorio).

## Estrutura

Raiz (`*.tf`) + 9 modulos (pasta propria com `main.tf`/`variables.tf`/`outputs.tf` cada):

- **`rg/`**: resource group (`rgfiap`, `northcentralus`)
- **`storage/`**: storage account (`stfiap`) que guarda o tfstate remoto (backend `azurerm`, ver `backend.tf`)
- **`acr/`**: Container Registry (`acrfiap.azurecr.io`), SKU Standard (free tier)
- **`aks/`**: cluster AKS (`aksfiap`), 1 node `Standard_D4as_v4` (AMD, 4 vCPU/16GiB — subiu de `Standard_D2s_v3` por falta de CPU sobrando no node unico; nao-gratis, usar `az aks stop`/`start` pra nao gerar custo ocioso — mas isso NAO para o IP publico do Load Balancer nem o disco do node, que continuam cobrando mesmo com o cluster parado), Azure CNI Overlay, integrado ao ACR via role assignment `AcrPull`. Tambem tem `oidc_issuer_enabled`, `workload_identity_enabled` e o addon `key_vault_secrets_provider` (CSI Secrets Store driver) habilitados. Nome do node pool `agenttmp` (nao `agentpool`) com `temporary_name_for_rotation = "agentpool2"` — permanente, decorrente de uma rotacao que esbarrou em limite regional de vCPU
- **`keyvault/`**: Key Vault (`kvfiap`), RBAC-based (`rbac_authorization_enabled`), rede restrita por IP (`network_acls`, `default_action = Deny`) + bypass pra servicos Azure confiaveis — libera tanto o IP do cliente quanto o IP de saida do cluster AKS (esse ultimo descoberto automaticamente, ver `aks_keyvault_access.tf` abaixo). Os 3 segredos da aplicacao (`keyvault_secrets.tf`, na raiz) sao sincronizados pro Secret nativo do Kubernetes via CSI Secrets Store driver — ver `k8s/oficinamecanica-api/secret-provider-class.yaml` no repo `OficinaMecanica`
- **`helm/`**: quatro `helm_release` — `ingress-nginx` (chart oficial, namespace proprio, Service `LoadBalancer`, com a annotation `azure-load-balancer-health-probe-request-path: /healthz` — sem ela, o health probe do proprio Load Balancer do Azure bate em `GET /`, cai na regra catch-all da API e recebe `301` da Swagger UI em vez de `200`, fazendo o Azure bloquear **todo** trafego externo por considerar o `ingress-nginx` inteiro unhealthy; tambem seta `controller.config.use-forwarded-headers: true` — sem isso o ingress-nginx **ignora** os `X-Forwarded-Proto`/`-Host`/`-Prefix` que a policy da APIM injeta e os substitui pelos proprios valores computados, ver `apim/` abaixo), `monitoring` (`kube-prometheus-stack`: Prometheus + Grafana + kube-state-metrics + node-exporter, sem Alertmanager, PVC de 8Gi/4Gi na StorageClass `managed-csi-premium` que o proprio AKS ja cria, dashboards do Grafana como codigo via sidecar), `loki` (agregacao de logs, modo `Monolithic`, PVC de 10Gi na mesma StorageClass, retencao de 72h, chart do repositorio `grafana-community` — ver `helm/loki.tf`) e `alloy` (coleta os logs de cada pod do node e envia pro Loki). Usa o provider `helm` configurado em `providers.tf` apontando pro `aks` via kube_config
- **`sqldb/`**: Azure SQL Database (`svsfiap.database.windows.net` / `OficinaMecanicaDb`), serverless, tier sempre-gratis. O campo que ativa esse tier (`use_free_limit`) nao existe no provider `azurerm` e nao pode ser setado depois via `az sql db update` (so na criacao) — por isso o banco foi criado via `az sql db create --use-free-limit true --free-limit-exhaustion-behavior AutoPause ...` e depois trazido para o state do Terraform com `terraform import`
- **`github_oidc/`**: App Registration + Service Principal + Federated Identity Credential (OIDC, restrita a `repo:<owner>/<repo>:ref:refs/heads/main`) usados pelo GitHub Actions pra autenticar no Azure sem nenhum secret de longa duracao. Role assignments `AcrPush` (no `acrfiap`) e `Azure Kubernetes Service Cluster Admin Role` (no `aksfiap`) — ver secao "CI/CD" no repo `OficinaMecanica`
- **`apim/`**: Azure API Management (`apimfiap`), SKU `Consumption_0` (unico valor aceito nesse tier - serverless, sem capacidade dedicada, sempre gratis ate 1M chamadas/mes). Fica **na frente** do `ingress-nginx` (nao o substitui) - o `ingress-nginx` continua servindo Grafana/Prometheus/Jaeger/Mailpit diretamente e vira so o *backend* que a APIM chama. Modelo **wildcard/passthrough** (nao import de OpenAPI): cada API (`oficinamecanica-api` no path `oficinaserver`, `grafana` no path `grafana`) e criada "em branco" com uma `azurerm_api_management_api_operation` coringa (`url_template = "/*"`) por metodo HTTP real via `for_each = toset(["GET", "POST", "PUT", "DELETE", "PATCH"])` — a APIM **nao tem um metodo HTTP curinga de verdade**, `method = "*"` e aceito pelo schema do provider Terraform sem erro mas o runtime da Azure nunca casa com nada (404 silencioso pra qualquer request). Backends definidos como entidades nomeadas e reutilizaveis (`azurerm_api_management_backend`: `ingress_nginx` e `grafana`), referenciadas via `<set-backend-service backend-id="...">` na policy de cada API (`azurerm_api_management_api_policy`) — nao `service_url` inline. O IP do LoadBalancer do `ingress-nginx` (e o host nip.io do Grafana, montado a partir dele) e lido dinamicamente via `data "kubernetes_service"` (provider `kubernetes`, configurado em `providers.tf` reaproveitando os mesmos outputs de `module.aks` que o provider `helm` ja usa). `subscription_required = false` nas duas (a API ja tem seu proprio JWT + rotas publicas de proposito; Grafana tem seu proprio login). Nomenclatura de path pensada pra crescer: futuros backends entram como `<nome>server` (ex.: `segurancaserver`, pra `OficinaMecanica.Seguranca`), mesmo padrao de `oficinaserver`.

  A policy de cada API injeta os headers `X-Forwarded-*` que o backend precisa pra saber que esta atras de um gateway publico: `oficinamecanica` seta `X-Forwarded-Proto: https`, `X-Forwarded-Host: <apim>.azure-api.net` e `X-Forwarded-Prefix: /oficinaserver`; `grafana` so `X-Forwarded-Proto: https`. `ingress-nginx` precisa de `use-forwarded-headers: true` (`helm/`, acima) pra nao descartar esses headers e preenche-los sozinho — esse foi o bug raiz por tras do `servers[]` do Swagger aparecendo com o IP interno em vez do host publico da APIM. O lado aplicacao (`Program.cs` do repo `OficinaMecanica`) le esses headers via `ForwardedHeadersMiddleware` + middleware customizado pra `X-Forwarded-Prefix`.

  Grafana usa `serve_from_sub_path: false` (nao `true`) em `helm/monitoring.yaml.tpl` **de proposito**: a policy da APIM (`set-backend-service` + operations coringa) ja tira o `/grafana` **antes** de encaminhar pro backend — com `true` o Grafana entrava num loop infinito de redirect em `/login` e `/`.

Dois arquivos na raiz (nao dentro de nenhum modulo) conectam modulos entre si
sem criar dependencia circular — cada um precisa ver outputs de dois modulos
ao mesmo tempo, o que so e possivel na raiz (modulos nunca "olham de volta"
pra quem os chama):
- **`keyvault_secrets.tf`**: os 3 `azurerm_key_vault_secret` da aplicacao (`jwt-secret-key`, `admin-senha`, `sql-connection-string`, essa ultima montada a partir dos outputs do `sqldb`)
- **`aks_keyvault_access.tf`**: a role assignment `Key Vault Secrets User` pra identidade do addon CSI do `aks` no `keyvault`, mais um `data "azurerm_public_ip"` que descobre automaticamente o IP de saida do cluster (usado no `network_acls` do Key Vault) — nenhum dos dois modulos referencia o outro diretamente

A assinatura usada (Azure for Students) tem restricao de regiao
(`sys.regionrestriction`: so libera `chilecentral`, `canadacentral`,
`northcentralus`, `eastus`, `mexicocentral`). Alem dessa politica geral,
alguns servicos tem uma segunda trava de **capacidade propria por regiao**
(passar na politica de regiao nao garante que aquele servico especifico vai
deixar criar ali): o tamanho de VM do node pool do AKS (serie B bloqueada
pelo proprio AKS, `Standard_F2s_v2` apareceu como "Size not available" mesmo
com cota livre — fechado em `Standard_D2s_v3`, depois subiu pra
`Standard_D4as_v4` por falta de CPU sobrando) e o Azure SQL Database
(`centralus`/`eastus` bloqueados por `ProvisioningDisabled` apesar de
permitidos pela politica de regiao — fechado em `canadacentral`). Se o
provider Terraform nao expuser um campo que so existe via API/CLI (como o
`use_free_limit` do SQL Database), o caminho e criar o recurso via `az cli`
e trazer pro Terraform com `terraform import`.

Comandos do Terraform ficam por conta de quem estiver rodando (nao ha
automacao de CI/CD pra provisionar infraestrutura ainda) — sempre a partir
da raiz deste repositorio como working directory. O deploy da *aplicacao*
(nao da infra) e automatizado no repositorio `OficinaMecanica`, ver o
`CLAUDE.md` de la, secao "CI/CD".

## Comandos Uteis

```bash
terraform init
terraform plan
terraform apply
terraform output
terraform output -raw apim_gateway_url
```

## Proximos passos conhecidos

- **`OficinaMecanica.Seguranca`** (Azure Function, autenticacao/autorizacao
  extraida do monolito `OficinaMecanica`, JWT assimetrico RS256 + JWKS): vai
  precisar de infra nova aqui — novo modulo `functionapp/` (Function App +
  Service Plan Consumption), `sqldb` ganha um `azurerm_mssql_database` novo
  (`SegurancaDb`, reaproveitando o mesmo `svsfiap`), reaproveita o `storage`
  (`stfiap`) existente tambem como `AzureWebJobsStorage` da Function (sem
  storage account dedicado), uma `azurerm_key_vault_key` RS256 no `keyvault`
  existente, e um novo bloco `segurancaserver` em `apim/main.tf` seguindo o
  padrao ja usado por `oficinamecanica`/`grafana`.
