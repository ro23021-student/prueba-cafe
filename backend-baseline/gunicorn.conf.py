# Monolito sincrono: 2 procesos (los 2 nucleos del cpuset 0-1) x THREADS hilos bloqueantes cada uno.
# Es la configuracion tipica de produccion para Flask; se documenta en el informe como decision de diseno
# (riesgo "implementaciones desiguales", Fase 3 Tabla de amenazas): si fuera mas pobre de lo razonable,
# C0 seria un hombre de paja.
import os

import app as aplicacion

bind = "0.0.0.0:8080"
workers = int(os.environ.get("WORKERS", "2"))
threads = int(os.environ.get("THREADS", "16"))
worker_class = "gthread"
timeout = 30
accesslog = None
wsgi_app = "app:crear_app()"


def on_starting(server):
    aplicacion.preparar_base(os.environ["DATABASE_URL"])
