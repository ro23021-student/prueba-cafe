"""C0 - monolito sincrono tradicional (Flask + gunicorn + PostgreSQL).

Mismo contrato REST que la API de Rust (Fase 3, Tabla 3.8):
  GET  /health            -> "ok"
  POST /auth/login        -> {token, expires_in, rol, cooperativa}
  POST /v1/eventos        -> 201 {ok} | 200 {duplicado} | 401 | 403 | 422 | 502
  GET  /v1/lotes/<id>     -> {lote_id, eventos: [...]}
Mismas reglas de validacion, mismo JWT (HS256, exp+iss), mismo RBAC y mismos usuarios (AUTH_USERS).
Solo cambia la arquitectura: E/S bloqueante con hilos, filas relacionales y sin motor de replicacion.
"""
import hmac
import json
import os
import time

import jwt
import psycopg2
import psycopg2.pool
from flask import Flask, g, jsonify, request

ETAPAS = {"recoleccion", "beneficio", "secado", "almacen", "despacho"}
CONOCIDOS = ("type", "lote_id", "cooperativa_id", "etapa", "ts", "owner")
ROLES = {"tecnico", "productor", "auditor"}
TIPO = "evento_lote"

SCHEMA = """
CREATE TABLE IF NOT EXISTS eventos (
    id             TEXT PRIMARY KEY,
    lote_id        TEXT   NOT NULL,
    cooperativa_id TEXT   NOT NULL,
    etapa          TEXT   NOT NULL,
    ts             BIGINT NOT NULL,
    owner          TEXT   NOT NULL,
    extra          JSONB  NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_eventos_lote_ts ON eventos (lote_id, ts);
CREATE INDEX IF NOT EXISTS idx_eventos_coop_ts ON eventos (cooperativa_id, ts);
"""


class ErrorValidacion(Exception):
    pass


class Prohibido(Exception):
    pass


# ---------------------------------------------------------------- configuracion
def parsear_usuarios(texto):
    usuarios = {}
    for item in (s.strip() for s in texto.split(",")):
        if not item:
            continue
        p = item.split(":")
        if not 3 <= len(p) <= 4 or not p[0] or not p[1]:
            raise ValueError("AUTH_USERS: cada entrada es usuario:clave:rol[:cooperativa]")
        if p[2] not in ROLES:
            raise ValueError(f"AUTH_USERS: rol desconocido: {p[2]}")
        if p[0] in usuarios:
            raise ValueError(f"AUTH_USERS: usuario repetido: {p[0]}")
        usuarios[p[0]] = {"clave": p[1], "rol": p[2], "coop": (p[3] if len(p) == 4 and p[3] else None)}
    if not usuarios:
        raise ValueError("AUTH_USERS no define ningun usuario")
    return usuarios


# ---------------------------------------------------------------- dominio
def validar_evento(obj):
    """Misma validacion que EventoLote::desde_json de Rust. Devuelve (fila, extra)."""
    if not isinstance(obj, dict):
        raise ErrorValidacion("El documento debe ser un objeto JSON")
    for campo in CONOCIDOS:
        if campo not in obj:
            raise ErrorValidacion(f"Campo obligatorio: {campo}")
    if obj["type"] != TIPO:
        raise ErrorValidacion(f'type debe ser "{TIPO}"')

    def texto(k):
        v = obj[k]
        if not isinstance(v, str) or not v.strip():
            raise ErrorValidacion(f"{k} debe ser texto no vacio")
        return v

    ts = obj["ts"]
    if isinstance(ts, bool) or not isinstance(ts, int):
        raise ErrorValidacion("ts debe ser un entero (epoch)")
    if obj["etapa"] not in ETAPAS:
        raise ErrorValidacion("Etapa invalida")
    extra = {k: v for k, v in obj.items() if k not in CONOCIDOS and not k.startswith("_")}
    lote = texto("lote_id")
    return {
        "id": f"{lote}:{ts}",
        "lote_id": lote,
        "cooperativa_id": texto("cooperativa_id"),
        "etapa": obj["etapa"],
        "ts": ts,
        "owner": texto("owner"),
    }, extra


def autorizar_escritura(sesion, fila):
    if sesion["rol"] == "auditor":
        raise Prohibido("El rol auditor es de solo lectura.")
    if sesion["rol"] == "productor" and fila["owner"] != sesion["usuario"]:
        raise Prohibido("Un productor solo escribe documentos propios.")
    if sesion["coop"] is not None and sesion["coop"] != fila["cooperativa_id"]:
        raise Prohibido("El evento pertenece a otra cooperativa.")


def puede_leer(sesion, fila):
    if sesion["rol"] == "productor":
        return fila["owner"] == sesion["usuario"]
    return sesion["coop"] is None or sesion["coop"] == fila["cooperativa_id"]


def a_json(fila, extra):
    d = dict(extra)
    d.update(type=TIPO, lote_id=fila["lote_id"], cooperativa_id=fila["cooperativa_id"],
             etapa=fila["etapa"], ts=fila["ts"], owner=fila["owner"])
    return d


# ---------------------------------------------------------------- aplicacion
def crear_app(config=None):
    cfg = config or {
        "DATABASE_URL": os.environ["DATABASE_URL"],
        "JWT_SECRET": os.environ["JWT_SECRET"],
        "JWT_ISSUER": os.environ.get("JWT_ISSUER", "trazabilidad-sandbox"),
        "JWT_TTL_S": int(os.environ.get("JWT_TTL_S", "3600")),
        "AUTH_USERS": os.environ["AUTH_USERS"],
        "DB_POOL": int(os.environ.get("DB_POOL", os.environ.get("THREADS", "16"))),
    }
    if len(cfg["JWT_SECRET"]) < 16:
        raise ValueError("JWT_SECRET debe tener al menos 16 caracteres")
    usuarios = parsear_usuarios(cfg["AUTH_USERS"])
    app = Flask(__name__)
    pool = {"p": None}

    def conexion():
        if pool["p"] is None:  # un pool por proceso worker (se crea tras el fork de gunicorn)
            pool["p"] = psycopg2.pool.ThreadedConnectionPool(1, cfg["DB_POOL"], cfg["DATABASE_URL"])
        return pool["p"]

    def respuesta_error(codigo, msg):
        r = jsonify({"error": msg})
        r.status_code = codigo
        if codigo == 401:
            r.headers["WWW-Authenticate"] = "Bearer"
        return r

    @app.errorhandler(ErrorValidacion)
    def _422(e):
        return respuesta_error(422, str(e))

    @app.errorhandler(Prohibido)
    def _403(e):
        return respuesta_error(403, str(e))

    @app.errorhandler(psycopg2.Error)
    def _502(e):
        return respuesta_error(502, f"sin conexion con la base de datos: {type(e).__name__}")

    @app.errorhandler(404)
    def _404(_):
        return respuesta_error(404, "no encontrado")

    @app.get("/health")
    def health():
        return "ok"

    @app.post("/auth/login")
    def login():
        c = request.get_json(silent=True)
        if not isinstance(c, dict) or not isinstance(c.get("user"), str) or not isinstance(c.get("pass"), str):
            return respuesta_error(422, "se esperan los campos user y pass")
        hallado = None
        for nombre, u in usuarios.items():  # recorre todos y compara en tiempo constante
            if hmac.compare_digest(nombre.encode(), c["user"].encode()) & hmac.compare_digest(u["clave"].encode(), c["pass"].encode()):
                hallado = (nombre, u)
        if hallado is None:
            return respuesta_error(401, "credenciales invalidas")
        nombre, u = hallado
        claims = {"sub": nombre, "rol": u["rol"], "iss": cfg["JWT_ISSUER"], "exp": int(time.time()) + cfg["JWT_TTL_S"]}
        if u["coop"]:
            claims["coop"] = u["coop"]
        token = jwt.encode(claims, cfg["JWT_SECRET"], algorithm="HS256")
        return jsonify(token=token, expires_in=cfg["JWT_TTL_S"], rol=u["rol"], cooperativa=u["coop"])

    @app.before_request
    def exigir_sesion():
        if not request.path.startswith("/v1/"):
            return None
        h = request.headers.get("Authorization", "")
        if not h.startswith("Bearer "):
            return respuesta_error(401, "falta el encabezado Authorization: Bearer <token>")
        try:
            c = jwt.decode(h[7:], cfg["JWT_SECRET"], algorithms=["HS256"], issuer=cfg["JWT_ISSUER"],
                           options={"require": ["exp", "iss", "sub"]}, leeway=0)
            if c["rol"] not in ROLES:
                raise jwt.InvalidTokenError("rol")
        except (jwt.InvalidTokenError, KeyError):
            return respuesta_error(401, "token invalido o vencido")
        g.sesion = {"usuario": c["sub"], "rol": c["rol"], "coop": c.get("coop")}
        return None

    @app.post("/v1/eventos")
    def crear_evento():
        entrada = request.get_json(silent=True)
        fila, extra = validar_evento(entrada)
        autorizar_escritura(g.sesion, fila)
        p = conexion()
        con = p.getconn()
        try:
            con.autocommit = True
            with con.cursor() as cur:
                cur.execute(
                    "INSERT INTO eventos (id, lote_id, cooperativa_id, etapa, ts, owner, extra) "
                    "VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (id) DO NOTHING",
                    (fila["id"], fila["lote_id"], fila["cooperativa_id"], fila["etapa"], fila["ts"], fila["owner"], json.dumps(extra)),
                )
                nuevo = cur.rowcount == 1
        finally:
            p.putconn(con)
        return (jsonify(ok=True), 201) if nuevo else (jsonify(duplicado=True), 200)

    @app.get("/v1/lotes/<path:lote_id>")
    def leer_lote(lote_id):
        if not lote_id.strip():
            raise ErrorValidacion("lote_id vacio")
        p = conexion()
        con = p.getconn()
        try:
            con.autocommit = True
            with con.cursor() as cur:
                cur.execute(
                    "SELECT lote_id, cooperativa_id, etapa, ts, owner, extra FROM eventos "
                    "WHERE lote_id = %s ORDER BY ts ASC LIMIT 200", (lote_id,))
                filas = cur.fetchall()
        finally:
            p.putconn(con)
        eventos = []
        for lote, coop, etapa, ts, owner, extra in filas:
            f = {"lote_id": lote, "cooperativa_id": coop, "etapa": etapa, "ts": ts, "owner": owner}
            if puede_leer(g.sesion, f):
                eventos.append(a_json(f, extra))
        return jsonify(lote_id=lote_id, eventos=eventos)

    return app


def preparar_base(dsn, intentos=30):
    """Crea el esquema (una sola vez, desde el proceso maestro de gunicorn)."""
    for i in range(intentos):
        try:
            con = psycopg2.connect(dsn)
            try:
                con.autocommit = True
                with con.cursor() as cur:
                    cur.execute(SCHEMA)
            finally:
                con.close()
            return
        except psycopg2.OperationalError:
            if i == intentos - 1:
                raise
            time.sleep(2)
