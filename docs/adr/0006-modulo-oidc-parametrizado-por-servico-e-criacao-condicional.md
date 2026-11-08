# ADR 0006: Modulo OIDC parametrizado por servico e criacao condicional

## Status
Aceito

## Contexto
Billing e Execucao precisam de CI/CD proprio: build e push da imagem no ACR,
deploy no AKS e leitura da connection string do proprio banco. O requisito
de independencia pede **identidade OIDC propria e de menor privilegio por
servico** (ADR 0001). Ja existem quatro modulos OIDC (`github_oidc`,
`github_oidc_seguranca`, `github_oidc_infra`, `github_oidc_banco`), cada um
uma copia ajustada do anterior.

Alem disso, os repositorios `OficinaMecanica.Billing` e
`OficinaMecanica.Execucao` **ainda nao existem no GitHub**, e o subject OIDC
com IDs imutaveis (`repo:<owner>@<ownerId>/<repo>@<repoId>:...`) so pode ser
montado depois que o ID do repositorio e conhecido.

## Decisao
- Novo modulo **`github_oidc_aks_app`**, parametrizado por servico (nome da
  App Registration, repositorio, IDs imutaveis, ACR, AKS e mapa de secrets).
  O `github_oidc` do OS Service (o antigo monolito) **nao e alterado**.
- Federated Identity Credentials **apenas para push em `main` e `release`**
  (subject com IDs imutaveis); **nao ha credencial de `pull_request`**, pois
  o job de deploy tem `AcrPush` e Cluster Admin.
- Roles: `AcrPush` no `acrfiap`, `Azure Kubernetes Service Cluster Admin
  Role` no `aksfiap` e `Key Vault Secrets User` **escopado em cada secret**
  listado em `key_vault_secret_scopes` (Billing: `billing-sql-connection-string`,
  lido pelo step de migration; Execucao: mapa vazio, porque o pipeline dela nao
  tem migration e nenhum secret a ler).
- Instancias `github_oidc_billing` e `github_oidc_execucao` na raiz com
  **criacao condicional**: `count = var.<servico>_github_repo_id == null ? 0 : 1`.
  As variaveis `billing_github_repo_id`/`execucao_github_repo_id` tem
  `default = null` (com validacao: so digitos ou `null`); outputs
  `billing_github_actions_client_id`/`execucao_github_actions_client_id` sao
  condicionais (`one(module.x[*].client_id)`).
- Passo apos criar cada repositorio: `gh api repos/willianrmattos/<repo> --jq
  .id`, gravar o valor no default da variavel em `variables.tf` (via PR, pois
  o CI nao le `.tfvars`), aplicar e configurar `AZURE_CLIENT_ID` no
  repositorio com o output.

## Consequencias
### Positivas
- Servico novo atras do AKS e uma instancia do modulo, sem copiar codigo.
- `terraform validate`/`plan` permanecem verdes antes da publicacao dos
  repositorios (modulos com `count = 0`).
- Identidades independentes; o pipeline de um servico so le os secrets do
  proprio servico; PR nunca autentica com privilegio de deploy.
- IDs imutaveis impedem que um repositorio renomeado/recriado com o mesmo
  nome herde a identidade.

### Negativas
- Duas formas de configuracao (`null` vs. preenchido): preencher o ID so
  num `.tfvars` local e aplicar localmente faz o `plan` do CI propor
  destruir a identidade - o ID precisa ir pro default em `variables.tf`.
- `AcrPush` vale para o registry inteiro (restringir por repositorio exige o
  modo ABAC do ACR, nao habilitado) e `Cluster Admin` para o cluster inteiro
  (contas locais, sem Azure RBAC for Kubernetes): um servico comprometido
  poderia sobrescrever imagens e ler secrets de outros dentro do cluster. A
  independencia vale no plano do Azure, nao dentro do Kubernetes.
- Coexistem dois padroes: o `github_oidc` do OS Service segue com subject no
  formato antigo e `Key Vault Secrets User` no vault inteiro; migra-lo pro
  modulo parametrizado recriaria a credencial federada e arriscaria o CI do
  OS Service.
- A Execucao nao recebe nenhuma role no Key Vault (mapa `key_vault_secret_scopes`
  vazio): a connection string do Atlas chega ao pod pelo CSI Secrets Store, com
  a identidade do addon do AKS, e nao pela identidade do pipeline. A role em
  escopo de secret criado por **outro** repositorio (Banco) e a do
  `github_oidc_banco` (ADR 0005), que depende da ordem Banco -> Infra e de o
  escopo de secret ja existente ser aceito pelo ARM (confirmar no primeiro
  apply); nao tem relacao com o modulo parametrizado.

## Alternativas consideradas
- **Generalizar o `github_oidc` existente com `for_each`**: reaproveitaria o
  codigo, mas altera um modulo ja aplicado e arrisca recriar a identidade do
  OS Service.
- **Uma identidade compartilhada pelos microsservicos**: simples, mas viola
  o requisito de identidade propria e menor privilegio por servico.
- **Copiar o modulo por servico** (como Banco/Seguranca): seriam seis copias
  quase identicas pra manter (quatro ja existem, e ja sao uma divida).
- **Criar os modulos com `repo_id` provisorio**: o Azure AD receberia
  credencial federada com subject invalido, sem efeito real e confusa de
  auditar.
- **Criar os repositorios antes**: bloquearia este trabalho, que e so
  `fmt`/`validate`; a publicacao depende de autorizacao explicita.
