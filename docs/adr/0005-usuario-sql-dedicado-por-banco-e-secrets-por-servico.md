# ADR 0005: Usuario SQL dedicado por banco e secrets por servico

## Status
Aceito

## Contexto
Ate aqui o monolito (`OficinaMecanicaDb`) e o Seguranca (`SegurancaDb`)
usavam o **administrador do SQL Server** (`adminfiap`) nas connection
strings guardadas no Key Vault. Com a entrada do Billing (`BillingDb`) e da
Execucao (MongoDB Atlas), o requisito de independencia dos microsservicos
pede, por servico: banco proprio, **credencial de banco dedicada** (nunca o
admin do servidor) e **segredos so seus**.

O SQL Server logico `svsfiap` continua **compartilhado por desenho**: a
assinatura Azure for Students restringe regioes e capacidade (ver
`CLAUDE.md`: so um subconjunto de regioes e o Azure SQL ja bloqueou
regioes permitidas pela politica), o que torna impraticavel provisionar um
servidor por servico. O isolamento de dados passa a ser por **banco +
usuario**, nao por servidor.

## Decisao
- O repositorio `OficinaMecanica.Banco` cria, por banco, um **usuario SQL
  contido dedicado** (`app_os` em `OficinaMecanicaDb`, `app_seguranca` em
  `SegurancaDb`, `app_billing` em `BillingDb`), com `db_owner` apenas no
  proprio banco. O administrador do servidor fica restrito ao Banco.
- Este repositorio monta as connection strings do Key Vault com esses
  usuarios (`sql-connection-string`, `seguranca-sql-connection-string`,
  `billing-sql-connection-string`). As senhas sao variaveis sensiveis com
  **os mesmos nomes nos dois repos** (`sql_app_os_password`,
  `sql_app_seguranca_password`, `sql_app_billing_password`), entregues por
  `TF_VAR_*` (GitHub Secrets no CI). As variaveis do administrador
  (`sql_administrator_login`/`_password`) foram removidas deste repo: nada
  mais as usa.
- A connection string do MongoDB Atlas (`execucao-mongo-connection-string`)
  e gravada no Key Vault pelo **Banco**, porque o host do cluster so existe
  apos a criacao. Por isso o `github_oidc_banco` ganha `Key Vault Secrets
  Officer` **escopado so nesse secret** (nao no vault: a identidade do Banco
  tem credencial de `pull_request`); este repo nao cria o secret.
- Segredos por servico: cada servico le so os seus pelo
  `SecretProviderClass` do proprio repo, e a identidade de CI dos servicos
  novos (`github_oidc_aks_app`, ADR 0006) recebe `Key Vault Secrets User`
  **por secret**, nao no vault inteiro. Segredos de Mercado Pago ficam em
  `mercadopago-access-token`/`mercadopago-webhook-secret`, valores reais
  somente via CI/ambiente local.
- **Ordem de aplicacao obrigatoria: Banco primeiro** (cria bancos e
  usuarios), **Infra depois** (aponta as connection strings pra usuarios que
  ja existem). O merge em `release`/`main` dispara `terraform apply
  -auto-approve`, entao mergear o PR do Infra antes do Banco derruba monolito
  e Seguranca (logins inexistentes).
- **Bootstrap do secret do Mongo**: (1) aplicar o Banco **localmente** na
  primeira vez, com o admin humano (Key Vault Administrator), que cria o
  secret; (2) so depois o apply do Infra cria a role escopada (o
  `github_oidc_infra` so tem `Contributor`, que nao cria role assignment: se o CI der
  `AuthorizationFailed`, aplique localmente com o admin humano); (3) dai em diante o
  CI do Banco funciona. Se o ARM recusar o escopo de secret inexistente/criado
  por outro repo, o apply do Infra falha nessa role sem destruir nada e basta
  reordenar.

## Consequencias
### Positivas
- Vazar a connection string de um servico nao da acesso aos bancos dos
  demais nem ao administrador do servidor.
- O admin do SQL Server sai do Key Vault e do cluster; senha de cada
  servico rotaciona de forma independente.
- Menor privilegio coerente com o padrao ja usado nos modulos
  `github_oidc_*`.

### Negativas
- O servidor logico (firewall, administrador, limites da assinatura) segue
  compartilhado; isolamento forte entre servicos no nivel do servidor nao
  existe.
- **Contrato entre dois repos**: logins e nomes das variaveis de senha
  duplicados em Banco e Infra; senha divergente entre eles resulta em
  falha de login nos servicos. Aplicar o Infra antes do Banco quebra o
  monolito e o Seguranca (usuarios ainda inexistentes).
- Trocar o valor do secret nao reinicia os consumidores: o monolito (env via
  `secretKeyRef`) precisa de novo rollout e a Function App de reinicio pra
  ler a nova connection string.
- `db_owner` no proprio banco e amplo (permite DDL), necessario pras
  migrations do CI; separar usuario de migration e de runtime fica como
  melhoria.
- Isolamento no Key Vault e **parcial**: identidades pre-existentes (CI do
  monolito, CI e Function App do Seguranca, e a identidade do addon CSI do
  AKS, compartilhada por todos os pods) mantem `Key Vault Secrets User` no
  vault inteiro. Evolucao: escopo por secret nessas identidades e Workload
  Identity por servico.
- A role do CI do Banco so e criada com o secret do Mongo ja existente, o que
  obriga o bootstrap local acima (primeira aplicacao do Banco fora do CI).
- As senhas SQL e a do RabbitMQ continuam no state remoto do Terraform
  (storage com acesso via Azure AD).

## Alternativas consideradas
- **Manter o admin do servidor nas connection strings**: mais simples, mas
  qualquer servico comprometido alcanca todos os bancos.
- **Um SQL Server logico por servico**: isolamento maior, inviavel dentro
  das restricoes da assinatura Azure for Students.
- **Autenticacao Microsoft Entra (managed identity/Workload Identity) no
  SQL**: elimina a senha, mas exige administrador Entra no servidor e
  usuarios externos por servico; fica como evolucao.
- **Um Key Vault por servico**: isolamento de segredos mais forte por RBAC de
  vault, ao custo de multiplicar vaults, URIs e role assignments.
