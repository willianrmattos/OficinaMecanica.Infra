# Broker de mensageria da Saga (OS Service <-> Billing <-> Execucao, via
# MassTransit). Optei por StatefulSet escrito na mao com a imagem OFICIAL do
# Docker Hub (rabbitmq:<tag>-management) em vez de chart Helm: os charts
# Bitnami viraram pagos e o operador oficial (Cluster Operator) e pesado
# demais pra 1 no unico sem folga de CPU - ver docs/adr/0004. Namespace
# proprio ("messaging") pra o broker nao se misturar com as aplicacoes
# (namespace default) nem com observabilidade (monitoring).
#
# Endereco interno: rabbitmq.messaging.svc.cluster.local:5672. Sem Ingress
# nem LoadBalancer de proposito: o painel de management so e acessado por
# "kubectl -n messaging port-forward svc/rabbitmq 15672:15672".
resource "kubernetes_namespace" "messaging" {
  metadata {
    name = var.messaging_namespace
  }
}

locals {
  rabbitmq_labels = {
    "app.kubernetes.io/name"      = "rabbitmq"
    "app.kubernetes.io/component" = "messaging"
  }

  # Conteudo dos arquivos de configuracao num local (e nao inline no
  # ConfigMap) porque o mesmo valor alimenta o checksum/config do pod
  # template: arquivos montados por subPath NAO sao atualizados pelo kubelet
  # quando o ConfigMap muda, entao sem o checksum uma mudanca de config
  # aplicada pelo Terraform so valeria no proximo restart manual do pod.
  rabbitmq_config = {
    "30-oficina.conf" = <<-CONF
      # Watermark absoluto (nao relativo): nao depende da deteccao do limite
      # de memoria do cgroup, e 300MB dentro do limite de 512Mi do container
      # deixa folga pro GC do Erlang e pro CLI dos probes. O padrao relativo
      # (0.4) ficaria colado no consumo ocioso do broker com o management
      # ligado e dispararia o alarme de memoria (bloqueia publishers).
      vm_memory_high_watermark.absolute = 300MB
      disk_free_limit.absolute = 256MB

      # O 10-defaults.conf da imagem libera o guest pela rede; religo a
      # restricao a localhost caso o usuario guest exista (so existe se o
      # usuario padrao nao for trocado pelo RABBITMQ_DEFAULT_USER).
      loopback_users.guest = true

      log.console = true
      log.console.level = info

      management.tcp.port = 15672
      prometheus.tcp.port = 15692
    CONF

    # Lista explicita (com o ponto final, sintaxe de termo Erlang) pra nao
    # depender de qual plugin a imagem ja deixa habilitado.
    "enabled_plugins" = "[rabbitmq_management,rabbitmq_prometheus].\n"
  }
}

# Secret nativo montado direto pelo Terraform (o valor ja esta em maos, vindo
# do random_password da raiz) - mesmo raciocinio do Secret da license key da
# New Relic em otel-collector.tf: sem ida-e-volta por Key Vault/CSI pra um
# consumidor que vive no mesmo apply. As aplicacoes (outro namespace) leem
# as mesmas credenciais do Key Vault (rabbitmq-username/rabbitmq-password).
resource "kubernetes_secret" "rabbitmq" {
  metadata {
    name      = "rabbitmq-credentials"
    namespace = kubernetes_namespace.messaging.metadata[0].name
    labels    = local.rabbitmq_labels
  }

  data = {
    username = var.rabbitmq_username
    password = var.rabbitmq_password
  }

  type = "Opaque"
}

# Montei os dois arquivos com subPath (nao o diretorio inteiro) porque a
# imagem ja traz 10-defaults.conf em /etc/rabbitmq/conf.d, que um mount do
# diretorio esconderia.
resource "kubernetes_config_map_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq-config"
    namespace = kubernetes_namespace.messaging.metadata[0].name
    labels    = local.rabbitmq_labels
  }

  data = local.rabbitmq_config
}

# StatefulSet de 1 replica (broker unico, sem quorum/cluster): PVC pra nao
# perder mensagens/filas duraveis e o Erlang cookie num restart do pod. A
# Service headless abaixo e so a "governing service" exigida pelo StatefulSet
# (identidade de rede estavel rabbitmq-0); quem consome usa a ClusterIP.
resource "kubernetes_service_v1" "rabbitmq_headless" {
  metadata {
    name      = "rabbitmq-headless"
    namespace = kubernetes_namespace.messaging.metadata[0].name
    labels    = local.rabbitmq_labels
  }

  spec {
    cluster_ip = "None"
    selector   = local.rabbitmq_labels

    port {
      name        = "amqp"
      port        = 5672
      target_port = "amqp"
    }
  }
}

resource "kubernetes_stateful_set_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace.messaging.metadata[0].name
    labels    = local.rabbitmq_labels
  }

  spec {
    service_name = kubernetes_service_v1.rabbitmq_headless.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.rabbitmq_labels
    }

    update_strategy {
      type = "RollingUpdate"
    }

    # O PVC sobrevive a destruir/escalar o StatefulSet de proposito: os dados
    # do broker so somem se eu apagar o PVC explicitamente.
    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }

    template {
      metadata {
        labels = local.rabbitmq_labels

        # Mudou a config => muda o checksum => o StatefulSet recria o pod
        # (RollingUpdate) e ele sobe lendo os arquivos novos.
        annotations = {
          "checksum/config" = sha256(jsonencode(local.rabbitmq_config))
        }
      }

      spec {
        # O broker nao fala com a API do Kubernetes (single node, sem
        # peer discovery), entao nao monto o token da service account.
        automount_service_account_token = false

        # Tempo pro broker fechar conexoes e fazer flush antes do SIGKILL.
        termination_grace_period_seconds = 60

        # A imagem oficial roda como o usuario "rabbitmq" (uid/gid 999) e
        # seus diretorios aceitam uid arbitrario; fixar 999 + fsGroup deixa o
        # PVC gravavel sem precisar de root nem de initContainer de chown.
        # fs_group_change_policy = OnRootMismatch porque o padrao (Always)
        # faz o kubelet reaplicar chmod/chown recursivo no volume a cada
        # montagem (restart/reschedule), e isso pode deixar o
        # /var/lib/rabbitmq/.erlang.cookie com permissao de grupo (0660) -
        # o Erlang recusa iniciar com cookie legivel por grupo/outros. Com
        # OnRootMismatch o kubelet so ajusta o volume quando a raiz dele
        # ainda nao tem o dono/permissao esperados (primeira montagem) e
        # preserva o 0400 do cookie nas montagens seguintes.
        security_context {
          run_as_user            = 999
          run_as_group           = 999
          fs_group               = 999
          fs_group_change_policy = "OnRootMismatch"
          run_as_non_root        = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "rabbitmq"
          image = "rabbitmq:${var.rabbitmq_image_tag}"

          port {
            name           = "amqp"
            container_port = 5672
          }

          port {
            name           = "management"
            container_port = 15672
          }

          port {
            name           = "metrics"
            container_port = 15692
          }

          # Variaveis (nao as *_FILE) porque a imagem recusa iniciar com
          # RABBITMQ_DEFAULT_USER_FILE/PASS_FILE (deprecated). So valem no
          # primeiro boot, com o diretorio de dados vazio: trocar o Secret
          # depois nao muda a senha do usuario ja persistido no PVC - rotacao
          # exige "rabbitmqctl change_password" (ver docs/adr/0004).
          env {
            name = "RABBITMQ_DEFAULT_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.rabbitmq.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "RABBITMQ_DEFAULT_PASS"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.rabbitmq.metadata[0].name
                key  = "password"
              }
            }
          }

          security_context {
            allow_privilege_escalation = false

            capabilities {
              drop = ["ALL"]
            }
          }

          # Requests baixos de proposito: o no unico (Standard_D4as_v4) nao
          # tem folga de CPU (ver docs/adr/0003 e o requests ja reservado
          # pelas demais cargas) - conferir "kubectl describe node" antes do
          # apply. 512Mi de limite e o teto que o watermark de memoria do
          # 30-oficina.conf assume.
          #
          # Limite de CPU de 500m: o Erlang dimensiona seus schedulers pelos
          # processadores logicos que enxerga (o no tem 4 vCPU), e a cota CFS
          # de 500m pode causar throttling sob rajada. Aceito pra a carga
          # pequena da Saga e nao fixei "+S" por nao ter medido; se a latencia
          # degradar, o caminho e limitar os schedulers via
          # RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS ou subir o limite.
          #
          # Pendencia aceita: sem read_only_root_filesystem, porque a imagem
          # oficial escreve em varios caminhos fora do PVC (/tmp, /var/log,
          # /etc/rabbitmq); isolar isso com emptyDir fica pra uma evolucao.
          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }

            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          # Startup tolera boot lento do Erlang (ate 5 min) sem o liveness
          # matar o pod antes da hora.
          startup_probe {
            tcp_socket {
              port = "amqp"
            }

            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 30
          }

          # TCP no readiness (barato) em vez de exec: cada exec de
          # rabbitmq-diagnostics sobe uma VM Erlang so pro CLI, o que pesa
          # contra o request de 100m. O liveness abaixo, com periodo longo,
          # e quem de fato confere que o no responde.
          readiness_probe {
            tcp_socket {
              port = "amqp"
            }

            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 3
          }

          liveness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "-q", "ping"]
            }

            period_seconds    = 60
            timeout_seconds   = 15
            failure_threshold = 3
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/rabbitmq"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/rabbitmq/conf.d/30-oficina.conf"
            sub_path   = "30-oficina.conf"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/rabbitmq/enabled_plugins"
            sub_path   = "enabled_plugins"
            read_only  = true
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.rabbitmq.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.rabbitmq_storage_class_name

        resources {
          requests = {
            storage = var.rabbitmq_storage_size
          }
        }
      }
    }
  }
}

# Unico endereco que as aplicacoes usam: rabbitmq.messaging.svc.cluster.local
# (5672 AMQP). 15672 (management) e 15692 (metricas Prometheus) existem na
# Service pra port-forward/scrape internos - ClusterIP, nunca exposto fora.
resource "kubernetes_service_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace.messaging.metadata[0].name
    labels    = local.rabbitmq_labels
  }

  spec {
    type     = "ClusterIP"
    selector = local.rabbitmq_labels

    port {
      name        = "amqp"
      port        = 5672
      target_port = "amqp"
    }

    port {
      name        = "management"
      port        = 15672
      target_port = "management"
    }

    port {
      name        = "metrics"
      port        = 15692
      target_port = "metrics"
    }
  }
}
