# ADR 0007: Bloqueio de `/health/ready` e `/metrics` na APIM

## Status
Aceito. Implementado em `apim/` (policy + `file()` em `apim/main.tf`); **ainda
nao aplicado**: entra em vigor no primeiro `terraform apply` deste repositorio
(merge em `release`/`main` aplica pelo CI), **em duas etapas**: Billing e
Execucao ja no primeiro apply; o `oficinaserver` (OS Service, em producao) so
quando `bloquear_endpoints_internos_no_oficinaserver` for `true`. Ver "Rollout
em duas etapas" e "Confirmar depois do apply".

## Contexto
Os tres servicos de negocio (OS Service, Billing, Execucao) expoem tres
endpoints de infraestrutura, todos **anonimos** (`MapHealthChecks`/`MapMetrics`,
fora do MVC, sem `[Authorize]`):

| Endpoint | O que faz |
|----------|-----------|
| `/health` | liveness: so confirma que o processo esta de pe, sem tocar em dependencias |
| `/health/ready` | prontidao: abre conexao com o banco (SQL Server ou MongoDB) e com o RabbitMQ; o corpo traz nome e status dos checks. O servico guarda o resultado por 5 s (`Health__ProntidaoCacheSegundos`), o que limita o custo, mas nao esconde o endpoint |
| `/metrics` | metricas no formato Prometheus (`prometheus-net`): contadores HTTP e nomes de rota |

As rotas da APIM `oficinaserver` (catch-all `/`), `billingserver` (`/billing`) e
`execucaoserver` (`/execucao`) usam a operacao coringa `/*` ([ADR 0002](0002-apim-gateway-na-frente-do-ingress-nginx.md)):
repassam **qualquer** path ao backend. Resultado: a internet chega a
`/oficinaserver/health/ready`, `/billingserver/metrics` etc.

Nada legitimo precisa desses dois paths pela APIM: as probes do kubelet batem
direto no IP do pod (nunca passam pela APIM), a telemetria sai por push (OTLP
para o OpenTelemetry Collector) e o Prometheus local do `docker-compose` fala
direto com a API.

O `OficinaMecanica.Seguranca` (Function App) so tem `/health` (`HealthFunction`,
`{"status":"ok"}`, sem dependencias); nao tem `/health/ready` nem `/metrics`, e a
rota catch-all `Root` devolve 404 para qualquer path desconhecido.

## Decisao
- Uma policy no escopo **da API**, secao `inbound`, nas tres APIs de negocio,
  logo depois do `<base />` e antes do `set-backend-service`: `choose/when` +
  `return-response` com **404 sem corpo** quando o final do path e
  `/health/ready` ou `/metrics`. O backend nem e chamado.
- O XML mora num arquivo so, `apim/bloqueio-health-ready-e-metrics.xml`, lido
  com `file()` num `local` (`bloqueio_endpoints_internos`) e incluido com
  `indent(4, ...)` nas duas policies que ja existiam: a do `for_each`
  `ingress_services` (Billing e Execucao, **sempre**; um servico novo no mapa
  herda o guard) e a de `azurerm_api_management_api_policy.oficinamecanica`
  (`oficinaserver`, **so com a variavel ligada**, ver o proximo item). Nao criei
  recurso de policy novo: a APIM guarda **uma** policy por API, entao o guard foi
  composto nas existentes, que mantem `<base />`, `set-backend-service` e os
  headers `X-Forwarded-*` sem alteracao.
- **Rollout em duas etapas** (`bloquear_endpoints_internos_no_oficinaserver`,
  `default = false`, em `variables.tf` da raiz e de `apim/`). Uma policy expression
  so e validada em execucao: um erro nela derrubaria (HTTP 500) todas as rotas da
  API. Billing e Execucao ainda nao tem trafego em producao e recebem o guard ja no
  primeiro apply, que assim prova a expressao numa API que pode falhar sem custo.
  O `oficinaserver` e a API do OS Service em producao e o merge aplica
  `-auto-approve`: com a variavel em `false` o texto da policy dele fica
  **identico** ao de antes do guard (o `terraform test` em `apim/tests/` confere o
  texto ao redor do `<base />`; a comparacao byte a byte com o `HEAD` por sha256
  tambem passou), entao o plan nao propoe mudanca nela. Depois de conferir o
  bloqueio nas APIs novas, o dono troca o default para `true` (via PR: o CI nao le
  `.tfvars`) e um novo apply liga o guard no `oficinaserver`. Reversao: voltar para
  `false` e aplicar.
- Condicao (C# na policy expression; o regex e aplicado ao path decodificado e em
  minusculas):

  ```
  Regex.IsMatch(System.Net.WebUtility.UrlDecode(context.Request.Url.Path).ToLowerInvariant(),
                @"/(health/(\.?/)*ready|metrics)(/\.?)*$|(^|/)\.\.(/|$)")
  ```

  - **Testa o FINAL do path**, nao um caminho completo. A documentacao da APIM nao
    diz se `context.Request.Url.Path` chega com o prefixo da API
    (`/billingserver/...`), e a premissa de que o path do backend (`/billing`) so
    e concatenado na requisicao ao backend (depois da secao `inbound`) tambem
    segue por confirmar. O final do path e o mesmo com ou sem prefixo, entao a
    condicao vale nos dois casos (inclusive para o `/` do `oficinaserver`).
  - A query string nao entra: a APIM expoe `Query`/`QueryString` separados de
    `Path`. `/health/ready?x=1` bloqueia; `/api/x?y=/health/ready` nao.
  - Sem distincao de maiusculas, com ou sem barra final, e tolerante a barras
    repetidas e a segmentos `.`. O `UrlDecode` existe porque o ingress-nginx e o
    ASP.NET Core normalizam o path **depois** da APIM: sem decodificar,
    `/health/%72eady` e `/health%2Fready` passariam e chegariam ao pod como
    `/health/ready`.
  - Um segmento `..` (depois de decodificar) tambem responde 404: sem isso,
    `/health/x/../ready` passaria se a normalizacao so acontecesse depois da
    APIM. E o unico efeito do guard fora desses dois endpoints (ver Consequencias).
  - O padrao nao tem quantificadores aninhados e ancora o inicio em `/health` ou
    `/metrics`, entao o custo e linear no tamanho do path (sem backtracking
    explosivo); um path de 8 mil caracteres de `/` e `.` leva alguns
    milissegundos no teste local.
  - A condicao segue a **forma documentada**: atributo `condition` entre aspas
    duplas, com as aspas do literal C# cruas dentro dele, como nos exemplos do
    `choose` e das *policy expressions* da documentacao e nos snippets oficiais
    (`Azure/api-management-policy-snippets`). O provider `azurerm` envia policies
    **so em formato `rawxml`**, que aceita isso; por isso o fragmento **nao e XML
    estrito**. Uma versao anterior usava aspas simples (XML estrito), mas nenhuma
    fonte oficial usa essa forma e nao ha como provar sem apply que a APIM a
    aceita sem reserializar. A expressao evita `<`, `>` e `&`, que seriam o mesmo
    problema.
  - Limite da validacao local: o teste extrai a expressao por texto e so passa o
    resto do fragmento por um parser XML estrito (escapando as aspas da
    expressao), e as policies compostas sao conferidas do mesmo jeito. Isso prova a
    estrutura (`choose/when/return-response`, guard depois do `<base />`), **nao**
    que a APIM aceita a expressao: a prova final e o primeiro apply em Billing e
    Execucao. A incerteza que sobra e especifica: a documentacao e os exemplos
    oficiais cobrem separadamente o atributo `condition` em aspas duplas com aspas
    internas cruas e o literal verbatim `@"..."` dentro de `@(...)`, mas nenhum
    exemplo oficial combina os dois na mesma expressao.
- **`/health` (liveness) continua exposto**: nao tem dependencias, responde so
  200 (corpo `Healthy` nos tres servicos, `{"status":"ok"}` no Seguranca) e e util
  como ping de disponibilidade e para conferir a concatenacao de path da APIM
  depois do deploy (`/billingserver/health`). Bloquea-lo nao protege nada e
  perderia essa verificacao.
- **`segurancaserver` fica de fora**: a Function so tem `/health` e nao tem
  `/health/ready` nem `/metrics` (ver Contexto); incluir o guard la seria codigo
  sem efeito. Se o Seguranca ganhar um desses endpoints, basta incluir o mesmo
  `local` na policy dele.
- Resposta **404 sem corpo**: parecida com a de um path que nao existe no backend
  (o ASP.NET Core responde 404 sem corpo por padrao) e nao confirma que o
  endpoint existe.
- Escopo de **API** e nao de produto/global: a documentacao da APIM avisa que
  policies de produto nao sao aplicadas a requisicoes feitas com assinatura
  all-access (chave de escopo "todas as APIs"), o que daria um jeito de contornar o
  guard; a policy de API vale para todas as operacoes sempre.
- O teste local da condicao fica em
  `docs/apim/testar_bloqueio_health_ready_e_metrics.py`: le o proprio fragmento,
  extrai o regex da expressao e confere 36 paths (bloqueia/repassa) e o custo em
  paths patologicos. Nao acessa a nuvem; o CI o roda no job `validate`. Localmente:
  `python -I docs/apim/testar_bloqueio_health_ready_e_metrics.py`.
- O rollout (variavel ligada/desligada, guard sempre em Billing/Execucao, nunca no
  Seguranca) e provado por `apim/tests/bloqueio.tftest.hcl`, um `terraform test` com
  providers simulados, sem nuvem (como rodar, no cabecalho do arquivo).

## Consequencias
### Positivas
- `/health/ready` (que abre conexao com banco e broker) e `/metrics` deixam de ser
  alcancaveis pela internet via APIM, sem mudar codigo dos servicos nem dos
  Ingress; as probes do Kubernetes seguem funcionando porque batem no pod.
- Uma regra, um arquivo, tres APIs; servico novo atras do `ingress-nginx` herda o
  guard ao entrar no `for_each`.
- Custo zero de infraestrutura nova: uma avaliacao de regex por requisicao.

### Negativas e limitacoes
- **Quem chega direto ao ingress/IP do cluster ainda alcanca os endpoints**
  (`http://<ip-do-ingress>/billing/health/ready`): o guard so cobre o caminho
  pela APIM. Fechar isso exige uma regra no proprio `ingress-nginx`/Ingress de cada
  servico ou restringir quem acessa o IP do LoadBalancer (o cluster nao tem motor
  de NetworkPolicy); fica como defesa em profundidade futura, nao feita aqui.
- **Rotas de negocio cujo path termine em `/health/ready` ou `/metrics`** passam a
  responder 404. Hoje nao existe nenhuma (so `MapHealthChecks`/`MapMetrics`
  respondem nesses paths nos tres servicos); criar uma exige ajustar o guard. Do
  mesmo modo, qualquer path com segmento `..` responde 404 (um cliente legitimo nunca
  envia esse segmento: ele e resolvido antes do envio).
- Requisicoes bloqueadas ainda sao chamadas da APIM e contam na cota gratuita do
  tier Consumption (1 milhao por mes); o guard protege o backend, nao a cota. Rate
  limiting na borda ficou fora do escopo.
- **A policy expression so e verificada de forma limitada ao definir a policy**
  (a documentacao diz que erros aparecem em execucao): um erro na expressao
  derrubaria (HTTP 500) **todas** as rotas das tres APIs, nao so os dois endpoints.
  Por isso a verificacao depois do primeiro apply abaixo e obrigatoria.
- Ao comparar a policy com o que a APIM devolve, o provider usa
  `XmlWithDotNetInterpolationsDiffSuppress`: tenta comparar os dois como XML
  (XmlDiff) e, se nao der, cai para uma normalizacao de espacos e entidades. O
  primeiro apply cria a policy sem diff; se a APIM devolver o texto reserializado,
  um `plan` **seguinte** pode mostrar diferenca nas policies com o guard, so
  cosmetica (o apply seguinte reescreve o mesmo conteudo).
- O `oficinaserver` continua com `/health/ready` e `/metrics` expostos ate a
  segunda etapa do rollout (e o estado de hoje): a protecao dele depende de um
  segundo PR e apply, que e esquecivel; a pendencia fica registrada aqui e no
  README.
- Nao ha teste automatizado contra uma APIM de verdade (sem apply, sem
  credenciais): o que foi provado e a estrutura do fragmento e das policies
  compostas, o `terraform validate` verde, o `terraform test` do rollout e a
  logica da condicao no teste local.

### Premissa que continua a confirmar
A concatenacao do path do backend (`http://<ip>/billing` + path da operacao) segue
pendente ([ADR 0002](0002-apim-gateway-na-frente-do-ingress-nginx.md) e README).
Este guard **nao depende dela** (testa so o final do path), entao nao a prova nem a
invalida. A documentacao do `set-backend-service` tem um exemplo coerente com a
premissa (`https://contoso.azure-api.net/api/partners/15` vira
`http://contoso.com/api/10.4/partners/15`, com a URL base do backend no lugar do
sufixo da API), mas o exemplo usa `base-url`, nao uma entidade de backend
(`backend-id`), entao nao encerra a duvida.

### Confirmar depois do apply
Com `<apim>` = `terraform output -raw apim_gateway_url`.

**Etapa 1, primeiro apply (`bloquear_endpoints_internos_no_oficinaserver = false`):**
o plan nao deve mostrar mudanca em `azurerm_api_management_api_policy.oficinamecanica`.

| Requisicao | Esperado |
|------------|----------|
| `GET <apim>/billingserver/health/ready?x=1`, `.../execucaoserver/health/ready`, `.../billingserver/metrics`, `.../execucaoserver/metrics`, `.../billingserver/health/%72eady` | 404 sem corpo |
| `GET <apim>/billingserver/health`, `.../execucaoserver/health`, `.../segurancaserver/health`, `.../oficinaserver/health` | 200 (o do Billing/Execucao tambem prova a concatenacao do path do backend) |
| Uma rota normal de Billing e de Execucao (com JWT) e o webhook `POST .../billingserver/webhooks/mercadopago` | inalterados (nao 404 do guard, nao 500) |
| `GET <apim>/oficinaserver/health/ready` | 200 (inalterado: o guard ainda nao esta ligado nessa API) |
| `kubectl get pods` | pods `Ready` (as probes batem direto no pod) |

**Etapa 2, ligar no `oficinaserver`:** so depois da etapa 1 conferida, trocar o
`default` de `bloquear_endpoints_internos_no_oficinaserver` para `true` em
`variables.tf` (via PR) e aplicar de novo.

| Requisicao | Esperado |
|------------|----------|
| `GET <apim>/oficinaserver/health/ready`, `.../oficinaserver/metrics` | 404 sem corpo |
| `GET <apim>/oficinaserver/health`, a Swagger UI (`/oficinaserver/index.html`), uma rota publica (consulta de OS por numero) e uma administrativa com JWT | inalterados |

Se alguma rota normal der 500 em qualquer etapa, o guard esta com erro de
expressao: na etapa 1, reverter o `file()` (ou o include) e reaplicar; na etapa 2,
voltar a variavel para `false` e aplicar.

## Alternativas consideradas
- **Bloquear no `ingress-nginx`** (regra no Ingress de cada servico ou snippet):
  cobriria tambem o acesso direto ao IP. Fica fora porque os Ingress moram nos
  repositorios dos servicos (tres lugares para manter a mesma regra, com este
  repositorio sem controle sobre eles) e os snippets de configuracao vem
  desabilitados por padrao nas versoes recentes do ingress-nginx (o chart fixado,
  4.15.1, nao altera isso). Continua valendo como camada adicional.
- **Nos servicos** (middleware que exige segredo/IP interno, ou autenticar os
  endpoints): mexe em codigo de tres repositorios, e as probes do kubelet e o
  Prometheus local precisariam passar; um 401/403 ainda confirma que o endpoint
  existe.
- **`ip-filter` na APIM** (permitir so IPs conhecidos): nenhum IP legitimo usa esses
  paths pela APIM, e a resposta (403) revelaria que o endpoint existe.
- **Policy de produto (`gateway`) ou global**: um lugar so, mas policy de produto
  nao vale para assinaturas all-access, e a global atingiria tambem o Seguranca sem
  necessidade.
- **Policy por operacao**: o modelo wildcard tem uma operacao por metodo HTTP
  (cinco por API); o escopo de API cobre todas com uma inclusao.
- **Curar operacoes em vez do wildcard** (so expor rotas conhecidas): perde o modelo
  passthrough sem manutencao por endpoint do ADR 0002.
- **Ligar o guard nas tres APIs ja no primeiro apply**: mais simples, mas um erro de
  expressao (so detectavel em execucao) derrubaria a API do OS Service em producao,
  com `-auto-approve` no merge. O rollout em duas etapas troca um segundo PR por
  essa seguranca.

## Referencias
Documentacao da APIM (Microsoft Learn): *policy expressions* (tipos permitidos:
`Regex`, `System.Net.WebUtility`; membros de `context.Request.Url`), `return-response`,
`choose` (exemplos com `condition` entre aspas duplas e aspas internas cruas),
*policies* (escopos e `<base />`), `set-backend-service`; repositorio
`Azure/api-management-policy-snippets`.
