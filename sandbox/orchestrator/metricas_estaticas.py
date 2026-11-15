#!/usr/bin/env python3
"""Metricas estaticas de producto y construccion (ISO/IEC 25010, mantenibilidad).

Incluye clippy con warnings como error, dart/flutter analyze, tamano del codigo por
componente y datos de construccion (binario Rust, dependencias e imagenes Docker).
Uso (desde sandbox/):  python3 orchestrator/metricas_estaticas.py [--medir-build]
Escribe results/metricas_estaticas.json. Solo biblioteca estandar."""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import time

RAIZ = pathlib.Path(__file__).resolve().parents[2]
COMPONENTES = {
    "backend-rust": (".rs", ["backend-rust/src", "backend-rust/tests"]),
    "backend-baseline": (".py", ["backend-baseline/app.py", "backend-baseline/gunicorn.conf.py", "backend-baseline/tests"]),
    "cliente-core": (".dart", ["cliente/trazabilidad_core/lib", "cliente/trazabilidad_core/test"]),
    "cliente-app": (".dart", ["cliente/trazabilidad_app/lib"]),
    "client-sim": (".dart", ["client-sim/lib", "client-sim/bin", "client-sim/test"]),
}


def loc(ext, rutas):
    """Lineas de codigo: no vacias y que no sean solo comentario de linea."""
    n = 0
    archivos = 0
    for r in rutas:
        p = RAIZ / r
        for f in ([p] if p.is_file() else sorted(p.rglob(f"*{ext}"))):
            archivos += 1
            for linea in f.read_text(encoding="utf-8").splitlines():
                t = linea.strip()
                if t and not t.startswith(("//", "#")):
                    n += 1
    return {"archivos": archivos, "lineas": n}


def clippy():
    cargo = shutil.which("cargo")
    if not cargo:
        return {"disponible": False}
    p = subprocess.run([cargo, "clippy", "--all-targets", "--message-format=json", "--", "-D", "warnings"],
                       cwd=RAIZ / "backend-rust", capture_output=True, text=True)
    avisos, errores = {}, 0
    for linea in p.stdout.splitlines():
        try:
            m = json.loads(linea)
        except ValueError:
            continue
        if m.get("reason") != "compiler-message":
            continue
        msg = m["message"]
        if msg["level"] == "error":
            errores += 1
        elif msg["level"] == "warning" and msg.get("code"):
            avisos[msg["code"]["code"]] = avisos.get(msg["code"]["code"], 0) + 1
    return {"disponible": True, "codigo_salida": p.returncode,
            "avisos_total": sum(avisos.values()), "errores": errores, "por_lint": avisos}


def _ejecutar(herramienta, subcomando, ruta):
    subprocess.run([herramienta, "pub", "get"], cwd=ruta, capture_output=True)
    p = subprocess.run([herramienta, subcomando], cwd=ruta, capture_output=True, text=True)
    return {"codigo_salida": p.returncode,
            "resumen": (p.stdout.strip().splitlines() or [""])[-1],
            "salida": (p.stdout + p.stderr).strip()[:2000]}


def dart_analyze():
    dart = shutil.which("dart")
    flutter = shutil.which("flutter")
    if not dart and not flutter:
        return {"disponible": False, "nota": "sin SDK de Dart/Flutter en esta maquina; se ejecuta en CI"}
    res = {"disponible": True, "dart": bool(dart), "flutter": bool(flutter)}
    for nombre, ruta in [("cliente-core", "cliente/trazabilidad_core"), ("client-sim", "client-sim")]:
        if dart:
            res[nombre] = _ejecutar(dart, "analyze", RAIZ / ruta)
        elif flutter:
            res[nombre] = _ejecutar(flutter, "analyze", RAIZ / ruta)
    if flutter:
        res["cliente-app"] = _ejecutar(flutter, "analyze", RAIZ / "cliente/trazabilidad_app")
    else:
        res["cliente-app"] = {"omitido": "flutter analyze requiere el SDK de Flutter; se ejecuta en CI"}
    return res


def construccion(medir=False):
    res = {"binario_rust": None, "dependencias_cargo": None, "build_rust": None, "imagenes_docker": {}}
    binario = RAIZ / "backend-rust" / "target" / "release" / "backend-rust"
    if binario.is_file():
        res["binario_rust"] = {"bytes": binario.stat().st_size,
                               "mib": round(binario.stat().st_size / 1048576, 2)}
    cargo = shutil.which("cargo")
    if cargo:
        meta = subprocess.run([cargo, "metadata", "--format-version", "1"], cwd=RAIZ / "backend-rust",
                              capture_output=True, text=True)
        if meta.returncode == 0:
            datos = json.loads(meta.stdout)
            resolve = datos.get("resolve", {})
            raiz = resolve.get("root")
            nodo = next((n for n in resolve.get("nodes", []) if n.get("id") == raiz), {})
            res["dependencias_cargo"] = {
                "paquetes": len(datos.get("packages", [])),
                "dependencias_directas": len(nodo.get("dependencies", [])),
            }
        if medir:
            t0 = time.monotonic()
            p = subprocess.run([cargo, "build", "--release"], cwd=RAIZ / "backend-rust",
                               capture_output=True, text=True)
            res["build_rust"] = {"segundos": round(time.monotonic() - t0, 2), "codigo_salida": p.returncode}
            if binario.is_file():
                res["binario_rust"] = {"bytes": binario.stat().st_size,
                                       "mib": round(binario.stat().st_size / 1048576, 2)}
    docker = shutil.which("docker")
    if docker:
        for imagen in ["trazabilidad-sandbox-api-rust", "trazabilidad-sandbox-api-baseline",
                       "trazabilidad-sandbox-client-sim"]:
            p = subprocess.run([docker, "image", "inspect", imagen, "--format", "{{.Size}}"],
                               capture_output=True, text=True)
            if p.returncode == 0 and p.stdout.strip().isdigit():
                res["imagenes_docker"][imagen] = {"bytes": int(p.stdout.strip()),
                                                  "mib": round(int(p.stdout.strip()) / 1048576, 2)}
    return res


def main(argv=None):
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--medir-build", action="store_true", help="mide cargo build --release (tarda varios minutos)")
    args = a.parse_args(argv)
    datos = {
        "tamano": {k: loc(ext, rutas) for k, (ext, rutas) in COMPONENTES.items()},
        "clippy": clippy(),
        "dart_analyze": dart_analyze(),
        "construccion": construccion(args.medir_build),
    }
    out = RAIZ / "sandbox" / "results"
    out.mkdir(exist_ok=True)
    (out / "metricas_estaticas.json").write_text(json.dumps(datos, indent=2, ensure_ascii=False))
    json.dump(datos, sys.stdout, indent=2, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
