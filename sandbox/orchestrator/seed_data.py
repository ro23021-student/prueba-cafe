#!/usr/bin/env python3
"""Genera datos SINTETICOS de trazabilidad (formato _bulk_docs de CouchDB).
Uso: seed_data.py --lotes 10000 --seed 42 > seed.json
Sin datos reales: productores seudonimizados, coordenadas inventadas dentro de un
rectangulo aproximado de la zona Apaneca-Ilamatepec (no son fincas reales)."""
import argparse, json, random
ETAPAS = ["recoleccion", "beneficio", "secado", "almacen", "despacho"]
ap = argparse.ArgumentParser()
ap.add_argument("--lotes", type=int, default=10000)
ap.add_argument("--seed", type=int, default=42)
a = ap.parse_args()
rng = random.Random(a.seed)
docs = []
t0 = 1_760_000_000  # inicio de cosecha sintetica (epoch)
for i in range(1, a.lotes + 1):
    coop = f"COOP-{rng.randint(1, 12):02d}"
    owner = f"prod-{rng.randint(1, 300):04d}"
    lote = f"L-{i:06d}"
    n = rng.choices([1, 2, 3, 4, 5], weights=[5, 10, 15, 20, 50])[0]
    ts = t0 + rng.randint(0, 90 * 86400)
    peso = round(rng.uniform(30, 120), 1)
    for k in range(n):
        d = {"_id": f"{lote}:{ts}", "type": "evento_lote", "lote_id": lote, "cooperativa_id": coop,
             "etapa": ETAPAS[k], "ts": ts, "owner": owner, "peso_kg": peso}
        if k == 0:
            d["lat"] = round(rng.uniform(13.80, 13.93), 3)
            d["lon"] = round(rng.uniform(-89.85, -89.70), 3)
        docs.append(d)
        ts += rng.randint(3600, 3 * 86400)
        peso = round(peso * rng.uniform(0.55, 0.9), 1)
print(json.dumps({"docs": docs}))
