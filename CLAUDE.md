# OficinaMecanica.Infra - Infraestrutura como Codigo (Terraform / Azure)

## Visao Geral

Repositorio dedicado ao Terraform que provisiona toda a infraestrutura
Azure usada pelo ecossistema OficinaMecanica — cluster AKS, banco de dados,
registro de imagens, cofre de segredos, API Gateway, observabilidade e
autenticacao de pipelines CI/CD. Migrou pra ca do repositorio `OficinaMecanica`
(onde vivia em `infra/`) pra centralizar a infra de todos os
servicos/repositorios de codigo do ecossistema (`OficinaMecanica`,
`OficinaMecanica.Seguranca`, `OficinaMecanica.Billing`,
`OficinaMecanica.Execucao`, futuros) num unico lugar, em vez de cada repo
de aplicacao carregar seu proprio `infra/`.

A migracao foi so de realocacao de arquivos — mesmo backend de state remoto
(Storage Account `stfiap`, container `tfstate`), nenhum recurso foi
recriado no Azure (`terraform plan` saiu vazio antes/depois da mudanca de
repositorio).

## Estrutura

Raiz (`*.tf`) + 13 modulos (pasta propria com `main.tf`/`variables.tf`/`outputs.tf` cada):

- **`rg/`**: resource group (`rgfiap`, `northcentralus`)
- **`storage/`**: storage account (`stfiap`) que guarda o tfstate remoto (backend `azurerm`, ver `backend.tf`)
- **`acr/`**: Container Registry (`acrfiap.azurecr.io`), SKU Standard (free tier)
- **`aks/`**: cluster AKS (`aksfiap`), 1 node `Standard_D4as_v4` (AMD, 4 vCPU/16GiB — subiu de `Standard_D2s_v3` por falta de CPU sobrando no node unico; nao-gratis, usar `az aks stop`/`start` pra nao gerar custo ocioso — mas isso NAO para o IP publico do Load Balancer nem o disco do node, que continuam cobrando mesmo com o cluster parado), Azure CNI Overlay, integrado ao ACR via role assignment `AcrPull`. Tambem tem `oidc_issuer_enabled`, `workload_identity_enabled` e o addon `key_vault_secrets_provider` (CSI Secrets Store driver) habilitados. Nome do node pool `agenttmp` (nao `agentpool`) com `temporary_name_for_rotation = "agentpool2"` — permanente, decorrente de uma rotacao que esbarrou em limite regional de vCPU
- **`keyvault/`**: Key Vault (`kvfiap`), RBAC-based (`rbac_authorization_enabled`) — acesso gateado inteiramente por role assignments, **sem** restricao de rede: `network_acls { default_action = "Allow", bypass = "AzureServices" }`, sem `ip_rules` nenhuma. Cheguei a tentar restringir por IP primeiro (IP do cliente + IP de saida do cluster AKS + IPs de saida da Function App do `OficinaMecanica.Seguranca`), mas Function App em tier Consumption tem egress imprevisivel — a lista de IPs de saida que a propria Azure expoe (`possible_outbound_ip_address_list`) nao e exaustiva (confirmado na pratica: uma chamada real da Function foi bloqueada vindo de um IP que nao estava nessa lista), e o `bypass = "AzureServices"` tambem nao cobre esse cenario (testado, "caller is not a trusted service") — sem alternativa pratica de allowlist de IP confiavel pra esse caso, sem subir uma VNet so pra isso, abandonei em favor de RBAC puro (ver o comentario em `keyvault/main.tf`). O segredo da aplicacao do OS Service (o antigo monolito) (`keyvault_secrets.tf`, na raiz) e sincronizado pro Secret nativo do Kubernetes via CSI Secrets Store driver — ver `k8s/oficinamecanica-api/secret-provider-class.yaml` no repo `OficinaMecanica`. Os segredos do `OficinaMecanica.Seguranca` (`seguranca_keyvault.tf`, na raiz) sao resolvidos direto pela Function App via Key Vault Reference/managed identity, sem passar pelo AKS (ver `functionapp/` abaixo)
- **`helm/`**: `ingress-nginx` (chart oficial, namespace proprio, Service `LoadBalancer`, com a annotation `azure-load-balancer-health-probe-request-path: /healthz` — sem ela, o health probe do proprio Load Balancer do Azure bate em `GET /`, cai na regra catch-all da API e recebe `301` da Swagger UI em vez de `200`, fazendo o Azure bloquear **todo** trafego externo por considerar o `ingress-nginx` inteiro unhealthy; tambem seta `controller.config.use-forwarded-headers: true` — sem isso o ingress-nginx **ignora** os `X-Forwarded-Proto`/`-Host`/`-Prefix` que a policy da APIM injeta e os substitui pelos proprios valores computados, ver `apim/` abaixo), `otel-collector` (`open-telemetry/opentelemetry-collector`, `mode: deployment`, 1 replica — recebe traces/metricas/logs OTLP da API e reexporta pra New Relic via exporter `otlphttp` generico, `headers.api-key` = license key) e `newrelic` (chart `nri-bundle` — integracao de Kubernetes da New Relic, `kube-state-metrics` proprio ja que nao ha mais nenhum concorrente no cluster). Prometheus/Grafana/Loki/Alloy/Jaeger (kube-prometheus-stack + Loki/Alloy self-hosted) foram removidos do cluster e substituidos pelo New Relic (decisao explicita: escolha livre de ferramenta de observabilidade pro projeto). Usa o provider `helm` configurado em `providers.tf` apontando pro `aks` via kube_config. Namespace `monitoring` recriado como `kubernetes_namespace` explicito (nao mais `create_namespace=true` de um helm_release especifico) - o Secret nativo com a license key da New Relic (`kubernetes_secret.newrelic_license_key`, unico consumidor de `azurerm_key_vault_secret.newrelic_license_key` na raiz) precisa que o namespace ja exista antes dele. Tambem hospeda o **RabbitMQ** (`helm/rabbitmq.tf`, broker da Saga dos microsservicos): `kubernetes_stateful_set_v1` de 1 replica com a imagem OFICIAL `rabbitmq:<tag-4.x>-management` (tag fixa em `variables.tf`, hoje 4.4.0, a mesma dos composes/Testcontainers/e2e dos servicos; nada de Bitnami - virou pago - nem operador), namespace proprio `messaging`, PVC 2Gi (`managed-csi`, retencao `Retain`), requests 100m/256Mi e limits 500m/512Mi (o no unico nao tem folga), uid 999 nao-root, `automountServiceAccountToken = false`, `30-oficina.conf` (em `/etc/rabbitmq/conf.d/`, ao lado do `10-defaults.conf` da imagem)/`enabled_plugins` num ConfigMap montado por `subPath` (management + prometheus). Service `ClusterIP` (5672 amqp, 15672 management, 15692 metricas) em `rabbitmq.messaging.svc.cluster.local`, **sem Ingress** (management so por `kubectl -n messaging port-forward svc/rabbitmq 15672:15672`). Pegadinhas: `RABBITMQ_DEFAULT_USER/PASS` so valem no primeiro boot (diretorio de dados vazio) - rotacionar senha exige `rabbitmqctl change_password` alem do `-replace` do `random_password`; a imagem recusa as variaveis `*_FILE`; credenciais vem de `random_password.rabbitmq` na raiz (`messaging_keyvault.tf`), passadas ao modulo como variaveis (`rabbitmq_username`/`rabbitmq_password`, sensivel). Ver `docs/adr/0004`
- **`github_oidc/`**: App Registration + Service Principal + Federated Identity Credential (OIDC, restrita a `repo:<owner>/<repo>:ref:refs/heads/main` e `ref:refs/heads/release`) usados pelo GitHub Actions do repo `OficinaMecanica` pra autenticar no Azure sem nenhum secret de longa duracao. Role assignments `AcrPush` (no `acrfiap`), `Azure Kubernetes Service Cluster Admin Role` (no `aksfiap`) e `Key Vault Secrets User` (no `kvfiap`, pro step de migration ler a connection string) — ver secao "CI/CD" no repo `OficinaMecanica`
- **`github_oidc_infra/`**: identidade OIDC unica do proprio repositorio (`OficinaMecanica.Infra`) - cobre tanto `terraform plan` (PR) quanto `terraform apply` de verdade (push em `main`/`release`). `Contributor` no resource group inteiro (cobre tudo que este repo gerencia), `Storage Blob Data Contributor` no container do tfstate (RBAC de dados, separado do Contributor de control-plane - sem ele o apply le o state mas nao consegue escrever de volta), `Key Vault Administrator` (esse repo cria/gerencia secrets, nao so le) e `Application.ReadWrite.All` (Microsoft Graph, com admin consent) - necessario porque os modulos `github_oidc*` deste repo gerenciam suas proprias App Registrations via Terraform
- **`github_oidc_banco/`**: mesmo padrao de identidade unica, mas pro repositorio irmao `OficinaMecanica.Banco` - `Reader` no resource group (so pra resolver o `data "azurerm_resource_group" "existing"` de la), `Storage Blob Data Contributor` no tfstate, e `Contributor` escopado especificamente no SQL Server (`svsfiap`, unico recurso que aquele repo de fato gerencia). Tambem tem `Key Vault Secrets Officer` escopado SO no secret `execucao-mongo-connection-string` (`var.key_vault_secret_name`, `local.execucao_mongo_secret_name` na raiz; ver `docs/adr/0005`): o Banco grava la esse secret, porque o host do MongoDB Atlas so existe depois que ele cria o cluster - por isso este repo NAO cria esse secret. Escopo por secret (nao no vault) porque a identidade tem credencial de `pull_request`; ele so vale com o secret ja existente (bootstrap em "Banco de Dados" abaixo)
- **`functionapp/`**: infraestrutura do `OficinaMecanica.Seguranca` (Azure Function de autenticacao/autorizacao, extraida do monolito `OficinaMecanica`, JWT assimetrico RS256 + JWKS). Service Plan `Y1` (Consumption — mesma logica sempre-gratis ja usada na APIM) + `azurerm_linux_function_app` (.NET 8 isolated), managed identity System-Assigned (autentica no Key Vault via `DefaultAzureCredential`, sem client secret nenhum). Reaproveita a mesma storage account do tfstate (`stfiap`, modulo `storage`) como `AzureWebJobsStorage`, em vez de criar uma storage account dedicada so pra isso. Os dois segredos de verdade (connection string do `SegurancaDb`, senha do admin seed) sao resolvidos via Key Vault Reference (`@Microsoft.KeyVault(SecretUri=...)`) usando essa mesma managed identity — ver `seguranca_keyvault.tf` na raiz, abaixo. `WEBSITE_RUN_FROM_PACKAGE`/`WEBSITE_MOUNT_ENABLED` ficam em `lifecycle.ignore_changes` (adicionados pelo proprio mecanismo de deploy, fora do Terraform). `site_config.cors` libera `https://<apim_name>.azure-api.net` como origin - o Swagger UI da Function (servido via APIM) precisa buscar seu proprio `swagger.json` direto no hostname da Function (o backend `seguranca` da APIM aponta pra la sem passar pelo ingress-nginx), e o navegador bloqueava isso por CORS sem esse header
- **`github_oidc_seguranca/`**: mesmo padrao OIDC do `github_oidc/` acima, modulo **separado** (nao uma segunda instancia do `github_oidc`) porque a permissao necessaria e bem diferente — restrito ao repositorio `OficinaMecanica.Seguranca`, role assignment `Contributor` escopado so na propria Function App (`module.functionapp.function_app_id`, suficiente pra deploy via zip), sem AcrPush nem nenhuma role no cluster AKS. Tambem tem `Key Vault Secrets User` (no `kvfiap`) pro step de migration daquele repo ler a connection string
- **`github_oidc_aks_app/`**: modulo OIDC **parametrizado por servico** pra microsservicos que rodam no AKS com imagem no ACR (Billing, Execucao, e os proximos) - NAO altera o `github_oidc` do OS Service. Subject com IDs imutaveis (`repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main|release`), **sem** credencial de `pull_request` (o job de deploy tem AcrPush + Cluster Admin). Roles: `AcrPush` (`acrfiap`), `Azure Kubernetes Service Cluster Admin Role` (`aksfiap`) e `Key Vault Secrets User` **por secret** (`key_vault_secret_scopes`, mapa nome => id ARM do secret), nao no vault inteiro; a Execucao usa o mapa VAZIO (nenhuma role no Key Vault: a connection string do Mongo chega ao pod pelo CSI com a identidade do addon). Instanciado na raiz como `github_oidc_billing`/`github_oidc_execucao` com `count = var.<x>_github_repo_id == null ? 0 : 1`: os repos ainda nao existem no GitHub, entao `billing_github_repo_id`/`execucao_github_repo_id` tem `default = null` e o modulo so passa a existir quando o id e informado. **Passo apos criar o repo**: `gh api repos/willianrmattos/<repo> --jq .id` e gravar o valor no `default` em `variables.tf` via PR (nao so num `.tfvars` local: o CI nao le `.tfvars`, e um plan sem o id propoe destruir a identidade). Outputs condicionais `billing_github_actions_client_id`/`execucao_github_actions_client_id` (`one(module.x[*].client_id)`). Ver `docs/adr/0006`
- **`apim/`**: Azure API Management (`apimfiap`), SKU `Consumption_0` (unico valor aceito nesse tier - serverless, sem capacidade dedicada, sempre gratis ate 1M chamadas/mes). Fica **na frente** do `ingress-nginx` (nao o substitui) - o `ingress-nginx` continua servindo Mailpit diretamente e vira so o *backend* que a APIM chama. Modelo **wildcard/passthrough** (nao import de OpenAPI): cada API (`oficinamecanica-api` no path `oficinaserver`, `seguranca-api` no path `segurancaserver`) e criada "em branco" com uma `azurerm_api_management_api_operation` coringa (`url_template = "/*"`) por metodo HTTP real via `for_each = toset(["GET", "POST", "PUT", "DELETE", "PATCH"])` — a APIM **nao tem um metodo HTTP curinga de verdade**, `method = "*"` e aceito pelo schema do provider Terraform sem erro mas o runtime da Azure nunca casa com nada (404 silencioso pra qualquer request). Backends definidos como entidades nomeadas e reutilizaveis (`azurerm_api_management_backend`: `ingress_nginx` e `seguranca`), referenciadas via `<set-backend-service backend-id="...">` na policy de cada API (`azurerm_api_management_api_policy`) — nao `service_url` inline. O backend `seguranca` e diferente do outro: aponta direto pro hostname publico da Function App (`module.functionapp.default_hostname`, `<nome>.azurewebsites.net`), sem passar pelo `ingress-nginx`/AKS. O IP do LoadBalancer do `ingress-nginx` e lido dinamicamente via `data "kubernetes_service"` (provider `kubernetes`, configurado em `providers.tf` reaproveitando os mesmos outputs de `module.aks` que o provider `helm` ja usa). `subscription_required = false` nas duas (a API ja tem seu proprio JWT + rotas publicas de proposito; Seguranca emite os JWT, nao valida nenhum aqui). Nomenclatura de path pensada pra crescer: cada backend novo entra como `<nome>server` (ex.: `segurancaserver`), mesmo padrao ja usado por `oficinaserver`. **Billing e Execucao** (`billingserver`/`execucaoserver`, apis `billing-api`/`execucao-api`) entram atras do MESMO `ingress-nginx` por **prefixo de path** (o OS Service segue catch-all em `/`): `local.ingress_services` em `apim/main.tf` + `for_each` (nao copiei os blocos como nos dois primeiros) gera backends nomeados `billing`/`execucao` com URL `http://<ip>/billing` e `http://<ip>/execucao`, operacao coringa por metodo, policy com `set-backend-service` + `X-Forwarded-Proto/Host/Prefix` (`/billingserver`, `/execucaoserver`) e `product_api`. O Ingress de cada servico (repo do servico) casa o prefixo e remove com `rewrite-target`. **PENDENTE DE CONFIRMACAO no ambiente real**: a premissa de que a APIM concatena o path do backend com o path da operacao (nao da pra provar sem apply); se falhar, alternativa = backend so com o IP + `<rewrite-uri template="@(...)">` na policy (comentario em `apim/main.tf`). **Bloqueio de `/health/ready` e `/metrics`** (`docs/adr/0007`): a policy de cada API de negocio (`oficinamecanica` e as do `for_each` `ingress_services`) tem, logo apos o `<base />` e antes do `set-backend-service`, um guard (`apim/bloqueio-health-ready-e-metrics.xml`, lido com `file()` em `local.bloqueio_endpoints_internos` e incluido com `indent(4, ...)` - a APIM guarda uma policy por API, entao compus nas existentes em vez de criar recurso novo; a condicao segue a forma documentada, `condition` entre aspas duplas com as aspas do literal C# cruas, que o provider envia em `rawxml`, entao o fragmento NAO e XML estrito) que responde 404 sem corpo quando o FINAL do path (decodificado, minusculas, tolerante a barra final, `//` e `/.`; segmento `..` tambem vira 404; a query fica de fora porque `Url.Path` nao a inclui) e `/health/ready` ou `/metrics`. Testar o final do path e deliberado: nao depende de `Url.Path` vir com o prefixo da API nem da premissa de concatenacao acima. A expressao evita `<`, `>` e `&`. `/health` (liveness) segue exposto; o `segurancaserver` fica sem guard (so tem `/health`). Limitacao: quem acessa o IP do ingress direto nao e coberto. **Implementado, ainda nao aplicado, em duas etapas**: Billing e Execucao recebem o guard sempre; o `oficinaserver` (OS Service, em producao) so quando `var.bloquear_endpoints_internos_no_oficinaserver` for true (`default = false`; com false o texto da policy dele fica identico ao de antes, o plan nao muda), porque policy expression so e verificada em execucao e um erro derrubaria a API do OS (o merge aplica `-auto-approve`). Depois do primeiro apply, conferir `/billingserver/health/ready` e `/execucaoserver/metrics` (404), `/billingserver/health` (200) e rotas normais/webhook inalterados; so entao trocar o default para true via PR (o CI nao le .tfvars) e aplicar de novo (lista completa no ADR 0007). Testes locais, sem Azure: `python -I docs/apim/testar_bloqueio_health_ready_e_metrics.py` (condicao; roda no job `validate` do CI) e `apim/tests/bloqueio.tftest.hcl` (`terraform test` com providers simulados, rodar numa copia de `apim/`). O webhook do Mercado Pago entra anonimo por `https://<apim>.azure-api.net/billingserver/webhooks/mercadopago` (`terraform output mercadopago_webhook_url`). A API `grafana` (path `/grafana`, backend/operations/policy/product_api proprios) existiu aqui e foi removida junto com o Grafana do cluster (ver bullet `helm/` acima) — o Grafana e o resto do stack antigo foram substituidos pelo New Relic, cujo acesso e direto (SaaS, fora da APIM).

  A policy da API `oficinamecanica` injeta os headers de proxy que o backend precisa pra saber que esta atras de um gateway publico: `X-Forwarded-Proto: https`, `X-Forwarded-Host: <apim>.azure-api.net` e `X-Forwarded-Prefix: /oficinaserver`. `ingress-nginx` precisa de `use-forwarded-headers: true` (`helm/`, acima) pra nao descartar esses headers e preenche-los sozinho — esse foi o bug raiz por tras do `servers[]` do Swagger aparecendo com o IP interno em vez do host publico da APIM. O lado aplicacao (`Program.cs` do repo `OficinaMecanica`) le esses headers via `ForwardedHeadersMiddleware` + middleware customizado pra `X-Forwarded-Prefix`. A policy do `seguranca` e diferente: usa `X-Gateway-Proto`/`X-Gateway-Host`/`X-Gateway-Prefix` (nomes proprios, NAO `X-Forwarded-*`) porque o App Service intercepta e descarta silenciosamente qualquer header client-supplied comecando com `X-Forwarded-` antes de chegar no worker isolado (confirmado na pratica) — o `ServerBasePathDocumentFilter.cs` (repo `OficinaMecanica.Seguranca`) le esses headers `X-Gateway-*` pra montar o `servers[]` do OpenAPI e o redirect da raiz com a URL publica certa da APIM.

## Banco de Dados (OficinaMecanica.Banco)

O SQL Server (`svsfiap`) e os 3 bancos (`OficinaMecanicaDb`, `SegurancaDb`,
`BillingDb`) foram extraidos pro repositorio irmao `OficinaMecanica.Banco` (state proprio,
mesma storage account/container do tfstate deste repo — `stfiap`/`tfstate`,
so a key e diferente: `banco.tfstate`). Diferente da propria migracao deste
repositorio (que foi so realocacao de arquivos, mesmo backend/state), essa
foi uma divisao de verdade: os recursos ja existiam de verdade no Azure e
foram movidos de state via `terraform state rm` (aqui) + `terraform import`
(no `OficinaMecanica.Banco`), sem destruir/recriar nada — confirmado via
`terraform plan` vazio nos dois repos apos a migracao.

Esse repositorio **nao referencia** o state do `OficinaMecanica.Banco`
(nada de `terraform_remote_state`, acoplamento forte entre os dois states) —
`keyvault_secrets.tf`/`seguranca_keyvault.tf`/`billing_keyvault.tf` so
precisam do FQDN do servidor (previsivel: `<nome>.database.windows.net`) e
dos nomes dos bancos pra montar as connection strings, entao
`sql_server_name`/`sql_database_name`/`seguranca_database_name`/
`billing_database_name` e os logins/senhas dos usuarios dedicados
(`sql_app_os_login`/`_password`, `sql_app_seguranca_login`/`_password`,
`sql_app_billing_login`/`_password`) existem aqui como variaveis simples
("fatos conhecidos" sobre um recurso que este repo nao gerencia mais) — mesmo padrao ja usado pro Key Vault (`key_vault_uri` montado a
partir de `var.key_vault_name` em `functionapp/main.tf`, nao de um output
de modulo).

**Usuario SQL dedicado por banco (`docs/adr/0005`)**: as apps NUNCA usam o
admin do servidor. O Banco cria usuarios contidos (`app_os` em
`OficinaMecanicaDb`, `app_seguranca` em `SegurancaDb`, `app_billing` em
`BillingDb`, `db_owner` so no proprio banco) e este repo monta as
connection strings do Key Vault com eles. As senhas sao variaveis sensiveis
(`sql_app_os_password`, `sql_app_seguranca_password`,
`sql_app_billing_password` - mesmos nomes nos dois repos, validacao: >= 8
caracteres, sem `;` nem aspas). `sql_administrator_login`/`_password` foram
**removidas** daqui (nada mais as usa; um `sql_administrator_login` sobrando
num `terraform.tfvars` local so gera aviso de variavel nao declarada). O
SQL Server logico continua compartilhado por desenho e por restricao da
assinatura Azure for Students.

**Ordem de aplicacao: Banco ANTES do Infra.** O merge de um PR em `release`/`main` dispara `terraform apply -auto-approve` automaticamente (job `apply` do CI). Mergear o PR do Infra ANTES de o Banco ter criado os usuarios dedicados troca as connection strings do Key Vault por logins que ainda nao existem e derruba o OS Service e o Seguranca - a ordem Banco -> Infra vale tambem pro merge.
Depois do apply, `kubectl rollout restart` no OS Service (le o secret via
`secretKeyRef`, so no start) e reinicio da Function App.

Bootstrap do secret do Mongo, em ordem: (1) aplicar o Banco LOCALMENTE a
primeira vez com o admin humano (tem Key Vault Administrator), que cria o
secret `execucao-mongo-connection-string`; (2) so depois o apply do Infra
cria a role `Key Vault Secrets Officer` do `github_oidc_banco`, escopada nesse
secret (o `github_oidc_infra` so tem `Contributor`, que nao cria role
assignment: se o CI der `AuthorizationFailed`, aplicar este passo localmente
com o admin humano); (3) dai em diante o CI do Banco funciona. Se o ARM recusar o escopo
de secret inexistente/criado por outro repo, o apply do Infra falha nessa role
sem destruir nada - reordenar (Banco local primeiro) e reaplicar.

Cinco arquivos na raiz (nao dentro de nenhum modulo) conectam modulos entre si
sem criar dependencia circular — cada um precisa ver outputs de dois (ou mais)
modulos ao mesmo tempo, o que so e possivel na raiz (modulos nunca "olham de
volta" pra quem os chama):
- **`keyvault_secrets.tf`**: o `azurerm_key_vault_secret` da aplicacao do OS Service (`sql-connection-string`, montado a partir de `var.sql_server_name`/`var.sql_database_name` com o usuario dedicado `app_os` — ver secao sobre `OficinaMecanica.Banco` acima pra saber por que nao e mais `module.sqldb.*` nem o admin) — `jwt-secret-key`/`admin-senha` existiam aqui antes e foram removidos junto com a migracao da autenticacao pro `OficinaMecanica.Seguranca` (ver `functionapp/`/`seguranca_keyvault.tf`)
- **`aks_keyvault_access.tf`**: a role assignment `Key Vault Secrets User` pra identidade do addon CSI do `aks` no `keyvault` — nenhum dos dois modulos referencia o outro diretamente. Sem nenhum `data "azurerm_public_ip"` aqui: com o Key Vault em RBAC puro (`network_acls.default_action = "Allow"`, ver bullet `keyvault/` acima), essa role assignment e o unico portao de acesso que o addon CSI precisa
- **`seguranca_keyvault.tf`**: recursos do `OficinaMecanica.Seguranca` no mesmo Key Vault (`kvfiap`) — a chave `azurerm_key_vault_key` RSA-2048 (`seguranca-rs256`, usada pra assinar/verificar JWT RS256 remotamente via `CryptographyClient`, a chave privada nunca sai do vault) e os secrets `seguranca-sql-connection-string` (usuario dedicado `app_seguranca`)/`seguranca-seed-admin-senha`, mais as role assignments `Key Vault Crypto User` (so na chave) e `Key Vault Secrets User` (no vault inteiro) pra managed identity da Function App (`module.functionapp`)
- **`billing_keyvault.tf`**: secrets do `OficinaMecanica.Billing` - `billing-sql-connection-string` (usuario `app_billing`, banco `BillingDb`), `mercadopago-access-token` e `mercadopago-webhook-secret` (variaveis sensiveis; valores reais so via `TF_VAR_*` no CI/ambiente local, nunca em arquivo versionado)
- **`messaging_keyvault.tf`**: `random_password.rabbitmq` (32 alfanumericos, sem especiais pra nao exigir percent-encoding em URI AMQP; provider `random` em `versions.tf`, lock commitado como o resto) e os secrets `rabbitmq-username`/`rabbitmq-password` - a mesma senha vai pro Secret nativo do namespace `messaging` (modulo `helm`) e pro Key Vault (de onde as apps de outros namespaces leem via CSI). `execucao-mongo-connection-string` NAO e criado aqui (ver `github_oidc_banco` acima)

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

Comandos do Terraform sempre a partir da raiz deste repositorio como
working directory, tanto rodando manualmente quanto via CI/CD.

## CI/CD

**Protecao de branch**: o ruleset `protect-main-release` (so `main` e `release`: sem apagar nem force-push, PR
obrigatorio e o check `Terraform Validate` exigido; sem bypass) ja esta ATIVO no GitHub e o arquivo versionado
`.github/rulesets/protect-main-release.json` e equivalente a ele. Nao ha script para aplicar: se precisar recriar ou
alterar, use a GitHub CLI com esse arquivo (`gh api --method PUT repos/willianrmattos/OficinaMecanica.Infra/rulesets/<id> --input
.github/rulesets/protect-main-release.json`; o `<id>` sai de `gh api repos/willianrmattos/OficinaMecanica.Infra/rulesets`).

`.github/workflows/ci.yml` automatiza `plan`/`apply` desta propria infra via
GitHub OIDC (`github_oidc_infra/`, identidade unica cobrindo os dois): job
`validate` (`fmt -check` + `validate` + `plan -lock=false`) roda em todo
PR/push contra `main`/`release`; job `apply` (`terraform apply -auto-approve`)
so em push/disparo manual nessas branches (**merge de PR em release/main = apply automatico**: mergear o Infra antes do Banco troca as connection strings por logins inexistentes). Os dois jobs leem os GitHub
Secrets `TF_VAR_*` (precisam existir antes do PR/merge, senao a validacao
das variaveis derruba o plan): `TF_VAR_SQL_APP_OS_PASSWORD`,
`TF_VAR_SQL_APP_SEGURANCA_PASSWORD`, `TF_VAR_SQL_APP_BILLING_PASSWORD`,
`TF_VAR_MERCADOPAGO_ACCESS_TOKEN`, `TF_VAR_MERCADOPAGO_WEBHOOK_SECRET`
(novos) mais `TF_VAR_APIM_PUBLISHER_EMAIL`, `TF_VAR_SEGURANCA_SEED_ADMIN_SENHA`,
`TF_VAR_SEGURANCA_SEED_ADMIN_CPF`, `TF_VAR_NEWRELIC_LICENSE_KEY` (existentes).
`TF_VAR_SQL_ADMINISTRATOR_LOGIN_PASSWORD` deixou de ser usado. Atencao:
`github_oidc_infra` tem so `Contributor` no resource group, que nao cria role
assignments - se o apply do CI der `AuthorizationFailed` nas roles novas,
aplicar localmente (ou dar `Role Based Access Control Administrator` a ele).
O deploy da *aplicacao* (nao da
infra) e automatizado nos repositorios `OficinaMecanica`/
`OficinaMecanica.Seguranca`, ver o `CLAUDE.md` de cada um, secao "CI/CD".

## Comandos Uteis

```bash
terraform init
terraform plan
terraform apply
terraform output
terraform output -raw apim_gateway_url
```

Isso e pra rodar manualmente/localmente - ver secao "CI/CD" acima pra como
isso ja roda automaticamente.
