output "release_name" {
  description = "Nome do Helm release criado."
  value       = helm_release.ingress_nginx.name
}

output "release_namespace" {
  description = "Namespace onde o ingress-nginx foi instalado."
  value       = helm_release.ingress_nginx.namespace
}

output "release_status" {
  description = "Status do Helm release."
  value       = helm_release.ingress_nginx.status
}

output "monitoring_namespace" {
  description = "Namespace onde o OpenTelemetry Collector e o nri-bundle foram instalados."
  value       = helm_release.otel_collector.namespace
}

output "messaging_namespace" {
  description = "Namespace onde o RabbitMQ foi instalado."
  value       = kubernetes_namespace.messaging.metadata[0].name
}

output "rabbitmq_host" {
  description = "Endereco interno (DNS do cluster) do RabbitMQ - usar como host do MassTransit nas aplicacoes do cluster."
  value       = "${kubernetes_service_v1.rabbitmq.metadata[0].name}.${kubernetes_namespace.messaging.metadata[0].name}.svc.cluster.local"
}

output "rabbitmq_amqp_port" {
  description = "Porta AMQP do RabbitMQ (Service ClusterIP)."
  value       = 5672
}
