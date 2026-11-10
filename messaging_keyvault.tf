# Credenciais do RabbitMQ (helm/rabbitmq.tf) - na raiz porque a senha precisa
# ir pra dois lugares que nao se conhecem: o Secret nativo do namespace
# messaging (modulo helm) e o Key Vault (modulo keyvault), de onde as
# aplicacoes de outros namespaces a leem via CSI Secrets Store. Mesmo padrao
# de keyvault_secrets.tf/seguranca_keyvault.tf.

# Sem caracteres especiais de proposito: a senha entra em URIs/connection
# strings AMQP, onde simbolos exigiriam percent-encoding em cada consumidor.
# 32 caracteres alfanumericos ja dao entropia de sobra. Fica no state remoto
# (storage com acesso via Azure AD) - rotacionar com
# "terraform apply -replace=random_password.rabbitmq" E trocar a senha no
# broker (rabbitmqctl change_password), pois o usuario persiste no PVC.
resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "rabbitmq_username" {
  name         = "rabbitmq-username"
  key_vault_id = module.keyvault.key_vault_id
  value        = var.rabbitmq_username
}

resource "azurerm_key_vault_secret" "rabbitmq_password" {
  name         = "rabbitmq-password"
  key_vault_id = module.keyvault.key_vault_id
  value        = random_password.rabbitmq.result
}
