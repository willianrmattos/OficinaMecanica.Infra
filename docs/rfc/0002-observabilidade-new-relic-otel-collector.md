# RFC 0002: Observabilidade - New Relic + OpenTelemetry Collector

## Status
Aceito

## Resumo
O AKS de producao usa **New Relic** como backend de observabilidade
(tracing, metricas e logs), mas a aplicacao (`OficinaMecanica`) nunca fala
diretamente com a New Relic - ela exporta tudo via **OpenTelemetry (OTLP)**
para um **OpenTelemetry Collector** rodando no proprio cluster, que
reexporta para a New Relic. Nao ha agente proprietario da New Relic
instalado. O ambiente local (docker-compose) continua usando um stack
self-hosted (Prometheus, Grafana, Loki, Alloy, Jaeger), sem relacao com
este RFC.

## Motivacao
O requisito era monitorar latencia de APIs, consumo de recursos do
Kubernetes, healthchecks, alertas de falha e logs estruturados com
correlacao, alem de expor dashboards de negocio (volume de ordens de
servico, tempo medio por status, erros de integracao). O AKS ja tinha um
stack self-hosted completo (Prometheus + Grafana + Loki + Alloy + Jaeger)
rodando via Helm, mas o proprio requisito da avaliacao permitia trocar por
uma ferramenta de mercado como Datadog ou New Relic - e o cluster de nó
unico, sem CPU sobrando, se beneficia de nao precisar hospedar esse stack
inteiro (Prometheus, Grafana, Loki, Alloy e Jaeger juntos consomem uma
fatia relevante dos poucos recursos disponiveis).

## Proposta
Adotar New Relic como backend gerenciado (elimina a necessidade de manter
Prometheus/Grafana/Loki/Alloy/Jaeger rodando no cluster), mas **sem
acoplar a aplicacao a New Relic diretamente**: a instrumentacao usa o SDK
padrao do OpenTelemetry (tracing, metricas via `System.Diagnostics.Metrics`,
logs via Serilog) e exporta tudo via OTLP para um OpenTelemetry Collector
que roda dentro do proprio AKS. E o Collector - nao a aplicacao - quem sabe
que o destino final e a New Relic. Trocar de fornecedor de observabilidade
no futuro (por exemplo, pra Datadog) exigiria mudar so a configuracao do
Collector, nao o codigo da aplicacao.

Kubernetes (CPU/memoria de pods e nodes) e monitorado separadamente via
`nri-bundle`, a integracao oficial de Kubernetes da New Relic - unico
componente especifico da New Relic instalado no cluster, ja que essa
integracao nao tem um equivalente vendor-neutral direto no mesmo nivel de
profundidade.

## Alternativas consideradas
- **Datadog**: opcao igualmente valida citada no requisito original: nao
  foi escolhida porque a New Relic tinha um plano gratuito mais direto de
  configurar para o escopo deste projeto no momento da decisao.
- **Agente proprietario da New Relic (New Relic .NET Agent)**: mais simples
  de configurar (auto-instrumentacao), mas acopla a aplicacao diretamente
  ao formato/protocolo da New Relic. Rejeitado em favor do SDK OpenTelemetry
  padrao, justamente pela portabilidade de fornecedor.
- **Manter o stack self-hosted (Prometheus/Grafana/Loki/Alloy/Jaeger)**:
  funcionava, mas competia por CPU/memoria com a propria aplicacao no
  node unico do cluster, e exigia manter 5 componentes diferentes no ar.

## Decisao
New Relic como backend, OpenTelemetry Collector como camada de exportacao
(sem agente proprietario), `nri-bundle` para metricas de Kubernetes. Essa
decisao vale apenas para o AKS de producao - o docker-compose local
continua com o stack self-hosted original, sem necessidade de trocar
(nao compete por recursos escassos da mesma forma).
