# Prova, sem nuvem (providers simulados), que o guard de /health/ready e /metrics
# entra nas policies como o rollout em duas etapas pede: Billing e Execucao sempre,
# oficinaserver so com a variavel ligada, Seguranca nunca. Nao precisa de
# credenciais nem de cluster. Rodo numa copia da pasta, pra nao deixar
# .terraform nem lock dentro de apim/:
#   cp -r apim /tmp/apim-test && cd /tmp/apim-test
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {}

mock_provider "kubernetes" {
  mock_data "kubernetes_service" {
    defaults = {
      status = [{
        load_balancer = [{
          ingress = [{
            ip       = "10.1.2.3"
            hostname = ""
          }]
        }]
      }]
    }
  }
}

variables {
  location                   = "northcentralus"
  resource_group_name        = "rgfiap"
  publisher_email            = "dono@example.com"
  ingress_nginx_namespace    = "ingress-nginx"
  seguranca_backend_hostname = "func.azurewebsites.net"
}

run "variavel_desligada_por_padrao" {
  command = plan

  assert {
    condition     = !strcontains(azurerm_api_management_api_policy.oficinamecanica.xml_content, "<choose>")
    error_message = "oficinaserver nao deveria ter o guard com a variavel em false"
  }

  assert {
    condition     = strcontains(azurerm_api_management_api_policy.oficinamecanica.xml_content, "    <base />\n    <set-backend-service backend-id=\"ingress-nginx\" />")
    error_message = "com false, o texto ao redor do <base /> deveria ficar como era antes do guard"
  }

  assert {
    condition = alltrue([
      for k in ["billing", "execucao"] :
      strcontains(azurerm_api_management_api_policy.ingress_services[k].xml_content, "<return-response>")
      && strcontains(azurerm_api_management_api_policy.ingress_services[k].xml_content, "(health/(\\.?/)*ready|metrics)")
    ])
    error_message = "billing e execucao devem ter o guard sempre"
  }

  assert {
    condition     = !strcontains(azurerm_api_management_api_policy.seguranca.xml_content, "<choose>")
    error_message = "seguranca nao deve ter o guard"
  }
}

run "variavel_ligada" {
  command = plan

  variables {
    bloquear_endpoints_internos_no_oficinaserver = true
  }

  assert {
    condition     = strcontains(azurerm_api_management_api_policy.oficinamecanica.xml_content, "<choose>") && strcontains(azurerm_api_management_api_policy.oficinamecanica.xml_content, "<set-status code=\"404\"")
    error_message = "oficinaserver deveria ter o guard com a variavel em true"
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_api_policy.oficinamecanica.xml_content, "    <base />\n    <!-- Fragmento")
      && length(split("<choose>", azurerm_api_management_api_policy.oficinamecanica.xml_content)[0]) < length(split("<set-backend-service", azurerm_api_management_api_policy.oficinamecanica.xml_content)[0])
    )
    error_message = "o guard deve vir logo depois do <base /> e antes do set-backend-service"
  }

  assert {
    condition = alltrue([
      for k in ["billing", "execucao"] :
      strcontains(azurerm_api_management_api_policy.ingress_services[k].xml_content, "<return-response>")
    ])
    error_message = "billing e execucao devem ter o guard sempre"
  }

  assert {
    condition     = !strcontains(azurerm_api_management_api_policy.seguranca.xml_content, "<choose>")
    error_message = "seguranca nao deve ter o guard"
  }
}
