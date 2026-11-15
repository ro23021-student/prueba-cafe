#!/usr/bin/env python3
"""Metricas de proceso del backend durante una corrida, consultando Prometheus.

Recolecta RSS, hilos, descriptores, CPU y tiempo de arranque del proceso Rust.
Uso: python3 orchestrator/metricas_proceso.py --inicio EPOCH --fin EPOCH
     [--run-id T-d10-s1] [--prom http://localhost:9090] [--salida results]
Escribe results/metricas_proceso_<run-id>.json. Solo biblioteca estandar."""
import argparse
import json
import statistics
import sys
import urllib.parse
import urllib.request

CONSULTAS = {
    "rss_mib": ('max(process_resident_memory_bytes{job="api-rust"})', 1 / 1048576),
    "hilos_so": ('max(process_threads{job="api-rust"})', 1),
    "fds_abiertos": ('max(process_open_fds{job="api-rust"})', 1),
    "cpu_nucleos": ('rate(process_cpu_seconds_total{job="api-rust"}[10s])', 1),
    "arranque_epoch": ('max(process_start_time_seconds{job="api-rust"})', 1),
}


def consultar_rango(prom, consulta, inicio, fin, paso=1):
    qs = urllib.parse.urlencode({"query": consulta, "start": inicio, "end": fin, "step": paso})
    with urllib.request.urlopen(f"{prom}/api/v1/query_range?{qs}", timeout=30) as r:
        cuerpo = json.load(r)
    if cuerpo.get("status") != "success":
        raise RuntimeError(f"Prometheus respondio {cuerpo}")
    valores = []
    for serie in cuerpo["data"]["result"]:
        valores += [float(v) for _, v in serie["values"] if v not in ("NaN", "+Inf", "-Inf")]
    return valores


def resumen(valores, escala=1.0):
    if not valores:
        return None
    return {"media": round(statistics.fmean(valores) * escala, 4),
            "pico": round(max(valores) * escala, 4),
            "muestras": len(valores)}


def main(argv=None):
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--prom", default="http://localhost:9090")
    a.add_argument("--inicio", type=int, required=True)
    a.add_argument("--fin", type=int, required=True)
    a.add_argument("--run-id", default="manual")
    a.add_argument("--salida", default="results")
    args = a.parse_args(argv)
    if args.fin <= args.inicio:
        sys.exit("--fin debe ser mayor que --inicio")
    datos = {"ventana": {"inicio": args.inicio, "fin": args.fin}, "proceso": {}}
    for nombre, (consulta, escala) in CONSULTAS.items():
        datos["proceso"][nombre] = resumen(consultar_rango(args.prom, consulta, args.inicio, args.fin), escala)
    ruta = f"{args.salida}/metricas_proceso_{args.run_id}.json"
    with open(ruta, "w") as f:
        json.dump(datos, f, indent=2)
    print(f"Escrito {ruta}")
    for nombre, valor in datos["proceso"].items():
        if valor:
            print(f"  {nombre:15} media {valor['media']:.3f} pico {valor['pico']:.3f}")


if __name__ == "__main__":
    main()
