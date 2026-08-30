# nri-bundle = integracao de Kubernetes da New Relic (CPU/memoria de pods e
# nodes) - parte separada do APM: independe da escolha de usar o
# OpenTelemetry Collector em vez do agente proprietario .NET (otel-collector.tf).
resource "helm_release" "newrelic" {
  name       = var.newrelic_release_name
  repository = "https://helm-charts.newrelic.com"
  chart      = "nri-bundle"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = var.newrelic_chart_version

  values = [
    templatefile("${path.module}/newrelic.yaml.tpl", {
      secret_name = kubernetes_secret.newrelic_license_key.metadata[0].name
    })
  ]

  # Namespace ja existe (kubernetes_namespace.monitoring, otel-collector.tf) -
  # sem essa dependencia explicita, o Terraform poderia tentar instalar os
  # dois helm_release deste modulo em paralelo antes do namespace/secret
  # existirem.
  depends_on = [kubernetes_secret.newrelic_license_key]
}
