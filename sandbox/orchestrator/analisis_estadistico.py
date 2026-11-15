#!/usr/bin/env python3
"""Analisis estadistico de la Fase 5 a partir de los resumenes del sandbox.

Uso:
    /tmp/venv-analysis/bin/python sandbox/orchestrator/analisis_estadistico.py

Lee results/resumen_*.json (E2), results/resumen_k6_*.json (E1) y, cuando existen,
results/metricas_proceso_*.json y results/metricas_docker_*.json. Escribe:
    results/analisis_fase5.json
    results/analisis_fase5.md

El analisis inferencial se ejecuta sobre el subconjunto balanceado disponible:
10 dispositivos, 60 s, perdida 0 % y 15 %, con N replicas por brazo (N se calcula
desde los resultados disponibles). No sustituye la matriz completa de 360 corridas;
esa limitacion se informa en el JSON y el Markdown.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.formula.api import ols
from statsmodels.stats.anova import anova_lm
from statsmodels.stats.power import TTestIndPower

AQUI = pathlib.Path(__file__).resolve().parent
RAIZ = AQUI.parent
RES = RAIZ / "results"
METRICAS = ["vd1_docs_por_s", "vd2_tfs", "vd3_mediana_s", "tasa_error_por_intento"]
NOMBRES = {
    "vd1_docs_por_s": "VD1 throughput (docs/s)",
    "vd2_tfs": "VD2 TFS (proporcion)",
    "vd3_mediana_s": "VD3 resincronizacion (s)",
    "tasa_error_por_intento": "Tasa de error por intento",
}


def cargar_e2() -> list[dict]:
    filas = []
    for p in sorted(RES.glob("resumen_*.json")):
        if p.name.startswith("resumen_k6_"):
            continue
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        c = d.get("config", {})
        if c.get("arch") not in ("T", "C0") or "generados_total" not in d:
            continue
        base = c.get("netem_base") or ""
        m = re.search(r"loss\s+(\d+(?:\.\d+)?)%", base)
        perdida = float(m.group(1)) if m else 0.0
        rid = c.get("run_id") or p.stem.removeprefix("resumen_")
        rm = re.search(r"-r(\d+)-", rid)
        filas.append({
            "run_id": rid,
            "arch": c["arch"],
            "loss_pct": perdida,
            "devices": int(c.get("dispositivos", 0)),
            "rep": int(rm.group(1)) if rm else None,
            "run_s": c.get("run_s"),
            "warmup_s": c.get("calentamiento_s"),
            "measure_s": c.get("medicion_s"),
            "drain_s": c.get("drenaje_s"),
            "seed": c.get("semilla"),
            "generados_total": d.get("generados_total"),
            "generados_ventana": d.get("generados_ventana"),
            "vd1_docs_por_s": d.get("vd1_docs_por_s"),
            "vd2_tfs": d.get("vd2_tfs"),
            "vd3_mediana_s": d.get("vd3_mediana_s"),
            "tasa_error_por_intento": d.get("tasa_error_por_intento"),
            "intentos_total": d.get("intentos_total"),
            "intentos_fallidos": d.get("intentos_fallidos"),
            "archivo": p.name,
        })
    return filas


def cargar_k6() -> list[dict]:
    filas = []
    for p in sorted(RES.glob("resumen_k6_*.json")):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        met = d.get("metrics", {})
        lat = met.get("lat_write", {}) or {}
        dur = met.get("http_req_duration", {}) or {}
        req = met.get("http_reqs", {}) or {}
        fall = met.get("http_req_failed", {}) or {}
        checks = d.get("root_group", {}).get("checks", {}) or {}
        rid = p.stem.removeprefix("resumen_k6_")
        m = re.match(r"e1-formal-(T|C0)-(\d+)", rid)
        filas.append({
            "run_id": rid,
            "arch": m.group(1) if m else ("T" if "T" in rid else "C0"),
            "vus": int(m.group(2)) if m else None,
            "formal": bool(m),
            "p95_escritura_ms": lat.get("p(95)"),
            "p95_http_ms": dur.get("p(95)"),
            "peticiones": req.get("count"),
            "http_req_failed_rate": fall.get("value"),
            "checks": checks,
            "umbral_lat_write": lat.get("thresholds"),
        })
    return filas


def cargar_proceso() -> dict[str, dict]:
    out = {}
    for p in RES.glob("metricas_proceso_*.json"):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        rid = p.stem.removeprefix("metricas_proceso_")
        out[rid] = d.get("proceso", {})
    return out


def cargar_docker() -> dict[str, dict]:
    out = {}
    for p in RES.glob("metricas_docker_*.json"):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        rid = p.stem.removeprefix("metricas_docker_")
        out[rid] = d.get("servicios", {})
    return out


def describir(xs: list[float]) -> dict:
    a = np.asarray([x for x in xs if x is not None and math.isfinite(float(x))], dtype=float)
    if a.size == 0:
        return {"n": 0}
    return {
        "n": int(a.size),
        "media": round(float(a.mean()), 6),
        "desv_est": round(float(a.std(ddof=1)), 6) if a.size > 1 else 0.0,
        "mediana": round(float(np.median(a)), 6),
        "q1": round(float(np.percentile(a, 25)), 6),
        "q3": round(float(np.percentile(a, 75)), 6),
        "min": round(float(a.min()), 6),
        "max": round(float(a.max()), 6),
    }


def cliffs_delta(x: list[float], y: list[float]) -> float | None:
    x = [float(v) for v in x if v is not None]
    y = [float(v) for v in y if v is not None]
    if not x or not y:
        return None
    u = stats.mannwhitneyu(x, y, alternative="two-sided").statistic
    return round(float(2 * u / (len(x) * len(y)) - 1), 4)


def prueba_mann_whitney(t: list[float], c: list[float], alternativa: str) -> dict:
    t = [float(v) for v in t if v is not None]
    c = [float(v) for v in c if v is not None]
    if len(t) < 3 or len(c) < 3:
        return {"ejecutada": False, "motivo": "se requieren al menos 3 observaciones por grupo"}
    if len(set(t + c)) == 1:
        return {"ejecutada": False, "motivo": "varianza nula (todas las observaciones iguales)"}
    r = stats.mannwhitneyu(t, c, alternative=alternativa, method="auto")
    return {
        "ejecutada": True,
        "alternativa": alternativa,
        "n_T": len(t),
        "n_C0": len(c),
        "U": round(float(r.statistic), 3),
        "p_valor": round(float(r.pvalue), 6),
        "delta_cliff": cliffs_delta(t, c),
    }


def holm(pvals: list[tuple[str, float]]) -> list[dict]:
    validos = sorted([(k, p) for k, p in pvals if p is not None and math.isfinite(p)], key=lambda x: x[1])
    m = len(validos)
    out = []
    for i, (nombre, p) in enumerate(validos):
        ajustado = min(1.0, p * (m - i))
        out.append({"prueba": nombre, "p": p, "p_holm": round(ajustado, 6)})
    return out


def wilcoxon_pareado(t: pd.DataFrame, c: pd.DataFrame, metrica: str) -> dict:
    """Sensibilidad pareada: T y C0 comparten semilla en cada repeticion (por perdida)."""
    a = t[["rep", metrica]].dropna()
    b = c[["rep", metrica]].dropna()
    m = a.merge(b, on="rep", suffixes=("_T", "_C0"))
    if len(m) < 5:
        return {"ejecutada": False, "motivo": "se requieren al menos 5 pares"}
    d = (m[f"{metrica}_T"] - m[f"{metrica}_C0"]).astype(float)
    if float(d.abs().sum()) == 0.0:
        return {"ejecutada": False, "motivo": "varianza nula (todas las diferencias son cero)"}
    r = stats.wilcoxon(m[f"{metrica}_T"], m[f"{metrica}_C0"], alternative="two-sided", method="auto")
    return {
        "ejecutada": True,
        "n_pares": int(len(m)),
        "W": round(float(r.statistic), 3),
        "p_valor": round(float(r.pvalue), 6),
        "diferencia_mediana_T_menos_C0": round(float(np.median(d)), 6),
    }


def bootstrap_dif_medianas(x: list, y: list, n: int = 10000, semilla: int = 20261101) -> dict:
    """IC percentil 95 % por bootstrap de la diferencia de medianas (T - C0)."""
    ax = np.asarray([float(v) for v in x if v is not None], dtype=float)
    ay = np.asarray([float(v) for v in y if v is not None], dtype=float)
    if ax.size < 3 or ay.size < 3:
        return {"ejecutada": False, "motivo": "se requieren al menos 3 observaciones por grupo"}
    if float(np.std(ax)) == 0.0 and float(np.std(ay)) == 0.0 and float(np.median(ax) - np.median(ay)) == 0.0:
        return {"ejecutada": False, "motivo": "varianza nula en ambos grupos"}
    rng = np.random.default_rng(semilla)
    difs = np.median(rng.choice(ax, size=(n, ax.size), replace=True), axis=1) - \
        np.median(rng.choice(ay, size=(n, ay.size), replace=True), axis=1)
    lo, hi = np.percentile(difs, [2.5, 97.5])
    return {
        "ejecutada": True,
        "remuestreos": n,
        "diferencia_medianas_T_menos_C0": round(float(np.median(ax) - np.median(ay)), 6),
        "ic95": [round(float(lo), 6), round(float(hi), 6)],
        "ic95_incluye_cero": bool(lo <= 0.0 <= hi),
    }


def anova_rangos(df: pd.DataFrame, metrica: str) -> dict:
    d = df[["arch", "loss_pct", metrica]].dropna().copy()
    if d[metrica].nunique() < 2:
        return {"ejecutada": False, "motivo": "variable constante"}
    d["rango"] = stats.rankdata(d[metrica].to_numpy())
    modelo = ols("rango ~ C(arch) * C(loss_pct)", data=d).fit()
    tabla = anova_lm(modelo, typ=2)
    ss_res = float(tabla.loc["Residual", "sum_sq"])
    terminos = {}
    for nombre in tabla.index:
        if nombre == "Residual":
            continue
        ss = float(tabla.loc[nombre, "sum_sq"])
        terminos[nombre] = {
            "F": round(float(tabla.loc[nombre, "F"]), 4),
            "p_valor": round(float(tabla.loc[nombre, "PR(>F)"]), 6),
            "eta2_parcial": round(ss / (ss + ss_res), 4) if (ss + ss_res) > 0 else None,
        }
    resid = modelo.resid
    sh = stats.shapiro(resid) if len(resid) >= 3 else None
    return {
        "ejecutada": True,
        "metodo": "ANOVA factorial sobre rangos (aproximacion a ART), tip=2",
        "n": int(len(d)),
        "terminos": terminos,
        "shapiro_residuos_p": round(float(sh.pvalue), 6) if sh else None,
    }


def analisis_energia() -> dict:
    pot = TTestIndPower()
    filas = []
    for d in (0.8, 1.0, 1.2, 1.5):
        filas.append({
            "d": d,
            "n10": round(float(pot.power(effect_size=d, nobs1=10, alpha=0.025, ratio=1.0, alternative="larger")), 4),
            "n15": round(float(pot.power(effect_size=d, nobs1=15, alpha=0.025, ratio=1.0, alternative="larger")), 4),
            "n20": round(float(pot.power(effect_size=d, nobs1=20, alpha=0.025, ratio=1.0, alternative="larger")), 4),
        })
    n80 = {}
    for d in (0.8, 1.0, 1.2, 1.5):
        n80[str(d)] = int(math.ceil(float(pot.solve_power(effect_size=d, power=0.80, alpha=0.025,
                                                          ratio=1.0, alternative="larger"))))
    return {"alfa": 0.025, "unilateral": True, "tabla": filas, "n_para_potencia_080": n80}


def main() -> None:
    global RES
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--resultados", default=str(RES))
    ap.add_argument("--salida-json", default=str(RES / "analisis_fase5.json"))
    ap.add_argument("--salida-md", default=str(RES / "analisis_fase5.md"))
    ap.add_argument("--devices", default="10", help="dispositivos a incluir, separados por coma (defecto: 10)")
    ap.add_argument("--perdidas", default="0,15", help="perdidas (%%) a incluir, separadas por coma (defecto: 0,15)")
    ap.add_argument("--run-s", type=int, default=60, help="duracion de corrida a incluir, en s (defecto: 60)")
    args = ap.parse_args()
    f_dev = [int(x) for x in args.devices.split(",") if x.strip()]
    f_loss = [float(x) for x in args.perdidas.split(",") if x.strip()]

    RES = pathlib.Path(args.resultados)
    e2 = cargar_e2()
    k6 = cargar_k6()
    proc = cargar_proceso()
    dock = cargar_docker()
    for f in e2:
        f["proceso"] = proc.get(f["run_id"])
        f["docker"] = dock.get(f["run_id"])

    df = pd.DataFrame(e2)
    balanceado = df[(df.devices.isin(f_dev)) & (df.run_s == args.run_s) & (df.loss_pct.isin(f_loss))].copy()

    # Replicas por celda (brazo x perdida); se reporta en lugar de un valor fijo.
    celdas = balanceado.groupby(["arch", "loss_pct"]).size()
    ns = sorted({int(v) for v in celdas})
    replica_txt = (
        f"{ns[0]} replicas por brazo" if len(ns) == 1
        else "replicas por celda: " + ", ".join(f"{k[0]}|{k[1]:g}={int(v)}" for k, v in celdas.items())
    )
    replica_json = {f"{k[0]}|{k[1]:g}": int(v) for k, v in celdas.items()}

    descriptivo = {}
    for (arch, loss), g in balanceado.groupby(["arch", "loss_pct"]):
        key = f"{arch}|{loss:g}"
        descriptivo[key] = {m: describir(g[m].tolist()) for m in METRICAS}

    normalidad = {}
    for (arch, loss), g in balanceado.groupby(["arch", "loss_pct"]):
        normalidad[f"{arch}|{loss:g}"] = {}
        for m in METRICAS:
            vals = [float(v) for v in g[m].dropna().tolist()]
            if len(vals) >= 3 and len(set(vals)) > 1:
                r = stats.shapiro(vals)
                normalidad[f"{arch}|{loss:g}"][m] = {
                    "n": len(vals), "W": round(float(r.statistic), 4), "p_valor": round(float(r.pvalue), 6),
                }
            else:
                normalidad[f"{arch}|{loss:g}"][m] = {"n": len(vals), "motivo": "n<3 o varianza nula"}

    pruebas = {}
    p_sec = []
    for loss in sorted(balanceado.loss_pct.unique()):
        t = balanceado[(balanceado.arch == "T") & (balanceado.loss_pct == loss)]
        c = balanceado[(balanceado.arch == "C0") & (balanceado.loss_pct == loss)]
        pruebas[f"{loss:g}"] = {
            "vd1_docs_por_s": prueba_mann_whitney(t.vd1_docs_por_s.tolist(), c.vd1_docs_por_s.tolist(), "greater"),
            "vd2_tfs": prueba_mann_whitney(t.vd2_tfs.tolist(), c.vd2_tfs.tolist(), "less"),
            "vd3_mediana_s": prueba_mann_whitney(t.vd3_mediana_s.tolist(), c.vd3_mediana_s.tolist(), "less"),
            "tasa_error_por_intento": prueba_mann_whitney(t.tasa_error_por_intento.tolist(), c.tasa_error_por_intento.tolist(), "less"),
        }
        for nombre in ("vd3_mediana_s", "tasa_error_por_intento"):
            p = pruebas[f"{loss:g}"][nombre].get("p_valor")
            if p is not None:
                p_sec.append((f"loss={loss:g}:{nombre}", p))

    # Sensibilidad pareada por semilla y tamano de efecto con IC bootstrap.
    pareadas = {}
    boot = {}
    for loss in sorted(balanceado.loss_pct.unique()):
        t = balanceado[(balanceado.arch == "T") & (balanceado.loss_pct == loss)]
        c = balanceado[(balanceado.arch == "C0") & (balanceado.loss_pct == loss)]
        clave = f"{loss:g}"
        pareadas[clave] = {m: wilcoxon_pareado(t, c, m) for m in
                           ("vd1_docs_por_s", "vd3_mediana_s", "tasa_error_por_intento")}
        boot[clave] = {m: bootstrap_dif_medianas(t[m].tolist(), c[m].tolist()) for m in
                       ("vd1_docs_por_s", "vd3_mediana_s")}

    factorial = {m: anova_rangos(balanceado, m) for m in ("vd1_docs_por_s", "vd2_tfs", "vd3_mediana_s", "tasa_error_por_intento")}
    energia = analisis_energia()

    e1_formal = [x for x in k6 if x["formal"] and x["vus"] == 500]
    e1 = {x["arch"]: x for x in e1_formal}
    smart = {
        "meta_p95_ms": 15.0,
        "e1_formal_500vus": e1,
        "cumple_p95_T": bool(e1.get("T", {}).get("p95_escritura_ms") is not None and e1["T"]["p95_escritura_ms"] < 15),
        "cumple_p95_C0": bool(e1.get("C0", {}).get("p95_escritura_ms") is not None and e1["C0"]["p95_escritura_ms"] < 15),
        "brecha_T_veces": round(float(e1["T"]["p95_escritura_ms"]) / 15, 2) if "T" in e1 and e1["T"].get("p95_escritura_ms") else None,
        "e2_tfs_objetivo": 0.01,
        "e2_tfs_T_mediana": descriptivo.get("T|0", {}).get("vd2_tfs", {}).get("mediana"),
        "e2_tfs_C0_mediana": descriptivo.get("C0|0", {}).get("vd2_tfs", {}).get("mediana"),
    }

    t_med = descriptivo.get("T|0", {}).get("vd1_docs_por_s", {}).get("mediana")
    if not t_med:
        t_med = descriptivo.get("T|15", {}).get("vd1_docs_por_s", {}).get("mediana")
    escenarios = []
    for docs_s in (1.0, 4.3, 10.0, 50.0):
        cap_mes = docs_s * 86400 * 30
        for usd in (6, 12, 24):
            escenarios.append({
                "throughput_docs_s": docs_s,
                "docs_mes": int(cap_mes),
                "vps_usd_mes": usd,
                "usd_por_millon": round(usd / (cap_mes / 1_000_000), 2),
            })
    viabilidad = {
        "supuestos": "VPS de bajo costo; 30 dias/mes; no incluye almacenamiento, respaldo ni soporte.",
        "throughput_piloto_docs_s": t_med,
        "escenarios": escenarios,
    }

    salida = {
        "generado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "alcance": {
            "corridas_e2_totales_en_results": int(len(df)),
            "corridas_e2_balanceadas_usadas": int(len(balanceado)),
            "matriz_objetivo": 360,
            "cobertura_balanceada_pct": round(100 * len(balanceado) / 360, 2),
            "replicas_por_celda": replica_json,
            "nota": f"Subconjunto exploratorio: 10 dispositivos, 60 s, perdida 0/15 %, {replica_txt}. No sustituye las 360 corridas.",
        },
        "corridas": e2,
        "descriptivo": descriptivo,
        "normalidad_shapiro": normalidad,
        "pruebas_hipotesis": pruebas,
        "pruebas_pareadas_wilcoxon": pareadas,
        "ic_bootstrap_medianas": boot,
        "holm_secundarias": holm(p_sec),
        "factorial_rangos": factorial,
        "energia": energia,
        "smart": smart,
        "viabilidad": viabilidad,
        "k6_todos": k6,
    }
    pathlib.Path(args.salida_json).write_text(json.dumps(salida, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    cols = ["run_id", "arch", "loss_pct", "devices", "rep", "run_s", "seed", "generados_total",
            "vd1_docs_por_s", "vd2_tfs", "vd3_mediana_s", "tasa_error_por_intento"]
    (RES / "datos_fase5.csv").write_text(balanceado[cols].to_csv(index=False), encoding="utf-8")

    # ---------------------------------------------------------------- Markdown
    L = []
    A = L.append
    A("# Analisis estadistico de la Fase 5\n")
    A(f"Generado: {salida['generado_utc']} (UTC).\n")
    A("## Alcance y validez\n")
    A(f"- Corridas E2 disponibles: **{len(df)}**. Subconjunto balanceado usado: **{len(balanceado)}**.")
    perd_txt = " y ".join(f"{p:g} %" for p in sorted(f_loss))
    A(f"- Diseno del subconjunto: {', '.join(str(d) for d in f_dev)} dispositivos, {args.run_s} s, "
      f"perdida {perd_txt}, {replica_txt} (T y C0).")
    A("- La matriz completa del protocolo es de **360 corridas** (2 x 4 x 3 x 15); este analisis cubre "
      f"**{salida['alcance']['cobertura_balanceada_pct']} %**. Es exploratorio y no reemplaza el experimento final.")
    if balanceado["vd2_tfs"].nunique() < 2:
        A("- TFS se observo constante en todos los grupos; una prueba de hipotesis sobre una constante no es identificable.\n")
    else:
        A("- TFS presenta variacion entre corridas; las pruebas de H1b son identificables.\n")
    A("## Estadistica descriptiva (subconjunto balanceado)\n")
    A("| Brazo | Perdida | Metrica | n | Mediana | Media | DE | Q1 | Q3 |")
    A("|---|---:|---|---:|---:|---:|---:|---:|---:|")
    for key, metrics in descriptivo.items():
        arch, loss = key.split("|")
        for m, d in metrics.items():
            if d.get("n"):
                A(f"| {arch} | {loss}% | {NOMBRES[m]} | {d['n']} | {d['mediana']:.4g} | {d['media']:.4g} | "
                  f"{d['desv_est']:.4g} | {d['q1']:.4g} | {d['q3']:.4g} |")
    A("\n## Pruebas de normalidad (Shapiro-Wilk)\n")
    A("| Grupo | Metrica | n | W | p |")
    A("|---|---|---:|---:|---:|")
    for g, ms in normalidad.items():
        for m, d in ms.items():
            if "W" in d:
                A(f"| {g} | {NOMBRES[m]} | {d['n']} | {d['W']} | {d['p_valor']} |")
            else:
                A(f"| {g} | {NOMBRES[m]} | {d.get('n', 0)} | - | {d.get('motivo')} |")
    A("\n## Hipotesis operacionales por nivel de perdida\n")
    A("| Perdida | Metrica | Alternativa | U | p | Delta de Cliff |")
    A("|---:|---|---|---:|---:|---:|")
    for loss, ms in pruebas.items():
        for m, d in ms.items():
            if d.get("ejecutada"):
                A(f"| {loss}% | {NOMBRES[m]} | {d['alternativa']} | {d['U']} | {d['p_valor']} | {d['delta_cliff']} |")
            else:
                A(f"| {loss}% | {NOMBRES[m]} | - | - | - | {d.get('motivo')} |")
    A("\n## Contraste pareado por semilla (Wilcoxon, analisis de sensibilidad)\n")
    A("| Perdida | Metrica | n pares | W | p | Dif. mediana (T-C0) |")
    A("|---:|---|---:|---:|---:|---:|")
    for loss, ms in pareadas.items():
        for m, d in ms.items():
            if d.get("ejecutada"):
                A(f"| {loss}% | {NOMBRES[m]} | {d['n_pares']} | {d['W']} | {d['p_valor']} | "
                  f"{d['diferencia_mediana_T_menos_C0']:.4g} |")
            else:
                A(f"| {loss}% | {NOMBRES[m]} | - | - | - | {d.get('motivo')} |")
    A("\nT y C0 comparten semilla en cada repeticion, pero las corridas son secuenciales: "
      "la correspondencia de semillas no equivale a aleatorizacion simultanea.\n")

    A("## IC bootstrap 95 % de la diferencia de medianas (T - C0)\n")
    A("| Perdida | Metrica | Dif. mediana | IC 95 % | Incluye 0 |")
    A("|---:|---|---:|---|---|")
    for loss, ms in boot.items():
        for m, d in ms.items():
            if d.get("ejecutada"):
                ic = f"[{d['ic95'][0]:.4g}, {d['ic95'][1]:.4g}]"
                A(f"| {loss}% | {NOMBRES[m]} | {d['diferencia_medianas_T_menos_C0']:.4g} | {ic} | "
                  f"{'Si' if d['ic95_incluye_cero'] else 'No'} |")
            else:
                A(f"| {loss}% | {NOMBRES[m]} | - | - | {d.get('motivo')} |")
    A("\n## ANOVA factorial sobre rangos\n")
    A("| Metrica | Termino | F | p | eta2 parcial |")
    A("|---|---|---:|---:|---:|")
    for m, d in factorial.items():
        if not d.get("ejecutada"):
            A(f"| {NOMBRES[m]} | - | - | - | {d.get('motivo')} |")
            continue
        for term, v in d["terminos"].items():
            A(f"| {NOMBRES[m]} | {term} | {v['F']} | {v['p_valor']} | {v['eta2_parcial']} |")
    A("\n## Correccion de Holm (hipotesis secundarias)\n")
    if salida["holm_secundarias"]:
        A("| Prueba | p | p Holm |")
        A("|---|---:|---:|")
        for x in salida["holm_secundarias"]:
            A(f"| {x['prueba']} | {x['p']} | {x['p_holm']} |")
    else:
        A("No se pudieron calcular pruebas secundarias.")
    A("\n## Potencia estadistica (t unilateral, alfa = 0,025)\n")
    A("| d de Cohen | n=10 | n=15 | n=20 |")
    A("|---:|---:|---:|---:|")
    for x in energia["tabla"]:
        A(f"| {x['d']} | {x['n10']} | {x['n15']} | {x['n20']} |")
    A("\n## Metas SMART y E1\n")
    A("| Brazo | p95 escritura E1, 500 VUs | Meta | Cumple |")
    A("|---|---:|---:|---|")
    for arch in ("T", "C0"):
        x = e1.get(arch, {})
        p95 = x.get("p95_escritura_ms")
        valor = f"{p95:.2f} ms" if p95 is not None else "-"
        A(f"| {arch} | {valor} | < 15 ms | {'Si' if smart['cumple_p95_' + arch] else 'No'} |")
    A(f"\nEl p95 de T esta **{smart['brecha_T_veces']}x** por encima de la meta de 15 ms en este hardware.")
    A("\n## Viabilidad economica (modelo, no cotizacion)\n")
    A("| Throughput | Docs/mes | VPS USD/mes | USD por millon |")
    A("|---:|---:|---:|---:|")
    for x in escenarios:
        A(f"| {x['throughput_docs_s']} docs/s | {x['docs_mes']:,} | {x['vps_usd_mes']} | {x['usd_por_millon']} |")
    A("\n" + salida["viabilidad"]["supuestos"])
    pathlib.Path(args.salida_md).write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"Escrito {args.salida_json} y {args.salida_md}")
    print(f"Corridas E2: {len(df)} | balanceadas: {len(balanceado)}")


if __name__ == "__main__":
    main()