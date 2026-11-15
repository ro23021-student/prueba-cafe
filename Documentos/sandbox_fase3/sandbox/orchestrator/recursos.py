#!/usr/bin/env python3
"""Resume CPU y memoria de cada servicio durante una corrida, consultando Prometheus (cAdvisor + /metrics).

Uso:  python3 orchestrator/recursos.py --inicio 1760000000 --fin 1760000300 [--prom http://localhost:9090]
        [--run-id T-d10-s1] [--salida results]
`inicio` y `fin` son epoch en segundos (la ventana de medicion de la corrida; el client-sim los guarda).
Escribe results/recursos_<run-id>.json. Metricas de producto (ISO/IEC 25010, eficiencia de desempeno):
CPU media y pico (nucleos), RAM media y pico (MiB) por servicio, y p95 de latencia interna del backend Rust.
Solo biblioteca estandar."""
import argparse
import json
import statistics
import sys
import urllib.parse
import urllib.request

SERVICIOS = ["api-rust", "couchdb", "api-baseline", "postgres", "client-sim", "prometheus", "cadvisor"]


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
        return None  # el servicio no estuvo activo en esta corrida (otro perfil)
    return {"media": round(statistics.fmean(valores) * escala, 4), "pico": round(max(valores) * escala, 4), "muestras": len(valores)}


def medir(prom, inicio, fin):
    out = {"ventana": {"inicio": inicio, "fin": fin}, "servicios": {}}
    for s in SERVICIOS:
        # Filtra por proyecto y servicio de Compose: evita contenedores homonimos de otras pilas.
        sel = ('container_label_com_docker_compose_project="trazabilidad-sandbox",'
               f'container_label_com_docker_compose_service="{s}"')
        cpu = consultar_rango(prom, f"sum(rate(container_cpu_usage_seconds_total{{{sel}}}[30s]))", inicio, fin)
        ram = consultar_rango(prom, f"sum(container_memory_working_set_bytes{{{sel}}})", inicio, fin)
        out["servicios"][s] = {"cpu_nucleos": resumen(cpu), "ram_mib": resumen(ram, 1 / 1048576)}
    p95 = consultar_rango(
        prom,
        'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{endpoint="/v1/eventos"}[10s])) by (le))',
        inicio, fin)
    out["backend_rust_p95_escritura_ms"] = resumen(p95, 1000)
    proc = consultar_rango(prom, 'max(process_resident_memory_bytes{job="api-rust"})', inicio, fin)
    out["backend_rust_rss_proceso_mib"] = resumen(proc, 1 / 1048576)
    hilos = consultar_rango(prom, 'max(process_threads{job="api-rust"})', inicio, fin)
    out["backend_rust_hilos_so"] = resumen(hilos)
    return out


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
    datos = medir(args.prom, args.inicio, args.fin)
    ruta = f"{args.salida}/recursos_{args.run_id}.json"
    with open(ruta, "w") as f:
        json.dump(datos, f, indent=2)
    print(f"Escrito {ruta}")
    for s, d in datos["servicios"].items():
        if d["cpu_nucleos"]:
            print(f"  {s:13} CPU media {d['cpu_nucleos']['media']:.3f} pico {d['cpu_nucleos']['pico']:.3f} nucleos | RAM pico {d['ram_mib']['pico']:.1f} MiB")


if __name__ == "__main__":
    main()
