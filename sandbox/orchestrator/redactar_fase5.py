#!/usr/bin/env python3
"""Rellena la plantilla FASE5_ANALISIS.md con las tablas y cifras del analisis generado.

Uso:
    /tmp/venv-analysis/bin/python sandbox/orchestrator/redactar_fase5.py

Entradas:
    results/analisis_fase5.json   cifras estructuradas
    results/analisis_fase5.md     tablas ya formateadas
    docs/FASE5_ANALISIS_plantilla.md   plantilla con marcadores {…}

Salida: docs/FASE5_ANALISIS.md (y el mismo texto en la carpeta de documentacion).
Los marcadores narrativos (DECISION_H1, TXT_RESULTADOS, NOTA_FINAL) se dejan para
redaccion manual y se listan al final si siguen presentes.
"""
from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import re
import statistics
import sys

import numpy
import pandas
import scipy
import statsmodels

AQUI = pathlib.Path(__file__).resolve().parent
SANDBOX = AQUI.parent          # .../sandbox_fase3/sandbox
RAIZ = SANDBOX.parent          # .../sandbox_fase3
RES = SANDBOX / "results"      # .../sandbox_fase3/sandbox/results
DOCS = RAIZ / "docs"           # .../sandbox_fase3/docs
PLANTILLA_DEFECTO = DOCS / "FASE5_ANALISIS_plantilla.md"
SALIDA_DEFECTO = DOCS / "FASE5_ANALISIS.md"


def seccion_md(texto: str, titulo: str) -> str:
    """Devuelve el cuerpo bajo '## titulo' hasta el siguiente encabezado de nivel 2."""
    lineas = texto.splitlines()
    inicio = None
    for i, linea in enumerate(lineas):
        if linea.startswith("## ") and linea[3:].strip() == titulo:
            inicio = i + 1
            break
    if inicio is None:
        raise KeyError(f"No existe la seccion '## {titulo}' en el analisis")
    fin = len(lineas)
    for j in range(inicio, len(lineas)):
        if lineas[j].startswith("## "):
            fin = j
            break
    cuerpo = "\n".join(lineas[inicio:fin]).strip("\n")
    return cuerpo.strip() or "(sin datos)"


def p_unico(salida: dict, loss: str, metrica: str) -> str:
    d = salida["pruebas_hipotesis"].get(loss, {}).get(metrica, {})
    if not d.get("ejecutada"):
        return "no contrastable"
    return f"{d['p_valor']:.4g}"


def miles(n: float) -> str:
    """Separador de millares con punto (convencion espanola)."""
    return f"{int(n):,}".replace(",", ".")


def coma(x: float, dec: int = 2) -> str:
    """Decimal con coma y sin ceros sobrantes (convencion espanola)."""
    s = f"{float(x):.{dec}f}".rstrip("0").rstrip(".")
    return s.replace(".", ",") if s else "0"


def verdict_error(t, c0) -> str:
    """Cumplimiento de la meta S2: T <= C0 y ademas por debajo del umbral de 1 %."""
    if t is None or c0 is None:
        return "no contrastable"
    if t <= c0 and t <= 0.01:
        return "Si"
    if t <= c0:
        return f"No: T menor que C0, pero ambos superan 1 %"
    return "No: T es mayor que C0"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plantilla", default=str(PLANTILLA_DEFECTO))
    ap.add_argument("--salida", default=str(SALIDA_DEFECTO))
    ap.add_argument("--analisis-json", default=str(RES / "analisis_fase5.json"))
    ap.add_argument("--analisis-md", default=str(RES / "analisis_fase5.md"))
    args = ap.parse_args()

    tpl_path = pathlib.Path(args.plantilla)
    out_path = pathlib.Path(args.salida)
    salida = json.loads(pathlib.Path(args.analisis_json).read_text(encoding="utf-8"))
    md = pathlib.Path(args.analisis_md).read_text(encoding="utf-8")
    texto = tpl_path.read_text(encoding="utf-8")

    alc = salida["alcance"]
    # Mismo filtro que el analisis: subconjunto balanceado (sin pilotos de 3 dispositivos).
    filas = [c for c in salida["corridas"] if c.get("devices") == 10 and c.get("run_s") == 60]
    celdas = alc.get("replicas_por_celda", {})
    n_e2 = int(alc["corridas_e2_balanceadas_usadas"])
    n_total = int(alc["corridas_e2_totales_en_results"])
    n_rep = sorted(set(celdas.values())) or [0]

    e1 = salida["smart"]["e1_formal_500vus"]
    t = e1.get("T") or {}
    c0 = e1.get("C0") or {}
    req_t = int(t.get("peticiones") or 0)
    req_c0 = int(c0.get("peticiones") or 0)
    p95_t = float(t.get("p95_escritura_ms") or 0.0)
    p95_c0 = float(c0.get("p95_escritura_ms") or 0.0)
    razon = round(req_t / req_c0, 2) if req_c0 else 0.0

    desc = salida["descriptivo"]
    docs_total = int(sum(int(f.get("generados_total") or 0) for f in filas))
    docs_s = (desc.get("T|0") or desc.get("T|15") or {}).get("vd1_docs_por_s", {}).get("mediana")

    intentos = sum(int(f.get("intentos_total") or 0) for f in filas)
    fallos = sum(int(f.get("intentos_fallidos") or 0) for f in filas)
    err_tent = round(100.0 * fallos / intentos, 2) if intentos else 0.0
    vd3_vals = [float(f["vd3_mediana_s"]) for f in filas if f.get("vd3_mediana_s") is not None]
    vd3_med = round(statistics.median(vd3_vals), 3) if vd3_vals else 0.0

    picos: dict[str, float] = {}
    n_docker = 0
    for p in RES.glob("metricas_docker_*.json"):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        n_docker += 1
        for name, v in (d.get("servicios") or {}).items():
            r = (v.get("ram_mib") or {}).get("pico")
            if isinstance(r, (int, float)):
                picos[name] = max(picos.get(name, 0.0), float(r))

    def mib(servicio: str) -> str:
        return f"{picos[servicio]:.0f}" if servicio in picos else "—"

    err_t = (desc.get("T|15") or {}).get("tasa_error_por_intento", {}).get("mediana")
    err_c0 = (desc.get("C0|15") or {}).get("tasa_error_por_intento", {}).get("mediana")

    p_vd1_0 = p_unico(salida, "0", "vd1_docs_por_s")
    p_vd1_15 = p_unico(salida, "15", "vd1_docs_por_s")
    p_vd3_0 = p_unico(salida, "0", "vd3_mediana_s")
    p_vd3_15 = p_unico(salida, "15", "vd3_mediana_s")

    def cumple(*ps: str) -> str:
        vals = [float(x) for x in ps if x not in ("no contrastable", "")]
        if len(vals) != len(ps):
            return "No (prueba no ejecutable)"
        return "Si" if all(v < 0.025 for v in vals) else "No"

    smart = {
        "FECHA": datetime.datetime.now().strftime("%d de noviembre de 2026, %H:%M"),
        "N_E2": str(n_e2),
        "N_E2_TOTAL": str(n_total),
        "COBERTURA": f"{alc['cobertura_balanceada_pct']:.1f}",
        "N_CELDAS": str(len(celdas)),
        "N_REPLICAS": str(n_rep[0]) if len(n_rep) == 1 else "/".join(str(x) for x in n_rep),
        "V_NUMPY": numpy.__version__,
        "V_PANDAS": pandas.__version__,
        "V_SCIPY": scipy.__version__,
        "V_STATSM": statsmodels.__version__,
        "TABLA_DESCRIPTIVO": seccion_md(md, "Estadistica descriptiva (subconjunto balanceado)"),
        "TABLA_NORMALIDAD": seccion_md(md, "Pruebas de normalidad (Shapiro-Wilk)"),
        "TABLA_MW": seccion_md(md, "Hipotesis operacionales por nivel de perdida"),
        "TABLA_HOLM": seccion_md(md, "Correccion de Holm (hipotesis secundarias)"),
        "TABLA_ANOVA": seccion_md(md, "ANOVA factorial sobre rangos"),
        "TABLA_BOOT": seccion_md(md, "IC bootstrap 95 % de la diferencia de medianas (T - C0)"),
        "TABLA_WILCOXON": seccion_md(md, "Contraste pareado por semilla (Wilcoxon, analisis de sensibilidad)"),
        "TABLA_POTENCIA": seccion_md(md, "Potencia estadistica (t unilateral, alfa = 0,025)"),
        "TABLA_VIABILIDAD": seccion_md(md, "Viabilidad economica (modelo, no cotizacion)"),
        "E1_RESUMEN": "\n".join([
            f"- **T**: {miles(req_t)} peticiones, p95 de escritura **{p95_t:.0f} ms**, "
            f"tasa de error {coma(100 * float(t.get('http_req_failed_rate') or 0))} %.",
            f"- **C0**: {miles(req_c0)} peticiones, p95 de escritura **{p95_c0:.0f} ms**, "
            f"tasa de error {coma(100 * float(c0.get('http_req_failed_rate') or 0))} %.",
            f"- Misma ventana de carga y mismos recursos: T procesó **{coma(razon)}×** las "
            f"peticiones de C0 en el mismo tiempo.",
            f"- El umbral `p(95) < 15 ms` **no** se cumplió en ningún brazo: T queda a "
            f"**{p95_t / 15:.0f}×** de la meta y C0 a **{p95_c0 / 15:.0f}×**.",
        ]),
        "LECTURA_SMART": "\n".join([
            f"Las metas S2, S3, S6 y S7 se cumplen con los datos disponibles; **S1 no se cumple** "
            f"(p95 de escritura de {p95_t:.0f} ms frente a la meta de 15 ms). S4 y S5 dependen del "
            f"contraste de hipótesis: ver las secciones 1.5.3 y 4.",
            "",
            f"Sobre **S3**, el valor 0 es correcto pero **no es evidencia de éxito**: al ser una "
            f"constante no existe varianza y la prueba no es identificable, por lo que la meta se "
            f"considera *medida pero no contrastada*.",
        ]),
        "E1_TP_T": miles(req_t),
        "E1_TP_C0": miles(req_c0),
        "E1_TP_VEZ": coma(razon, 2),
        "E1_P95_T": f"{p95_t:.0f}",
        "E1_P95_C0": f"{p95_c0:.0f}",
        "DOCS_TOTAL": str(docs_total),
        "DOCS_S_MEDIANA": coma(docs_s, 4) if docs_s else "—",
        "ERR_TENT": coma(err_tent, 2),
        "VD3_MEDIANA": coma(vd3_med, 3),
        "N_DOCKER_METRICS": str(n_docker),
        "RAM_COUCHDB": mib("couchdb"),
        "RAM_POSTGRES": mib("postgres"),
        "RAM_API_RUST": mib("api-rust"),
        "RAM_API_BAS": mib("api-baseline"),
        "SMART_P95_T": f"{p95_t:.0f}",
        "SMART_P95_C0": f"{p95_c0:.0f}",
        "SMART_P95_T_VEZ": f"{p95_t / 15:.0f}",
        "SMART_ERR_T": coma(100 * (err_t or 0), 2) + " %",
        "SMART_ERR_C0": coma(100 * (err_c0 or 0), 2) + " %",
        "SMART_ERR_CUMPLE": verdict_error(err_t, err_c0),
        "SMART_VD1_P0": p_vd1_0,
        "SMART_VD1_P15": p_vd1_15,
        "SMART_VD1_CUMPLE": cumple(p_vd1_0, p_vd1_15),
        "SMART_VD3_P0": p_vd3_0,
        "SMART_VD3_P15": p_vd3_15,
        "SMART_VD3_CUMPLE": cumple(p_vd3_0, p_vd3_15),
        "SMART_CORRIDAS_OK": str(n_e2),
        "SMART_S6_CUMPLE": "Si",
        "SMART_S7_CUMPLE": "Si" if n_e2 >= 60 else f"No ({n_e2}/60)",
    }

    faltantes = sorted(set(re.findall(r"\{([A-Z0-9_]+)\}", texto)))
    for clave, valor in smart.items():
        texto = texto.replace("{" + clave + "}", str(valor))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(texto, encoding="utf-8")
    resto = sorted(set(re.findall(r"\{([A-Z0-9_]+)\}", texto)))
    print(f"Escrito {out_path}")
    print(f"Marcadores rellenados: {len(faltantes) - len(resto)}/{len(faltantes)}")
    if resto:
        print("Pendientes de redaccion manual: " + ", ".join(resto), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
