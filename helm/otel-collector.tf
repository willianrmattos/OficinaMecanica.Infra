# Namespace criado explicitamente (nao via create_namespace=true de um dos
# helm_release) porque o kubernetes_secret abaixo precisa que o namespace ja
# exista antes dele - evita a ambiguidade de depender do create_namespace
# implicito de um helm_release especifico.
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

# Unico Secret nativo com a license key - referenciado tanto pelo Collector
# (env var, abaixo) quanto pelo nri-bundle (helm/newrelic.tf, via
# global.customSecretName/customSecretLicenseKey). Nao sincronizado via CSI
# Secrets Store: o Terraform ja tem o valor em maos (var.newrelic_license_key),
# sem necessidade de ida-e-volta pelo Key Vault so pra esses dois consumidores
# dentro do proprio cluster.
resource "kubernetes_secret" "newrelic_license_key" {
  metadata {
    name      = "newrelic-license-key"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    license-key = var.newrelic_license_key
  }

  type = "Opaque"
}

# OpenTelemetry Collector como gateway dentro do cluster: recebe OTLP da API
# (traces/metricas/logs, Program.cs) e reexporta pra New Relic. Decisao
# deliberada de nao instalar o agente proprietario .NET da New Relic - se um
# dia trocar de backend de observabilidade, so mexe no exporter aqui, sem
# tocar no codigo da API.
resource "helm_release" "otel_collector" {
  name       = var.otel_collector_release_name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.otel_collector_chart_version

  values = [
    templatefile("${path.module}/otel-collector.yaml.tpl", {
      newrelic_otlp_endpoint = var.newrelic_otlp_endpoint
      secret_name            = kubernetes_secret.newrelic_license_key.metadata[0].name
    })
  ]
}
