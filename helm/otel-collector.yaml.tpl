mode: deployment
replicaCount: 1

# Versao recente do chart nao tem mais default sensato pra imagem - exige
# explicito. Imagem "core" (nao "-contrib") basta: uso so otlp/batch/otlphttp,
# todos componentes do core, sem nenhum receiver/exporter exclusivo do contrib.
image:
  repository: otel/opentelemetry-collector

# Node unico, sem motivo pra HA de um gateway stateless (perder um lote de
# telemetria em restart nao e critico, diferente de um servico de negocio).
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    memory: 256Mi

extraEnvs:
  - name: NEW_RELIC_LICENSE_KEY
    valueFrom:
      secretKeyRef:
        name: ${secret_name}
        key: license-key

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch: {}
  exporters:
    # Exporter generico "otlphttp" - a New Relic aceita OTLP padrao, sem
    # exporter/extensao propria (so o header api-key abaixo pra autenticar).
    otlphttp/newrelic:
      endpoint: ${newrelic_otlp_endpoint}
      headers:
        api-key: $${env:NEW_RELIC_LICENSE_KEY}
      compression: gzip
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [otlphttp/newrelic]
      metrics:
        receivers: [otlp]
        processors: [batch]
        exporters: [otlphttp/newrelic]
      logs:
        receivers: [otlp]
        processors: [batch]
        exporters: [otlphttp/newrelic]
