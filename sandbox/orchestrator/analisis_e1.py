#!/usr/bin/env python3
"""Analisis estadistico de E1 (estres del backend, sin degradacion de red).

Lee, desde results/:
  - resumen_k6_e1-rep-<T|C0>-500-r<N>.json   (replicas a 500 VUs)
  - metricas_docker_e1-rep-<T|C0>-500-r<N>.json (RAM/CPU por servicio)
  - resumen_k6_e1-curva-<T|C0>-<VUs>.json    (curva de latencia, una corrida por punto)

Escribe results/analisis_e1.json y results/analisis_e1.md.
Uso: python3 orchestrator/analisis_e1.py [--results results]
"""
import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from scipy.stats import mannwhitneyu

SEMILLA = 20261112
ALFA = 0.05
UMBRALES_MS = [15, 50, 100, 250, 500, 1000]


def cargar_json(p: Path):
    try:
        return json.loads(p.read_text())
    except Exception:
        return None


def metricas_k6(d: dict) -> dict:
    m = d["metrics"]
    reqs = m["http_reqs"]
    lw = m["lat_write"]
    return {
        "duracion_s": reqs["count"] / reqs["rate"] if reqs.get("rate") else None,
        "req_s": reqs["rate"],
        "fallos_pct": 100 * m["http_req_failed"]["value"],
        "lat_med_ms": lw["med"],
        "lat_p90_ms": lw.get("p(90)"),
        "lat_p95_ms": lw["p(95)"],
        "lat_max_ms": lw.get("max"),
    }


def memoria_docker(res: Path, rid: str, arch: str) -> dict:
    d = cargar_json(res / f"metricas_docker_{rid}.json")
    out = {"ram_api_mib": None, "ram_bd_mib": None, "ram_total_mib": None, "cpu_bd_pct": None}
    if not d:
        return out
    s = d.get("servicios", {})
    api, bd = ("api-rust", "couchdb") if arch == "T" else ("api-baseline", "postgres")
    try:
        ra = s[api]["ram_mib"]["media"]
        rb = s[bd]["ram_mib"]["media"]
        out.update(ram_api_mib=ra, ram_bd_mib=rb, ram_total_mib=ra + rb,
                   cpu_bd_pct=s[bd]["cpu_pct"]["media"])
    except Exception:
        pass
    return out


def cliff(x, y) -> float:
    return sum(int(a > b) - int(a < b) for a in x for b in y) / (len(x) * len(y))


def bootstrap_dif_mediana(x, y, n=10000):
    rng = np.random.default_rng(SEMILLA)
    x, y = np.asarray(x, float), np.asarray(y, float)
    difs = [np.median(rng.choice(x, len(x))) - np.median(rng.choice(y, len(y))) for _ in range(n)]
    lo, hi = np.percentile(difs, [2.5, 97.5])
    return float(np.median(x) - np.median(y)), float(lo), float(hi)


def comparar(t, c, alternativa):
    t, c = np.asarray(t, float), np.asarray(c, float)
    if np.ptp(np.concatenate([t, c])) == 0:
        return {"p_unilateral": None, "p_bilateral": None, "U": None, "cliff": 0.0, "nota": "constante"}
    u, p1 = mannwhitneyu(t, c, alternative=alternativa)
    _, p2 = mannwhitneyu(t, c, alternative="two-sided")
    dif, lo, hi = bootstrap_dif_mediana(t, c)
    return {"U": float(u), "p_unilateral": float(p1), "p_bilateral": float(p2),
            "cliff": cliff(t, c), "dif_mediana": dif, "ic95": [lo, hi]}


def desc(xs):
    a = np.asarray([x for x in xs if x is not None], float)
    if not len(a):
        return None
    return {"n": int(len(a)), "mediana": float(np.median(a)), "media": float(a.mean()),
            "de": float(a.std(ddof=1)) if len(a) > 1 else 0.0,
            "min": float(a.min()), "max": float(a.max())}


def fmt(x, nd=2):
    return "-" if x is None else (f"{x:.{nd}f}" if isinstance(x, (int, float)) else str(x))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results")
    args = ap.parse_args()
    res = Path(args.results)

    # ---- Replicas a 500 VUs ----
    reps = []
    for f in sorted(res.glob("resumen_k6_e1-rep-*-500-r*.json")):
        m = re.search(r"e1-rep-(T|C0)-500-r(\d+)", f.name)
        d = cargar_json(f)
        if not m or not d:
            continue
        rid = f"e1-rep-{m[1]}-500-r{m[2]}"
        fila = {"arch": m[1], "rep": int(m[2])}
        fila.update(metricas_k6(d))
        fila.update(memoria_docker(res, rid, m[1]))
        reps.append(fila)

    por = {a: [r for r in reps if r["arch"] == a] for a in ("T", "C0")}
    claves = [("req_s", "Throughput (req/s)", "greater"),
              ("lat_med_ms", "Latencia mediana de escritura (ms)", "less"),
              ("lat_p95_ms", "Latencia p95 de escritura (ms)", "less"),
              ("fallos_pct", "Fallos de peticion (%)", "less"),
              ("ram_total_mib", "RAM API + BD (MiB)", "less"),
              ("cpu_bd_pct", "CPU de la BD (%)", "less")]
    comp, descr = {}, {}
    for k, _, alt in claves:
        t = [r[k] for r in por["T"] if r[k] is not None]
        c = [r[k] for r in por["C0"] if r[k] is not None]
        descr[k] = {"T": desc(t), "C0": desc(c)}
        if len(t) >= 3 and len(c) >= 3:
            comp[k] = comparar(t, c, alt)

    # ---- Curva de latencia ----
    curva = []
    for f in sorted(res.glob("resumen_k6_e1-curva-*.json")):
        m = re.search(r"e1-curva-(T|C0)-(\d+)\.json", f.name)
        d = cargar_json(f)
        if not m or not d:
            continue
        fila = {"arch": m[1], "vus": int(m[2])}
        fila.update(metricas_k6(d))
        fila.update(memoria_docker(res, f"e1-curva-{m[1]}-{m[2]}", m[1]))
        curva.append(fila)
    curva.sort(key=lambda r: (r["vus"], r["arch"]))

    capacidad = {}
    for a in ("T", "C0"):
        capacidad[a] = {}
        puntos = sorted([r for r in curva if r["arch"] == a], key=lambda r: r["vus"])
        for u in UMBRALES_MS:
            ok = [r["vus"] for r in puntos if r["lat_p95_ms"] is not None and r["lat_p95_ms"] < u]
            capacidad[a][str(u)] = max(ok) if ok else None

    salida = {"generado": datetime.now(timezone.utc).isoformat(timespec="seconds"),
              "replicas_500vus": reps, "descriptiva": descr, "pruebas": comp,
              "curva": curva, "vus_max_con_p95_bajo_umbral_ms": capacidad}
    (res / "analisis_e1.json").write_text(json.dumps(salida, indent=2, ensure_ascii=False))

    # ---- Informe Markdown ----
    L = []
    A = L.append
    A("# Analisis E1 (estres del backend, sin degradacion de red)\n")
    A(f"Generado: {salida['generado']} (UTC).\n")
    A("## Replicas a 500 usuarios virtuales\n")
    A(f"Replicas: T = {len(por['T'])}, C0 = {len(por['C0'])}. Duracion de cada corrida: ~300 s "
      "(rampa de subida, 240 s a 500 VUs y rampa de bajada).\n")
    A("| Arq | Rep | Duracion (s) | req/s | Fallos (%) | Lat. med (ms) | Lat. p95 (ms) | RAM API+BD (MiB) | CPU BD (%) |")
    A("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for r in sorted(reps, key=lambda r: (r["arch"], r["rep"])):
        A(f"| {r['arch']} | {r['rep']} | {fmt(r['duracion_s'], 0)} | {fmt(r['req_s'], 1)} | {fmt(r['fallos_pct'])} | "
          f"{fmt(r['lat_med_ms'], 0)} | {fmt(r['lat_p95_ms'], 0)} | {fmt(r['ram_total_mib'], 0)} | {fmt(r['cpu_bd_pct'], 0)} |")
    A("\n## Comparacion T vs C0 (Mann-Whitney, alfa = 0,05)\n")
    A("Hipotesis unilaterales: T mayor en throughput; T menor en latencia, fallos, RAM y CPU. "
      "Con n = 5 por grupo el p minimo posible es 0,004. Delta de Cliff: +1 = todo T > todo C0.\n")
    A("| Metrica | Mediana T | Mediana C0 | T/C0 | U | p unilateral | p bilateral | Cliff | IC95 dif. medianas (T-C0) |")
    A("|---|---:|---:|---:|---:|---:|---:|---:|---|")
    for k, nombre, _ in claves:
        dt, dc = descr[k]["T"], descr[k]["C0"]
        if not (dt and dc):
            continue
        p = comp.get(k, {})
        ratio = dt["mediana"] / dc["mediana"] if dc["mediana"] else None
        ic = p.get("ic95")
        A(f"| {nombre} | {fmt(dt['mediana'], 2)} | {fmt(dc['mediana'], 2)} | {fmt(ratio, 2)} | "
          f"{fmt(p.get('U'), 0)} | {fmt(p.get('p_unilateral'), 4)} | {fmt(p.get('p_bilateral'), 4)} | "
          f"{fmt(p.get('cliff'), 2)} | {('[' + fmt(ic[0], 1) + ', ' + fmt(ic[1], 1) + ']') if ic else '-'} |")
    A("\nLas diferencias con p unilateral < 0,05 se consideran significativas. No se aplica Holm "
      "porque estas seis comparaciones son descriptivas de E1 y la hipotesis primaria (throughput) es una sola.\n")

    A("## Curva de latencia (una corrida por punto, 120 s a carga constante)\n")
    if curva:
        A("| VUs | Arq | req/s | Fallos (%) | Lat. med (ms) | Lat. p90 (ms) | Lat. p95 (ms) | RAM API+BD (MiB) |")
        A("|---:|---|---:|---:|---:|---:|---:|---:|")
        for r in curva:
            A(f"| {r['vus']} | {r['arch']} | {fmt(r['req_s'], 1)} | {fmt(r['fallos_pct'])} | {fmt(r['lat_med_ms'], 0)} | "
              f"{fmt(r['lat_p90_ms'], 0)} | {fmt(r['lat_p95_ms'], 0)} | {fmt(r['ram_total_mib'], 0)} |")
        A("\nMayor carga probada (VUs) cuyo p95 de escritura queda por debajo de cada umbral:\n")
        A("| Umbral p95 | T | C0 |")
        A("|---:|---:|---:|")
        for u in UMBRALES_MS:
            A(f"| < {u} ms | {capacidad['T'][str(u)] or 'ninguna'} | {capacidad['C0'][str(u)] or 'ninguna'} |")
        A("\nUna sola corrida por punto: la curva describe la forma de la saturacion, no permite pruebas de hipotesis.\n")
    else:
        A("Sin datos de curva todavia.\n")

    A("## Meta SMART de latencia\n")
    if por["T"] and por["C0"]:
        pt, pc = descr["lat_p95_ms"]["T"], descr["lat_p95_ms"]["C0"]
        A(f"A 500 VUs el p95 de escritura es {fmt(pt['mediana'], 0)} ms (T) y {fmt(pc['mediana'], 0)} ms (C0): "
          f"la meta original de < 15 ms {'no se cumple' if min(pt['mediana'], pc['mediana']) >= 15 else 'se cumple en al menos un brazo'} "
          "en este equipo de 2 nucleos, donde la latencia es tiempo de espera en cola por saturacion. "
          "La meta debe expresarse para una carga concreta (ver tabla de umbrales).\n")
    (res / "analisis_e1.md").write_text("\n".join(L) + "\n")
    print(f"Escrito {res / 'analisis_e1.json'} y {res / 'analisis_e1.md'}")
    print(f"Replicas: T={len(por['T'])} C0={len(por['C0'])} | puntos de curva: {len(curva)}")


if __name__ == "__main__":
    main()
