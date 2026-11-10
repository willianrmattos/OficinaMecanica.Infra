# ADR 0004: RabbitMQ no AKS via StatefulSet com imagem oficial

## Status
Aceito

## Contexto
A migracao do monolito para microsservicos (OS Service, Billing, Execucao)
usa uma Saga orquestrada sobre MassTransit, o que exige um broker de
mensagens compartilhado entre os tres servicos. O projeto fixou RabbitMQ
como broker. Ele precisa rodar no mesmo cluster AKS dos servicos (sem IP
publico, sem custo adicional de servico gerenciado), dentro das restricoes
ja documentadas no ADR 0003: **no unico** `Standard_D4as_v4`, sem CPU
sobrando, assinatura Azure for Students.

Os caminhos usuais pra instalar RabbitMQ em Kubernetes esbarram em algo:
os charts Helm da Bitnami (o mais usado) deixaram de ter imagens gratuitas
atualizadas, e o operador oficial (Cluster Operator) acrescenta um
controller e CRDs a um no que ja nao tem folga.

## Decisao
RabbitMQ roda como **`kubernetes_stateful_set_v1` de 1 replica**, escrito
no Terraform (`helm/rabbitmq.tf`, mesmo modulo `helm/` que ja guarda o
`ingress-nginx` e a observabilidade), usando a **imagem oficial do Docker
Hub** `rabbitmq:<tag-4.x>-management` com **tag exata fixada** em
`helm/variables.tf` (`rabbitmq_image_tag`):

- Namespace proprio `messaging`; endereco interno
  `rabbitmq.messaging.svc.cluster.local:5672` (Service `ClusterIP`: 5672
  AMQP, 15672 management, 15692 metricas Prometheus). Sem Ingress e sem
  LoadBalancer: o painel so e acessado por `kubectl port-forward`.
- Persistencia: PVC pequeno (2Gi, `managed-csi`) com retencao `Retain`.
- Recursos baixos de proposito: requests 100m/256Mi, limits 500m/512Mi, com
  `vm_memory_high_watermark.absolute` alinhado ao limite.
- Seguranca do pod: nao-root (uid/gid 999, o usuario da propria imagem),
  `fsGroup`, `allowPrivilegeEscalation: false`, `capabilities drop ALL`,
  seccomp `RuntimeDefault`, `automountServiceAccountToken: false`.
- Configuracao declarativa via ConfigMap (`conf.d` + `enabled_plugins` com
  `rabbitmq_management` e `rabbitmq_prometheus`).
- Credenciais: usuario `oficina` e senha de `random_password` (raiz),
  entregues ao broker por Secret nativo e gravadas no Key Vault como
  `rabbitmq-username`/`rabbitmq-password` pra os servicos lerem via CSI
  Secrets Store.
- Versao: **`4.4.0-management`**, a mesma dos `docker-compose` dos tres
  servicos, do Testcontainers (Execucao e OS Service usam a tag; o Billing
  fixa por digest, que e o de `4.4.0-management`) e do e2e do OS Service, pra
  o que os testes provam valer no cluster. Conferi a imagem com o
  `securityContext` e a configuracao deste StatefulSet (uid 999, `capabilities
  drop ALL`, `no-new-privileges`, 512Mi e 0,5 CPU, `30-oficina.conf` e
  `enabled_plugins` extraidos do `rabbitmq.tf`): sobe em cerca de 12 s, aplica
  `vm_memory_high_watermark.absolute = 300MB` e `disk_free_limit.absolute =
  256MB`, o management (15672) e as metricas Prometheus (15692) respondem, o
  liveness `rabbitmq-diagnostics -q ping` leva poucos segundos (limite de 15 s)
  e uma fila duravel aceita publish e get. Todos os parametros do
  `30-oficina.conf` foram aceitos na 4.4.0, sem aviso de chave desconhecida.
  Nada foi aplicado no cluster, entao nao ha upgrade de dados em andamento.

## Consequencias
### Positivas
- Imagem oficial e mantida pelo projeto RabbitMQ; sem dependencia de
  chart/repositorio de terceiros que mude de licenca.
- Custo zero adicional e footprint pequeno (um unico pod), coerente com o
  no unico.
- Tudo versionado e revisavel em Terraform, sem operador nem CRDs; upgrade
  de versao e uma troca de tag com `plan` visivel.

### Negativas
- **Ponto unico de falha**: 1 no, sem quorum/cluster. Um restart do pod
  indisponibiliza a mensageria por alguns segundos/minutos; o PVC preserva
  filas e mensagens duraveis, mas nao ha alta disponibilidade.
- A senha so vale no **primeiro boot** (diretorio de dados vazio): trocar o
  Secret depois nao altera o usuario ja persistido. Rotacao exige
  `rabbitmqctl change_password` alem do `terraform apply -replace`.
- Um unico usuario (`oficina`) compartilhado pelos tres servicos: sem
  isolamento por usuario/vhost entre eles. Evolucao possivel: um usuario e
  um vhost por servico.
- O cluster nao tem motor de NetworkPolicy habilitado: qualquer pod alcanca
  o broker e so a credencial o protege.
- O AMQP no cluster e **sem TLS**: os servicos falam com o broker em texto
  claro por um `ClusterIP` interno (sem Ingress nem LoadBalancer). Aceito pelo
  mesmo motivo do no unico sem folga; TLS no listener 5672 e evolucao futura.
- A 4.4 registra no log que `management_metrics_collection` (habilitado pelo
  plugin de management) e um recurso deprecated: ainda funciona, mas uma
  minor futura pode deixar de permiti-lo por padrao, e entao seria preciso
  `deprecated_features.permit.management_metrics_collection = true` no
  `30-oficina.conf`. Vale reler o aviso a cada troca de tag.
- Capacidade: 100m de CPU request precisam caber no no (ver ADR 0003) -
  conferir `kubectl describe node` antes do apply; com o pod `Pending` o
  apply espera o rollout e falha por tempo.
- Pendencias aceitas no pod: sem `readOnlyRootFilesystem` (a imagem escreve
  fora do PVC) e limite de 500m de CPU pode causar throttling nos schedulers
  do Erlang sob rajada (nao medido; ajustar `+S` ou o limite se aparecer
  latencia). A config entra por `subPath` (nao atualiza sozinha), entao o pod
  carrega a annotation `checksum/config` pra uma mudanca de config recriar o
  pod. `fsGroupChangePolicy: OnRootMismatch` evita que o kubelet reaplique
  permissoes no PVC a cada montagem e deixe o `.erlang.cookie` com modo que o
  Erlang recusa.
- Probes de readiness por TCP (barato) em vez de `rabbitmq-diagnostics`;
  metricas Prometheus estao habilitadas, mas o OpenTelemetry Collector
  ainda nao as coleta (pendente).
- Pull anonimo do Docker Hub sujeito a limite de taxa; fixar por digest ou
  espelhar no ACR e uma melhoria futura.

## Alternativas consideradas
- **Chart Helm da Bitnami**: era a opcao mais simples, mas as imagens
  gratuitas atualizadas foram descontinuadas e o catalogo virou pago.
- **RabbitMQ Cluster Operator (oficial) + CRD `RabbitmqCluster`**: mais
  idiomatico e com HA possivel, mas adiciona controller/CRDs a um no sem
  folga, excessivo pra 1 replica.
- **Azure Service Bus (gerenciado)**: sem operacao propria, mas tem custo
  fixo no tier que suporta topicos e o projeto ja fixou RabbitMQ/MassTransit.
- **RabbitMQ como SaaS externo**: dependencia de terceiro, plano gratuito
  limitado e mais uma credencial externa.
