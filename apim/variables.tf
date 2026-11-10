variable "location" {
  description = "Regiao do Azure onde a APIM sera criada. Sempre fornecido pelo main.tf raiz (module.rg.location)."
  type        = string
}

variable "resource_group_name" {
  description = "Nome do resource group (modulo rg) onde a APIM sera criada. Sempre fornecido pelo main.tf raiz (module.rg.resource_group_name)."
  type        = string
}

variable "apim_name" {
  description = "Nome da instancia do API Management. Globalmente unico (vira <nome>.azure-api.net)."
  type        = string
  default     = "apimfiap"
}

variable "publisher_name" {
  description = "Nome do publisher exibido no portal da APIM."
  type        = string
  default     = "OficinaMecanica"
}

variable "publisher_email" {
  description = "E-mail do publisher (usado pela APIM para notificacoes). Sem valor padrao: definir via TF_VAR_apim_publisher_email ou um .tfvars nao versionado."
  type        = string
}

variable "ingress_nginx_namespace" {
  description = "Namespace onde o ingress-nginx foi instalado via Helm (modulo helm) - usado pra ler o IP publico do LoadBalancer via data source do Kubernetes."
  type        = string
}

variable "ingress_nginx_service_name" {
  description = "Nome do Service do controller do ingress-nginx (chart oficial cria com este nome por padrao)."
  type        = string
  default     = "ingress-nginx-controller"
}

variable "seguranca_backend_hostname" {
  description = "Hostname publico da Function App do OficinaMecanica.Seguranca (modulo functionapp, ex: <nome>.azurewebsites.net) - backend do path segurancaserver. Diferente de oficinamecanica, nao passa pelo ingress-nginx: a Function tem seu proprio endpoint HTTPS direto, sem AKS no meio."
  type        = string
}

variable "bloquear_endpoints_internos_no_oficinaserver" {
  description = "Liga (true) ou nao (false) o bloqueio de /health/ready e /metrics na policy da API oficinaserver (OS Service, em producao). Billing e Execucao, sem trafego em producao, sempre recebem o bloqueio. Deixei false de proposito: uma policy expression so e validada em execucao, e um erro nela derrubaria a API do OS; o primeiro apply so mexe nas APIs novas e, depois de conferir o bloqueio nelas (lista no docs/adr/0007), o valor passa a true via PR (o CI nao le .tfvars) e um novo apply liga."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
