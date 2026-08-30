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
