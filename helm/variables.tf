variable "release_name" {
  description = "Nome do Helm release."
  type        = string
  default     = "ingress-nginx"
}

variable "namespace" {
  description = "Namespace onde o ingress-nginx sera instalado."
  type        = string
  default     = "ingress-nginx"
}

variable "chart_version" {
  description = "Versao do chart ingress-nginx. Fixei na versao instalada (confirmada via `helm list -n ingress-nginx`) para evitar drift silencioso - sem isso, o Terraform reconsultaria o 'latest' do repositorio a cada plan e poderia propor upgrade automaticamente."
  type        = string
  default     = "4.15.1"
}

variable "monitoring_namespace" {
  description = "Namespace onde o OpenTelemetry Collector e o nri-bundle (integracao Kubernetes da New Relic) sao instalados. Antes tambem era o namespace do Prometheus/Grafana/Loki/Alloy (removidos - ver historico do repositorio)."
  type        = string
  default     = "monitoring"
}

variable "otel_collector_release_name" {
  description = "Nome do Helm release do OpenTelemetry Collector."
  type        = string
  default     = "otel-collector"
}

variable "otel_collector_chart_version" {
  description = "Versao do chart opentelemetry-collector (repositorio open-telemetry/opentelemetry-helm-charts). Fixada de proposito, mesmo motivo do chart_version do ingress-nginx - reconferir a versao estavel atual antes do primeiro apply."
  type        = string
  default     = "0.172.0"
}

variable "newrelic_release_name" {
  description = "Nome do Helm release do nri-bundle (integracao de Kubernetes da New Relic - CPU/memoria de pods/nodes)."
  type        = string
  default     = "newrelic"
}

variable "newrelic_chart_version" {
  description = "Versao do chart nri-bundle (repositorio helm-charts.newrelic.com). Fixada de proposito, mesmo motivo do chart_version do ingress-nginx."
  type        = string
  default     = "8.0.20"
}

variable "newrelic_license_key" {
  description = "License Key da New Relic - repassada do var.newrelic_license_key da raiz, guardada num kubernetes_secret proprio (helm/otel-collector.tf) pro Collector e o nri-bundle referenciarem sem texto plano no values do Helm."
  type        = string
  sensitive   = true
}

variable "newrelic_otlp_endpoint" {
  description = "Endpoint OTLP da New Relic pro qual o Collector reexporta. Default e a regiao US (otlp.nr-data.net) - trocar para https://otlp.eu01.nr-data.net se a conta for da regiao EU."
  type        = string
  default     = "https://otlp.nr-data.net"
}

variable "messaging_namespace" {
  description = "Namespace proprio do broker de mensageria (RabbitMQ), separado das aplicacoes (default) e da observabilidade (monitoring). O endereco interno resultante e rabbitmq.<namespace>.svc.cluster.local:5672."
  type        = string
  default     = "messaging"
}

variable "rabbitmq_image_tag" {
  description = "Tag da imagem OFICIAL do Docker Hub (rabbitmq:<tag>), variante -management (inclui o painel e a API de gerenciamento). Fixada de proposito numa 4.x exata, mesmo motivo do chart_version do ingress-nginx: sem isso um pull futuro traria outra versao sem passar por um plan. Nao usar charts/imagens Bitnami (catalogo virou pago). Alinhada com a versao dos composes, do Testcontainers e do e2e dos servicos (4.4.0) e conferida com o securityContext e a configuracao deste StatefulSet (docs/adr/0004). Reconferir a tag estavel mais recente antes do primeiro apply."
  type        = string
  default     = "4.4.0-management"
}

variable "rabbitmq_username" {
  description = "Usuario administrativo do broker, criado no primeiro boot do RabbitMQ (RABBITMQ_DEFAULT_USER). Repassado do var.rabbitmq_username da raiz, que tambem o guarda no Key Vault pra as aplicacoes lerem."
  type        = string
}

variable "rabbitmq_password" {
  description = "Senha do usuario administrativo do broker - gerada por random_password na raiz (messaging_keyvault.tf), guardada num kubernetes_secret proprio (helm/rabbitmq.tf) e referenciada pelo StatefulSet via secretKeyRef, sem texto plano no manifesto."
  type        = string
  sensitive   = true
}

variable "rabbitmq_storage_size" {
  description = "Tamanho do PersistentVolumeClaim (Azure Disk) que guarda os dados do RabbitMQ. Pequeno de proposito: o broker so carrega as mensagens em transito da Saga. Mudar este valor depois do primeiro apply nao redimensiona o disco: o volumeClaimTemplates de um StatefulSet e imutavel e a API do Kubernetes rejeita a alteracao. Aumentar exige patch manual no PVC existente (kubectl -n messaging patch pvc data-rabbitmq-0; a StorageClass managed-csi permite expansao); diminuir nao e possivel."
  type        = string
  default     = "2Gi"
}

variable "rabbitmq_storage_class_name" {
  description = "StorageClass do PVC do RabbitMQ. managed-csi e a classe do driver CSI de Azure Disk do AKS (StandardSSD_LRS), explicita pra nao depender de qual classe esta marcada como padrao no cluster."
  type        = string
  default     = "managed-csi"
}
