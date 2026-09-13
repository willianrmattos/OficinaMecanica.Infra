# RFC 0001: Terraform centralizado em repositorio proprio

## Status
Aceito

## Resumo
Todo o Terraform do ecossistema (AKS, ACR, Key Vault, API Management,
identidades OIDC do GitHub Actions, Helm releases) vive num repositorio
proprio, `OficinaMecanica.Infra`, separado dos repositorios de aplicacao
(`OficinaMecanica`, `OficinaMecanica.Seguranca`). O banco de dados tem uma
divisao ainda mais fina, com state proprio em `OficinaMecanica.Banco`.

## Motivacao
O projeto comecou com o Terraform dentro de `OficinaMecanica/infra/` -
ou seja, a infraestrutura de todo o ecossistema vivia acoplada ao
repositorio de um unico servico (o monolito). Isso trazia alguns
problemas conforme o ecossistema cresceu:
- `OficinaMecanica.Seguranca` precisava de recursos Azure proprios
  (Function App, banco, Key Vault) que nao faziam sentido dentro do
  repositorio do monolito.
- O ciclo de vida da infraestrutura (raramente muda, exige plano
  cuidadoso) e bem diferente do ciclo de vida do codigo de aplicacao
  (muda com frequencia, cada PR).
- Misturar os dois no mesmo repositorio dificultava aplicar politicas
  diferentes de CI/CD pra cada um (ex: aprovacao manual pra mudancas de
  infra vs. deploy automatico de codigo).

## Proposta
Extrair todo o Terraform pra um repositorio irmao dedicado,
`OficinaMecanica.Infra`, que passa a ser a fonte da verdade pra
praticamente toda a infraestrutura Azure do ecossistema. Os repositorios
de aplicacao (`OficinaMecanica`, `OficinaMecanica.Seguranca`) deixam de
ter pasta `infra/` ou qualquer Terraform proprio - so consomem os
recursos ja provisionados (AKS, Key Vault, etc.) via CI/CD.

O banco de dados foi um passo alem: mesmo dentro do `OficinaMecanica.Infra`,
o modulo `sqldb/` foi extraido pra outro repositorio ainda,
`OficinaMecanica.Banco`, com **state proprio** (nao so pasta separada) -
reconhecendo que o ciclo de vida de um banco de dados (extremamente
sensivel, quase nunca destruido/recriado) e ainda mais isolado do resto da
infraestrutura do que o resto.

## Alternativas consideradas
- **Terraform dentro de cada repositorio de aplicacao**: mantém a infra
  fisicamente perto do codigo que ela suporta, mas duplica preocupações
  transversais (Key Vault, identidades OIDC) em varios lugares e nao
  resolve o problema de recursos que nao pertencem a nenhum app especifico
  (ex: o proprio cluster AKS, compartilhado).
- **Um monorepo com todo o Terraform + todo o codigo de aplicacao**: unifica
  tudo, mas mistura ciclos de vida e times (mesmo sendo uma pessoa so
  neste projeto, o objetivo e simular praticas reais de mercado) - PRs de
  infra e PRs de aplicacao competeriam pela mesma esteira de CI/CD.

## Decisao
Repositorio proprio para toda a infraestrutura (`OficinaMecanica.Infra`),
com uma segunda divisao ainda mais fina para o banco de dados
(`OficinaMecanica.Banco`, state proprio). Ver ADR 0003 (mesmo repositorio)
para a decisao especifica de nao duplicar ambientes de homologacao/producao
dentro dessa mesma infraestrutura, por restricao de custo.
