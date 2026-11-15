#!/usr/bin/env python3
"""Exporta docs/FASE5_ANALISIS.md a HTML, DOCX y PDF con LibreOffice.

Uso:
    /tmp/venv-analysis/bin/python sandbox/orchestrator/exportar_fase5.py [--entrada docs/FASE5_ANALISIS.md]

Requiere: python-markdown (venv de analisis) y `soffice` en PATH.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

try:
    import markdown
except ImportError:  # pragma: no cover
    sys.exit("Falta python-markdown en el venv: pip install markdown")

AQUI = pathlib.Path(__file__).resolve().parent
SANDBOX = AQUI.parent          # .../sandbox_fase3/sandbox
RAIZ = SANDBOX.parent          # .../sandbox_fase3
DEFECTO = RAIZ / "docs" / "FASE5_ANALISIS.md"

CSS = """<!DOCTYPE html><html><head><meta charset="utf-8"><title>Fase 5</title>
<style>
body{font-family:DejaVu Sans,Arial,sans-serif;font-size:10.5pt;line-height:1.45;margin:2cm}
h1{font-size:17pt}h2{font-size:13.5pt;border-bottom:1px solid #999}
h3{font-size:11.5pt;margin-top:14pt}
table{border-collapse:collapse;width:100%;font-size:8.5pt;margin:8px 0}
th,td{border:1px solid #666;padding:3px 5px;text-align:left}th{background:#eee}
code{font-family:DejaVu Sans Mono,monospace;font-size:9pt;background:#f4f4f4}
pre{background:#f4f4f4;padding:8px;white-space:pre-wrap}
</style></head><body>
"""


def convertir(ruta: pathlib.Path, filtro: str, outdir: pathlib.Path) -> pathlib.Path:
    """Ejecuta soffice para pasar de `ruta` al filtro indicado y devuelve la salida.

    Se usa el nombre corto del filtro (`docx`, `pdf`): el nombre completo
    (`docx:"MS Word 2007 XML"`) falla con impl_store 0x81a en LibreOffice 24.2.
    """
    destino = outdir / f"{ruta.stem}.{filtro.split(':')[0]}"
    if destino.exists():
        destino.unlink()
    cmd = ["soffice", "--headless"]
    if ruta.suffix == ".html":
        cmd += ["--infilter=HTML (StarWriter)"]
    cmd += ["--convert-to", filtro, "--outdir", str(outdir), str(ruta)]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if not destino.exists():
        sys.stderr.write(res.stdout + res.stderr)
        raise SystemExit(f"No se genero {destino.name}")
    return destino


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--entrada", default=str(DEFECTO))
    args = ap.parse_args()

    md_path = pathlib.Path(args.entrada).resolve()
    if not md_path.exists():
        raise SystemExit(f"No existe {md_path}")
    if "{DECISION_H1}" in md_path.read_text(encoding="utf-8"):
        raise SystemExit("La plantilla aun tiene marcadores sin resolver; ejecuta redactar_fase5.py")

    cuerpo = markdown.markdown(
        md_path.read_text(encoding="utf-8"),
        extensions=["tables", "fenced_code", "sane_lists"],
    )
    html_path = md_path.with_suffix(".html")
    html_path.write_text(CSS + cuerpo + "\n</body></html>", encoding="utf-8")

    docx = convertir(html_path, "docx", md_path.parent)
    pdf = convertir(docx, "pdf", md_path.parent)
    print(f"Escrito {html_path.name}, {docx.name} y {pdf.name} en {md_path.parent}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
