#!/usr/bin/env python3
"""Genera el plan de corridas aleatorizado (diseno factorial, bloques por jornada).
Uso: make_plan.py --seed 20261101 --reps 15 --out plan.csv

Brazos: T (Rust + CouchDB) y C0 (monolito relacional centralizado). C1 no forma parte
de las Fases 3 y 4 de la Tarea, por eso no se incluye en el plan obligatorio.
"""
import argparse, csv, itertools, random
ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, required=True)
ap.add_argument("--reps", type=int, default=15)
ap.add_argument("--blocks", type=int, default=5, help="jornadas (bloques)")
ap.add_argument("--out", default="plan.csv")
ap.add_argument("--archs", default="T,C0", help="brazos separados por coma (por defecto T,C0)")
a = ap.parse_args()
archs = [x.strip() for x in a.archs.split(",") if x.strip()]
if not archs or any(x not in ("T", "C0") for x in archs):
    raise SystemExit("--archs solo admite T y/o C0")
losses, devs = [0, 5, 15, 30], [10, 50, 100]
cells = list(itertools.product(archs, losses, devs))
rng = random.Random(a.seed)
rows = []
for rep in range(1, a.reps + 1):
    for cell in cells:
        rows.append({"rep": rep, "arch": cell[0], "loss_pct": cell[1], "devices": cell[2],
                     "run_seed": rng.randrange(2**31)})
# bloque = jornada; dentro de cada bloque el orden se aleatoriza
rng.shuffle(rows)
per = -(-len(rows) // a.blocks)
for i, r in enumerate(rows):
    r["block"] = i // per + 1
    r["order"] = i + 1
with open(a.out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["order", "block", "rep", "arch", "loss_pct", "devices", "run_seed"])
    w.writeheader(); w.writerows(rows)
print(f"{len(rows)} corridas escritas en {a.out}")
