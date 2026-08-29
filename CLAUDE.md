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

Raiz (`*.tf`) + 10 modulos (pasta propria com `main.tf`/`variables.tf`/`outputs.tf` cada):

- **`rg/`**: resource group (`rgfiap`, `northcentralus`)
- **`storage/`**: storage account (`stfiap`) que guarda o tfstate remoto (backend `azurerm`, ver `backend.tf`)
- **`acr/`**: Container Registry (`acrfiap.azurecr.io`), SKU Standard (free tier)
- **`aks/`**: cluster AKS (`aksfiap`), 1 node `Standard_D4as_v4` (AMD, 4 vCPU/16GiB — subiu de `Standard_D2s_v3` por falta de CPU sobrando no node unico; nao-gratis, usar `az aks stop`/`start` pra nao gerar custo ocioso — mas isso NAO para o IP publico do Load Balancer nem o disco do node, que continuam cobrando mesmo com o cluster parado), Azure CNI Overlay, integrado ao ACR via role assignment `AcrPull`. Tambem tem `oidc_issuer_enabled`, `workload_identity_enabled` e o addon `key_vault_secrets_provider` (CSI Secrets Store driver) habilitados. Nome do node pool `agenttmp` (nao `agentpool`) com `temporary_name_for_rotation = "agentpool2"` — permanente, decorrente de uma rotacao que esbarrou em limite regional de vCPU
- **`keyvault/`**: Key Vault (`kvfiap`), RBAC-based (`rbac_authorization_enabled`) — acesso gateado inteiramente por role assignments, **sem** restricao de rede: `network_acls { default_action = "Allow", bypass = "AzureServices" }`, sem `ip_rules` nenhuma. Cheguei a tentar restringir por IP primeiro (IP do cliente + IP de saida do cluster AKS + IPs de saida da Function App do `OficinaMecanica.Seguranca`), mas Function App em tier Consumption tem egress imprevisivel — a lista de IPs de saida que a propria Azure expoe (`possible_outbound_ip_address_list`) nao e exaustiva (confirmado na pratica: uma chamada real da Function foi bloqueada vindo de um IP que nao estava nessa lista), e o `bypass = "AzureServices"` tambem nao cobre esse cenario (testado, "caller is not a trusted service") — sem alternativa pratica de allowlist de IP confiavel pra esse caso, sem subir uma VNet so pra isso, abandonei em favor de RBAC puro (ver o comentario em `keyvault/main.tf`). O segredo da aplicacao do monolito (`keyvault_secrets.tf`, na raiz) e sincronizado pro Secret nativo do Kubernetes via CSI Secrets Store driver — ver `k8s/oficinamecanica-api/secret-provider-class.yaml` no repo `OficinaMecanica`. Os segredos do `OficinaMecanica.Seguranca` (`seguranca_keyvault.tf`, na raiz) sao resolvidos direto pela Function App via Key Vault Reference/managed identity, sem passar pelo AKS (ver `functionapp/` abaixo)
- **`helm/`**: quatro `helm_release` — `ingress-nginx` (chart oficial, namespace proprio, Service `LoadBalancer`, com a annotation `azure-load-balancer-health-probe-request-path: /healthz` — sem ela, o health probe do proprio Load Balancer do Azure bate em `GET /`, cai na regra catch-all da API e recebe `301` da Swagger UI em vez de `200`, fazendo o Azure bloquear **todo** trafego externo por considerar o `ingress-nginx` inteiro unhealthy; tambem seta `controller.config.use-forwarded-headers: true` — sem isso o ingress-nginx **ignora** os `X-Forwarded-Proto`/`-Host`/`-Prefix` que a policy da APIM injeta e os substitui pelos proprios valores computados, ver `apim/` abaixo), `monitoring` (`kube-prometheus-stack`: Prometheus + Grafana + kube-state-metrics + node-exporter, sem Alertmanager, PVC de 8Gi/4Gi na StorageClass `managed-csi-premium` que o proprio AKS ja cria, dashboards do Grafana como codigo via sidecar), `loki` (agregacao de logs, modo `Monolithic`, PVC de 10Gi na mesma StorageClass, retencao de 72h, chart do repositorio `grafana-community` — ver `helm/loki.tf`) e `alloy` (coleta os logs de cada pod do node e envia pro Loki). Usa o provider `helm` configurado em `providers.tf` apontando pro `aks` via kube_config
- **`github_oidc/`**: App Registration + Service Principal + Federated Identity Credential (OIDC, restrita a `repo:<owner>/<repo>:ref:refs/heads/main`) usados pelo GitHub Actions do repo `OficinaMecanica` pra autenticar no Azure sem nenhum secret de longa duracao. Role assignments `AcrPush` (no `acrfiap`) e `Azure Kubernetes Service Cluster Admin Role` (no `aksfiap`) — ver secao "CI/CD" no repo `OficinaMecanica`
- **`functionapp/`**: infraestrutura do `OficinaMecanica.Seguranca` (Azure Function de autenticacao/autorizacao, extraida do monolito `OficinaMecanica`, JWT assimetrico RS256 + JWKS). Service Plan `Y1` (Consumption — mesma logica sempre-gratis ja usada na APIM) + `azurerm_linux_function_app` (.NET 8 isolated), managed identity System-Assigned (autentica no Key Vault via `DefaultAzureCredential`, sem client secret nenhum). Reaproveita a mesma storage account do tfstate (`stfiap`, modulo `storage`) como `AzureWebJobsStorage`, em vez de criar uma storage account dedicada so pra isso. Os dois segredos de verdade (connection string do `SegurancaDb`, senha do admin seed) sao resolvidos via Key Vault Reference (`@Microsoft.KeyVault(SecretUri=...)`) usando essa mesma managed identity — ver `seguranca_keyvault.tf` na raiz, abaixo. `WEBSITE_RUN_FROM_PACKAGE`/`WEBSITE_MOUNT_ENABLED` ficam em `lifecycle.ignore_changes` (adicionados pelo proprio mecanismo de deploy, fora do Terraform). `site_config.cors` libera `https://<apim_name>.azure-api.net` como origin - o Swagger UI da Function (servido via APIM) precisa buscar seu proprio `swagger.json` direto no hostname da Function (o backend `seguranca` da APIM aponta pra la sem passar pelo ingress-nginx), e o navegador bloqueava isso por CORS sem esse header
- **`github_oidc_seguranca/`**: mesmo padrao OIDC do `github_oidc/` acima, modulo **separado** (nao uma segunda instancia do `github_oidc`) porque a permissao necessaria e bem diferente — restrito ao repositorio `OficinaMecanica.Seguranca`, role assignment `Contributor` escopado so na propria Function App (`module.functionapp.function_app_id`, suficiente pra deploy via zip), sem AcrPush nem nenhuma role no cluster AKS
- **`apim/`**: Azure API Management (`apimfiap`), SKU `Consumption_0` (unico valor aceito nesse tier - serverless, sem capacidade dedicada, sempre gratis ate 1M chamadas/mes). Fica **na frente** do `ingress-nginx` (nao o substitui) - o `ingress-nginx` continua servindo Grafana/Prometheus/Jaeger/Mailpit diretamente e vira so o *backend* que a APIM chama. Modelo **wildcard/passthrough** (nao import de OpenAPI): cada API (`oficinamecanica-api` no path `oficinaserver`, `grafana` no path `grafana`, `seguranca-api` no path `segurancaserver`) e criada "em branco" com uma `azurerm_api_management_api_operation` coringa (`url_template = "/*"`) por metodo HTTP real via `for_each = toset(["GET", "POST", "PUT", "DELETE", "PATCH"])` — a APIM **nao tem um metodo HTTP curinga de verdade**, `method = "*"` e aceito pelo schema do provider Terraform sem erro mas o runtime da Azure nunca casa com nada (404 silencioso pra qualquer request). Backends definidos como entidades nomeadas e reutilizaveis (`azurerm_api_management_backend`: `ingress_nginx`, `grafana` e `seguranca`), referenciadas via `<set-backend-service backend-id="...">` na policy de cada API (`azurerm_api_management_api_policy`) — nao `service_url` inline. O backend `seguranca` e diferente dos outros dois: aponta direto pro hostname publico da Function App (`module.functionapp.default_hostname`, `<nome>.azurewebsites.net`), sem passar pelo `ingress-nginx`/AKS. O IP do LoadBalancer do `ingress-nginx` (e o host nip.io do Grafana, montado a partir dele) e lido dinamicamente via `data "kubernetes_service"` (provider `kubernetes`, configurado em `providers.tf` reaproveitando os mesmos outputs de `module.aks` que o provider `helm` ja usa). `subscription_required = false` nas tres (a API ja tem seu proprio JWT + rotas publicas de proposito; Grafana tem seu proprio login; Seguranca emite os JWT, nao valida nenhum aqui). Nomenclatura de path pensada pra crescer: cada backend novo entra como `<nome>server` (ex.: `segurancaserver`), mesmo padrao ja usado por `oficinaserver`.

  A policy de cada API injeta os headers de proxy que o backend precisa pra saber que esta atras de um gateway publico: `oficinamecanica` seta `X-Forwarded-Proto: https`, `X-Forwarded-Host: <apim>.azure-api.net` e `X-Forwarded-Prefix: /oficinaserver`; `grafana` so `X-Forwarded-Proto: https`. `ingress-nginx` precisa de `use-forwarded-headers: true` (`helm/`, acima) pra nao descartar esses headers e preenche-los sozinho — esse foi o bug raiz por tras do `servers[]` do Swagger aparecendo com o IP interno em vez do host publico da APIM. O lado aplicacao (`Program.cs` do repo `OficinaMecanica`) le esses headers via `ForwardedHeadersMiddleware` + middleware customizado pra `X-Forwarded-Prefix`. A policy do `seguranca` e diferente das outras duas: usa `X-Gateway-Proto`/`X-Gateway-Host`/`X-Gateway-Prefix` (nomes proprios, NAO `X-Forwarded-*`) porque o App Service intercepta e descarta silenciosamente qualquer header client-supplied comecando com `X-Forwarded-` antes de chegar no worker isolado (confirmado na pratica) — o `ServerBasePathDocumentFilter.cs` (repo `OficinaMecanica.Seguranca`) le esses headers `X-Gateway-*` pra montar o `servers[]` do OpenAPI e o redirect da raiz com a URL publica certa da APIM.

  Grafana usa `serve_from_sub_path: false` (nao `true`) em `helm/monitoring.yaml.tpl` **de proposito**: a policy da APIM (`set-backend-service` + operations coringa) ja tira o `/grafana` **antes** de encaminhar pro backend — com `true` o Grafana entrava num loop infinito de redirect em `/login` e `/`.

## Banco de Dados (OficinaMecanica.Banco)

O SQL Server (`svsfiap`) e os 2 bancos (`OficinaMecanicaDb`, `SegurancaDb`)
foram extraidos pro repositorio irmao `OficinaMecanica.Banco` (state proprio,
mesma storage account/container do tfstate deste repo — `stfiap`/`tfstate`,
so a key e diferente: `banco.tfstate`). Diferente da propria migracao deste
repositorio (que foi so realocacao de arquivos, mesmo backend/state), essa
foi uma divisao de verdade: os recursos ja existiam de verdade no Azure e
foram movidos de state via `terraform state rm` (aqui) + `terraform import`
(no `OficinaMecanica.Banco`), sem destruir/recriar nada — confirmado via
`terraform plan` vazio nos dois repos apos a migracao.

Esse repositorio **nao referencia** o state do `OficinaMecanica.Banco`
(nada de `terraform_remote_state`, acoplamento forte entre os dois states) —
`keyvault_secrets.tf`/`seguranca_keyvault.tf` so precisam do FQDN do
servidor (previsivel: `<nome>.database.windows.net`) e dos nomes dos bancos
pra montar as connection strings, entao `sql_server_name`/`sql_database_name`/
`seguranca_database_name`/`sql_administrator_login`/
`sql_administrator_login_password` continuam existindo aqui como variaveis
simples ("fatos conhecidos" sobre um recurso que este repo nao gerencia
mais) — mesmo padrao ja usado pro Key Vault (`key_vault_uri` montado a
partir de `var.key_vault_name` em `functionapp/main.tf`, nao de um output
de modulo).

Tres arquivos na raiz (nao dentro de nenhum modulo) conectam modulos entre si
sem criar dependencia circular — cada um precisa ver outputs de dois (ou mais)
modulos ao mesmo tempo, o que so e possivel na raiz (modulos nunca "olham de
volta" pra quem os chama):
- **`keyvault_secrets.tf`**: o `azurerm_key_vault_secret` da aplicacao do monolito (`sql-connection-string`, montado a partir de `var.sql_server_name`/`var.sql_database_name` — ver secao sobre `OficinaMecanica.Banco` acima pra saber por que nao e mais `module.sqldb.*`) — `jwt-secret-key`/`admin-senha` existiam aqui antes e foram removidos junto com a migracao da autenticacao pro `OficinaMecanica.Seguranca` (ver `functionapp/`/`seguranca_keyvault.tf`)
- **`aks_keyvault_access.tf`**: a role assignment `Key Vault Secrets User` pra identidade do addon CSI do `aks` no `keyvault` — nenhum dos dois modulos referencia o outro diretamente. Sem nenhum `data "azurerm_public_ip"` aqui: com o Key Vault em RBAC puro (`network_acls.default_action = "Allow"`, ver bullet `keyvault/` acima), essa role assignment e o unico portao de acesso que o addon CSI precisa
- **`seguranca_keyvault.tf`**: recursos do `OficinaMecanica.Seguranca` no mesmo Key Vault (`kvfiap`) — a chave `azurerm_key_vault_key` RSA-2048 (`seguranca-rs256`, usada pra assinar/verificar JWT RS256 remotamente via `CryptographyClient`, a chave privada nunca sai do vault) e os secrets `seguranca-sql-connection-string`/`seguranca-seed-admin-senha`, mais as role assignments `Key Vault Crypto User` (so na chave) e `Key Vault Secrets User` (no vault inteiro) pra managed identity da Function App (`module.functionapp`)

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
