# ADR 0003: Homologacao e producao no mesmo cluster/aplicacao

## Status
Aceito

## Contexto
O requisito de avaliacao pedia deploy automatico separado para uma branch
de homologacao (`release`) e uma de producao (`main`). O desenho inicial
previa um namespace dedicado no AKS para homologacao (Deployment/Service/
Ingress proprios), alem de um segundo Function App e um segundo banco de
dados para o `OficinaMecanica.Seguranca` - um ambiente fisicamente isolado
por tras de cada branch, como se faria num cenario de producao real.

Esse desenho esbarrou numa limitacao concreta: o cluster AKS roda num
**node unico**, sem CPU sobrando pra manter uma segunda instancia completa
da aplicacao (nem reduzindo replicas ao minimo). A mesma restricao de
custo que motivou usar a assinatura Azure for Students e Terraform enxuto
torna inviavel manter dois ambientes fisicamente separados.

## Decisao
`main` (producao) e `release` (homologacao) disparam deploy automatico
para **a mesma aplicacao em execucao**: mesmo Deployment `oficinamecanica-api`
no AKS, mesma Function App `funcsegurancafiap`, mesmo banco de dados. Nao
ha namespace, node pool, Function App ou banco de dados dedicados para
homologacao. A separacao entre os dois ambientes e feita inteiramente a
nivel de **processo**: branch `main` protegida (sem push direto, PR
obrigatorio), CI/CD disparado automaticamente por push em qualquer uma das
duas branches, cada uma redirecionando pro mesmo alvo de deploy.

## Consequencias
### Positivas
- Custo zero adicional - nenhum recurso Azure extra provisionado so para
  homologacao.
- Viavel dentro da cota de CPU de um cluster de node unico.
- Ainda demonstra o fluxo de CI/CD esperado (PR obrigatorio, deploy
  automatico por branch), que era o objetivo central do requisito.

### Negativas
- Um push em `release` e um push em `main` acabam afetando o mesmo
  ambiente rodando - nao ha isolamento real entre "testar antes" e
  "producao de verdade". Um deploy problematico em homologacao afeta
  producao imediatamente, o que anularia a proposta de ter um ambiente de
  homologacao num cenario real.
- Nao ha como rodar testes de carga ou validacao exploratoria em
  homologacao sem impactar quem estiver usando a aplicacao "em producao"
  no mesmo instante.

## Alternativas consideradas
- **Namespace dedicado no AKS + segunda Function App + segundo banco**
  (desenho original): isolamento real entre ambientes, mas inviavel dentro
  da CPU disponivel no node unico do cluster.
- **Reduzir replicas ao minimo (1) em homologacao pra caber no mesmo
  node**: avaliado e descartado - mesmo com 1 replica, a soma de CPU
  requisitada pelos dois Deployments (producao + homologacao) excedia o
  que o node unico oferece.

## Nota
Num cenario real de producao, o recomendado seria infraestrutura dedicada
por ambiente (namespace/node pool/Function App/banco separados), eliminando
o risco de um deploy de teste afetar producao. Esta decisao e especifica
das restricoes de custo deste projeto, documentada tambem nos
READMEs de `OficinaMecanica` e `OficinaMecanica.Seguranca`.
