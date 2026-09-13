# ADR 0002: API Management na frente do ingress-nginx

## Status
Aceito

## Contexto
O ecossistema tem dois pontos de entrada distintos: o AKS (onde
`OficinaMecanica` roda atras de um `ingress-nginx`) e a Function App
(`OficinaMecanica.Seguranca`, com seu proprio hostname
`*.azurewebsites.net`). Um cliente/admin externo precisa de um unico ponto
de entrada estavel pra falar com os dois, sem se preocupar com qual e
qual, e alguns comportamentos (path base do Swagger, CORS) precisavam ser
ajustados de forma consistente na borda.

## Decisao
Colocar o **Azure API Management (APIM)** como gateway unico na frente de
ambos: uma API no APIM aponta pro backend do `ingress-nginx` (roteando pra
`OficinaMecanica`), outra API aponta pro backend da Function App
(roteando pra `OficinaMecanica.Seguranca`). O `ingress-nginx` continua
existindo e fazendo o roteamento *dentro* do cluster (e o unico jeito de
expor um Service do AKS via HTTP/HTTPS de forma gerenciada), mas deixa de
ser o ponto de entrada externo - o APIM assume esse papel, com policies
de reescrita de path e CORS aplicadas numa camada so, antes de qualquer
tráfego chegar em qualquer um dos dois backends.

## Consequencias
### Positivas
- Um unico dominio/URL pro cliente falar com o ecossistema inteiro,
  independente de qual servico atende cada rota.
- Policies transversais (CORS, reescrita de path, potencialmente rate
  limiting no futuro) ficam centralizadas no APIM, nao duplicadas em cada
  servico.
- O `ingress-nginx` continua fazendo o que faz de melhor (roteamento
  dentro do cluster), sem precisar assumir responsabilidades de gateway
  de borda (como CORS entre servicos heterogeneos).

### Negativas
- Duas camadas de proxy reverso (APIM -> ingress-nginx -> Service) somam
  latencia extra em cada requisicao, comparado a expor o ingress-nginx
  diretamente.
- Mais um componente de infraestrutura pra provisionar e manter
  (`azurerm_api_management_*` no Terraform) - tempo de provisionamento do
  proprio APIM e considerável (dezenas de minutos).

## Alternativas consideradas
- **Expor o ingress-nginx diretamente (IP publico/hostname do
  LoadBalancer)**: mais simples, sem camada extra de latencia, mas exige
  que o cliente conheca dois enderecos diferentes (um pro AKS, outro pra
  Function App) e replica CORS/policies em cada servico individualmente.
- **APIM apontando direto pros Services do AKS (sem ingress-nginx)**:
  tecnicamente possível via `azurerm_api_management_backend` apontando pra
  um IP interno, mas perderia o roteamento/health checking que o
  ingress-nginx ja fornece dentro do cluster.
