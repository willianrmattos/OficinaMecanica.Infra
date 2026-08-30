# global.customSecretName/customSecretLicenseKey referenciam o Secret ja
# criado em otel-collector.tf (kubernetes_secret.newrelic_license_key) -
# evita expor a license key em texto plano aqui ou no values do Helm.
global:
  cluster: aksfiap
  customSecretName: ${secret_name}
  customSecretLicenseKey: license-key
  lowDataMode: true

newrelic-infrastructure:
  enabled: true

# Correlacao K8s<->APM nao e necessaria agora (nao estamos usando o agente
# proprietario da New Relic, so o OTel Collector) - desabilitado pra reduzir
# footprint no node unico.
nri-metadata-injection:
  enabled: false

# Explicito (mesmo sendo o default do chart) porque nao ha mais nenhum
# kube-state-metrics concorrente no cluster.
kube-state-metrics:
  enabled: true
