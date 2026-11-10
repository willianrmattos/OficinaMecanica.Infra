"""Teste local (sem Azure) da condicao de bloqueio de /health/ready e /metrics.

Le o PROPRIO arquivo apim/bloqueio-health-ready-e-metrics.xml (o mesmo que o
Terraform injeta nas policies), extrai a expressao C# do atributo `condition` e o
regex dela, e o aplica do jeito que a APIM o faria:

    Regex.IsMatch(WebUtility.UrlDecode(context.Request.Url.Path).ToLowerInvariant(), padrao)

O fragmento NAO e XML estrito: segue a forma dos exemplos da documentacao da APIM
(atributo entre aspas duplas com as aspas do literal C# cruas, o formato rawxml
que o provider azurerm envia). Por isso a expressao e extraida por texto e, so
para validar a estrutura, as aspas dela sao escapadas antes de passar por um parser
XML estrito. Esse parse prova a estrutura do fragmento (choose/when/return-response
404, sem corpo), NAO que a APIM aceita a expressao: isso so o primeiro apply prova.

Url.Path nao inclui a query string (a APIM expoe Query/QueryString a parte), entao
a query e removida antes de avaliar. Python `re` e .NET Regex se comportam igual
para este padrao (so classes, grupos, alternancia, `*`, `?`, `$` e `^`).

Uso (a partir de qualquer pasta):  python -I docs/apim/testar_bloqueio_health_ready_e_metrics.py
Sai com codigo 1 se algum caso divergir. Nao acessa rede nem credenciais.
"""

import html
import re
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote_plus

FRAGMENTO = Path(__file__).resolve().parents[2] / "apim" / "bloqueio-health-ready-e-metrics.xml"

# (path como chega na APIM, com query opcional, deve bloquear?)
CASOS = [
    # --- devem responder 404 ---
    ("/health/ready", True),
    ("/HEALTH/READY/", True),
    ("/billing/health/ready", True),
    ("/billing/health/ready?x=1", True),
    ("/billingserver/health/ready", True),
    ("/execucao/metrics", True),
    ("/execucaoserver/metrics/", True),
    ("/metrics", True),
    ("/oficinaserver/METRICS?format=prometheus", True),
    ("/oficinaserver/health/ready/?a=b&c=d", True),
    ("//health/ready", True),
    ("/oficinaserver/health//ready", True),
    ("/billingserver/health/%72eady", True),
    ("/billingserver/health%2Fready", True),
    ("/billingserver/%6Detrics", True),
    ("/billingserver/health/./ready", True),
    ("/billingserver/health/ready/.", True),
    ("/billingserver/health/x/../ready", True),
    ("/billingserver/health/ready/x/..", True),
    # --- NAO devem bloquear ---
    ("/api/ordens-de-servico", False),
    ("/billing/api/orcamentos/health/ready-nao", False),
    ("/api/pecas/metrics-report", False),
    ("/health", False),
    ("/health/", False),
    ("/billingserver/health?x=/health/ready", False),
    ("/billingserver/xhealth/ready", False),
    ("/billingserver/health/readyx", False),
    ("/billingserver/health/ready/extra", False),
    ("/billingserver/health/ready.json", False),
    ("/oficinaserver/metrics/summary", False),
    ("/oficinaserver/swagger/index.html", False),
    ("/billingserver/webhooks/mercadopago", False),
    ("/billingserver/api/orcamentos/12", False),
    ("/billingserver/arquivo..txt", False),
    ("/", False),
    ("", False),
]


def carregar_regex():
    texto = FRAGMENTO.read_bytes().decode("utf-8")

    achados = re.findall(r'^\s*<when condition="(@\(.*\))">\s*$', texto, re.MULTILINE)
    assert len(achados) == 1, "esperava exatamente um <when condition=\"@(...)\"> em uma linha"
    expressao = achados[0]
    proibidos = [c for c in "<>&" if c in expressao]
    assert not proibidos, f"caracteres de marcacao XML na expressao: {proibidos}"
    literais = re.findall(r'@"([^"]*)"', expressao)
    assert len(literais) == 1, "esperava exatamente um literal @\"...\" (o padrao)"

    # Estrutura: escapo so as aspas da expressao e passo o fragmento por um parser estrito.
    estrito = texto.replace(expressao, html.escape(expressao, quote=True))
    raiz = ET.fromstring(estrito)  # levanta ParseError se o resto nao for XML bem formado
    assert raiz.tag == "choose", "raiz deveria ser <choose>"
    whens = raiz.findall("when")
    assert len(whens) == 1, "esperava exatamente um <when>"
    assert whens[0].get("condition") == expressao, "a condicao lida pelo parser difere do texto"
    status = whens[0].find("return-response/set-status")
    assert status is not None and status.get("code") == "404", "o when deve devolver 404"
    assert whens[0].find("return-response/set-body") is None, "corpo deve ficar vazio"
    return re.compile(literais[0])


def bloqueia(padrao, path_com_query):
    url_path = re.split(r"[?#]", path_com_query, maxsplit=1)[0]  # Url.Path nao tem query
    return padrao.search(unquote_plus(url_path).lower()) is not None


def main():
    padrao = carregar_regex()
    falhas = 0
    print(f"{'path':<52} {'esperado':<9} {'obtido':<9} resultado")
    for path, esperado in CASOS:
        obtido = bloqueia(padrao, path)
        ok = obtido == esperado
        falhas += not ok
        rotulo = lambda b: "404" if b else "repassa"
        print(f"{path or '(vazio)':<52} {rotulo(esperado):<9} {rotulo(obtido):<9} {'ok' if ok else 'FALHOU'}")

    # Custo: um path longo de barras/pontos nao pode causar backtracking explosivo no gateway.
    pior = "/billingserver/health" + "/." * 4000 + "x"
    t0 = time.perf_counter()
    bloqueia(padrao, pior)
    bloqueia(padrao, "/" * 8000 + "x")
    gasto = time.perf_counter() - t0
    print(f"\nteste de custo (paths patologicos de 8 mil caracteres): {gasto * 1000:.1f} ms")
    if gasto > 1.0:
        falhas += 1
        print("FALHOU: custo do regex acima de 1 s")

    print(f"\n{len(CASOS)} casos, {falhas} falha(s)")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
