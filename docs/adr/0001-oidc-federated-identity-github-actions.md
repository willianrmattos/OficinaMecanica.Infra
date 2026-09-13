# ADR 0001: OIDC/Federated Identity em vez de secrets de longa duracao

## Status
Aceito

## Contexto
Todo o CI/CD do ecossistema (build+push de imagem, deploy no AKS, deploy
na Function App, `terraform plan`/`apply`) precisa autenticar no Azure a
partir do GitHub Actions. A forma tradicional seria criar um Service
Principal com um client secret, guardar esse secret como um GitHub Secret,
e usar `azure/login@v2` com `creds`. Isso funciona, mas o secret e um
valor de longa duracao: se vazar (log acidental, repositorio comprometido),
continua valido ate ser revogado manualmente, e precisa ser rotacionado
periodicamente.

## Decisao
Cada identidade de CI (`github_oidc`, `github_oidc_seguranca`,
`github_oidc_infra`, `github_oidc_banco`) e uma App Registration +
Service Principal do Azure AD sem client secret, associada a uma ou mais
**Federated Identity Credentials**. O GitHub Actions emite um token OIDC
de curta duracao a cada execucao do workflow, assinado pelo GitHub
(`https://token.actions.githubusercontent.com`); o Azure AD confia nesse
token porque o "subject" nele bate com o configurado na credencial
federada (restrito a um repositorio e evento especificos - PR ou push numa
branch exata). Nao existe nenhum segredo de longa duracao armazenado no
GitHub em nenhum dos quatro repositorios.

Uma identidade por repositorio (nao uma por finalidade - ex: uma so pra
"validate" e outra pra "deploy"): um PR passa a rodar com um token
tecnicamente capaz de aplicar mudancas de verdade, nao so planeja-las.
Aceito conscientemente por ser um projeto sem colaboradores externos
abrindo PRs.

## Consequencias
### Positivas
- Nenhum secret de longa duracao pra vazar, rotacionar ou revogar.
- O escopo de cada identidade e explicito em Terraform (role assignments
  versionados), nao um Service Principal criado manualmente no portal.
- A credencial federada ja restringe por repositorio e branch/evento -
  reduz superficie de ataque mesmo sem um secret rotativo.

### Negativas
- O formato do "subject" no token do GitHub mudou de convencao ao longo do
  tempo (nomes de repositorio/owner vs. IDs numericos imutaveis) - repos
  criados em momentos diferentes tiveram comportamento diferente, exigindo
  depuracao (erro `AADSTS700213`) pra descobrir qual formato cada
  repositorio realmente usa.
- Uma identidade por repositorio (nao por finalidade) significa que um PR
  roda com permissao de aplicar, nao so de planejar - uma concessao
  aceitavel aqui, mas que nao escalaria bem com colaboradores externos.

## Alternativas consideradas
- **Client secret tradicional via GitHub Secrets**: mais simples de
  configurar, mas exige rotacao manual e o secret fica visível/copiavel
  por qualquer um com acesso de escrita ao repositorio (e nao expira
  sozinho).
- **Uma identidade por finalidade (validate vs. apply)**: mais restritivo
  (PR nunca teria permissao de escrita), mas dobra o numero de identidades
  a gerenciar. Chegou a ser implementado para Infra/Banco e depois
  revertido em favor de uma identidade unica por repositorio, pela
  simplicidade.
