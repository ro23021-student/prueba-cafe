"""Pruebas del monolito C0. Las de integracion usan un PostgreSQL real (TEST_DATABASE_URL) y se omiten sin el."""
import os
import sys
import time

import jwt
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import app as m  # noqa: E402

DSN = os.environ.get("TEST_DATABASE_URL")
SECRETO = "secreto-de-integracion-0123456789"
USUARIOS = "tec:clave-tec:tecnico,aud:clave-aud:auditor,prod:clave-prod:productor,tec2:clave-tec2:tecnico:OTRA"


def evento(**kw):
    d = {"type": "evento_lote", "lote_id": "L-1", "cooperativa_id": "C1", "etapa": "recoleccion", "ts": 1700000000, "owner": "u1", "peso_kg": 40}
    d.update(kw)
    return d


# ------------------------------------------------------------ unitarias (sin BD)
def test_validar_acepta_y_conserva_extra():
    fila, extra = m.validar_evento(evento(_rev="1-x"))
    assert fila["id"] == "L-1:1700000000" and extra == {"peso_kg": 40}


@pytest.mark.parametrize("campo,valor", [("etapa", "x"), ("type", "otro"), ("ts", "hoy"), ("ts", 1.5), ("ts", True), ("owner", "  ")])
def test_validar_rechaza(campo, valor):
    with pytest.raises(m.ErrorValidacion):
        m.validar_evento(evento(**{campo: valor}))


def test_validar_rechaza_faltantes_y_no_objeto():
    d = evento()
    del d["lote_id"]
    for malo in (d, [1], None):
        with pytest.raises(m.ErrorValidacion):
            m.validar_evento(malo)


def test_parsear_usuarios():
    u = m.parsear_usuarios(USUARIOS)
    assert u["tec2"]["coop"] == "OTRA" and u["tec"]["coop"] is None
    for malo in ["", "solo", "a:b:root", ":b:tecnico", "a:b:tecnico,a:c:auditor"]:
        with pytest.raises(ValueError):
            m.parsear_usuarios(malo)


# ------------------------------------------------------------ integracion (con BD)
@pytest.fixture()
def cliente():
    if not DSN:
        pytest.skip("TEST_DATABASE_URL no definida")
    m.preparar_base(DSN, intentos=1)
    import psycopg2
    con = psycopg2.connect(DSN)
    con.autocommit = True
    con.cursor().execute("TRUNCATE eventos")
    con.close()
    app = m.crear_app({"DATABASE_URL": DSN, "JWT_SECRET": SECRETO, "JWT_ISSUER": "sandbox", "JWT_TTL_S": 60, "AUTH_USERS": USUARIOS, "DB_POOL": 4})
    return app.test_client()


def token(c, user):
    r = c.post("/auth/login", json={"user": user, "pass": f"clave-{user}"})
    assert r.status_code == 200
    return {"Authorization": "Bearer " + r.get_json()["token"]}


def test_crea_reintento_y_lectura(cliente):
    h = token(cliente, "tec")
    assert cliente.post("/v1/eventos", json=evento(), headers=h).status_code == 201
    assert cliente.post("/v1/eventos", json=evento(), headers=h).status_code == 200  # idempotente
    r = cliente.get("/v1/lotes/L-1", headers=h).get_json()
    assert len(r["eventos"]) == 1 and r["eventos"][0]["peso_kg"] == 40 and r["eventos"][0]["etapa"] == "recoleccion"


def test_orden_por_ts_y_health(cliente):
    h = token(cliente, "tec")
    for ts in (30, 10, 20):
        cliente.post("/v1/eventos", json=evento(ts=ts), headers=h)
    assert [e["ts"] for e in cliente.get("/v1/lotes/L-1", headers=h).get_json()["eventos"]] == [10, 20, 30]
    assert cliente.get("/health").data == b"ok"


def test_invalidos_422(cliente):
    h = token(cliente, "tec")
    assert cliente.post("/v1/eventos", json=evento(etapa="inventada"), headers=h).status_code == 422
    assert cliente.post("/v1/eventos", json={"lote_id": "X"}, headers=h).status_code == 422
    assert cliente.get("/v1/lotes/L-1", headers=h).get_json()["eventos"] == []


def test_sin_token_o_malo_401(cliente):
    r = cliente.post("/v1/eventos", json=evento())
    assert r.status_code == 401 and r.headers["WWW-Authenticate"] == "Bearer"
    assert cliente.post("/v1/eventos", json=evento(), headers={"Authorization": "Bearer basura.no.jwt"}).status_code == 401
    assert cliente.get("/v1/lotes/L-1").status_code == 401
    ajeno = jwt.encode({"sub": "tec", "rol": "tecnico", "iss": "sandbox", "exp": int(time.time()) + 60}, "otro-secreto-distinto-123", algorithm="HS256")
    assert cliente.get("/v1/lotes/L-1", headers={"Authorization": "Bearer " + ajeno}).status_code == 401
    vencido = jwt.encode({"sub": "tec", "rol": "tecnico", "iss": "sandbox", "exp": int(time.time()) - 5}, SECRETO, algorithm="HS256")
    assert cliente.get("/v1/lotes/L-1", headers={"Authorization": "Bearer " + vencido}).status_code == 401
    otro_emisor = jwt.encode({"sub": "tec", "rol": "tecnico", "iss": "otro", "exp": int(time.time()) + 60}, SECRETO, algorithm="HS256")
    assert cliente.get("/v1/lotes/L-1", headers={"Authorization": "Bearer " + otro_emisor}).status_code == 401


def test_login(cliente):
    assert cliente.post("/auth/login", json={"user": "tec", "pass": "mala"}).status_code == 401
    assert cliente.post("/auth/login", json={"user": "nadie", "pass": "x"}).status_code == 401
    assert cliente.post("/auth/login", json={"user": "tec"}).status_code == 422
    ok = cliente.post("/auth/login", json={"user": "aud", "pass": "clave-aud"}).get_json()
    assert ok["rol"] == "auditor" and ok["expires_in"] == 60


def test_rbac(cliente):
    assert cliente.post("/v1/eventos", json=evento(), headers=token(cliente, "aud")).status_code == 403
    assert cliente.post("/v1/eventos", json=evento(), headers=token(cliente, "prod")).status_code == 403
    assert cliente.post("/v1/eventos", json=evento(owner="prod"), headers=token(cliente, "prod")).status_code == 201
    assert cliente.post("/v1/eventos", json=evento(ts=5), headers=token(cliente, "tec2")).status_code == 403
    n = lambda u: len(cliente.get("/v1/lotes/L-1", headers=token(cliente, u)).get_json()["eventos"])
    assert (n("aud"), n("prod"), n("tec2")) == (1, 1, 0)


def test_bd_caida_502():
    app = m.crear_app({"DATABASE_URL": "postgresql://x@127.0.0.1:1/x", "JWT_SECRET": SECRETO, "JWT_ISSUER": "sandbox", "JWT_TTL_S": 60, "AUTH_USERS": USUARIOS, "DB_POOL": 2})
    c = app.test_client()
    assert c.post("/v1/eventos", json=evento(), headers=token(c, "tec")).status_code == 502
