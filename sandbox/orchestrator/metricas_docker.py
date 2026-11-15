#!/usr/bin/env python3
"""Resume CPU/RAM de los contenedores del sandbox desde muestras de `docker stats`.

Los runners guardan una linea JSON por muestra en results/docker_stats_<run-id>.jsonl.
Uso: python3 orchestrator/metricas_docker.py --archivo results/docker_stats_RUN.jsonl --run-id RUN
Escribe results/metricas_docker_<run-id>.json. Solo biblioteca estandar."""
import argparse
import json
import pathlib
import statistics

SERVICIOS = ["api-rust", "api-baseline", "couchdb", "postgres", "client-sim", "prometheus", "cadvisor"]


def servicio(nombre):
    for s in SERVICIOS:
        if nombre.startswith(f"trazabilidad-sandbox-{s}-"):
            return s
    return None


def mib(texto):
    valor = texto.split("/")[0].strip().replace("MiB", "").replace("GiB", "").replace("KiB", "").strip()
    try:
        n = float(valor)
    except ValueError:
        return None
    if "GiB" in texto:
        n *= 1024
    elif "KiB" in texto:
        n /= 1024
    return n


def resumen(valores):
    if not valores:
        return None
    return {"media": round(statistics.fmean(valores), 4), "pico": round(max(valores), 4), "muestras": len(valores)}


def main(argv=None):
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--archivo", required=True)
    a.add_argument("--run-id", default="manual")
    a.add_argument("--salida", default="results")
    args = a.parse_args(argv)
    ruta = pathlib.Path(args.archivo)
    if not ruta.is_file():
        print(f"No existe {ruta}; se omite metricas_docker")
        return 0
    cpu, ram = {}, {}
    for linea in ruta.read_text().splitlines():
        try:
            m = json.loads(linea)
        except ValueError:
            continue
        s = servicio(m.get("Name", ""))
        if not s:
            continue
        try:
            cpu.setdefault(s, []).append(float(m["CPUPerc"].rstrip("%")))
        except (KeyError, ValueError):
            pass
        v = mib(m.get("MemUsage", ""))
        if v is not None:
            ram.setdefault(s, []).append(v)
    datos = {"servicios": {s: {"cpu_pct": resumen(cpu.get(s, [])), "ram_mib": resumen(ram.get(s, []))}
                           for s in SERVICIOS if cpu.get(s) or ram.get(s)}}
    destino = f"{args.salida}/metricas_docker_{args.run_id}.json"
    pathlib.Path(destino).write_text(json.dumps(datos, indent=2))
    print(f"Escrito {destino}")
    for s, d in datos["servicios"].items():
        c, r = d["cpu_pct"], d["ram_mib"]
        print(f"  {s:13} CPU% media {c['media'] if c else 0:.2f} pico {c['pico'] if c else 0:.2f} | "
              f"RAM pico {r['pico'] if r else 0:.1f} MiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
