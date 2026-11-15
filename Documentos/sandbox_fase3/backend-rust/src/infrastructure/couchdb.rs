//! Adaptador de CouchDB: cliente HTTP asincrono (Reqwest) contra la API REST y Mango Queries.
use crate::application::puertos::{ErrorRepo, EventoRepositorio, ResultadoGuardado};
use crate::domain::evento::EventoLote;
use async_trait::async_trait;
use serde_json::{json, Value};

const VALIDATE_JS: &str = include_str!("politicas/validate_doc_update.js");
const SECURITY_JSON: &str = include_str!("politicas/security.json");

#[derive(Clone)]
pub struct RepoCouch {
    http: reqwest::Client,
    url: String,
    db: String,
    user: String,
    pass: String,
}

impl RepoCouch {
    pub fn new(http: reqwest::Client, url: &str, db: &str, user: &str, pass: &str) -> Self {
        Self {
            http,
            url: url.trim_end_matches('/').into(),
            db: db.into(),
            user: user.into(),
            pass: pass.into(),
        }
    }

    fn req(&self, m: reqwest::Method, ruta: &str) -> reqwest::RequestBuilder {
        self.http
            .request(m, format!("{}/{}{}", self.url, self.db, ruta))
            .basic_auth(&self.user, Some(&self.pass))
    }

    /// Crea la base si no existe (412 = ya existe).
    pub async fn asegurar_db(&self) -> Result<(), ErrorRepo> {
        let r = self
            .req(reqwest::Method::PUT, "")
            .send()
            .await
            .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
        match r.status().as_u16() {
            201 | 202 | 412 => Ok(()),
            c => Err(ErrorRepo::Inesperado(format!("crear base: HTTP {c}"))),
        }
    }

    /// Instala el RBAC: `_security` (quien entra a la base) y `_design/auth` con
    /// validate_doc_update (quien escribe que, por documento). Idempotente.
    pub async fn asegurar_politicas(&self) -> Result<(), ErrorRepo> {
        let sec: Value = serde_json::from_str(SECURITY_JSON)
            .map_err(|e| ErrorRepo::Inesperado(e.to_string()))?;
        let r = self
            .req(reqwest::Method::PUT, "/_security")
            .json(&sec)
            .send()
            .await
            .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
        if !r.status().is_success() {
            return Err(ErrorRepo::Inesperado(format!(
                "_security: HTTP {}",
                r.status()
            )));
        }
        let mut doc = json!({"_id": "_design/auth", "validate_doc_update": VALIDATE_JS});
        let actual = self
            .req(reqwest::Method::GET, "/_design/auth")
            .send()
            .await
            .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
        if actual.status().is_success() {
            let v: Value = actual
                .json()
                .await
                .map_err(|e| ErrorRepo::Inesperado(e.to_string()))?;
            if v["validate_doc_update"] == VALIDATE_JS {
                return Ok(());
            }
            doc["_rev"] = v["_rev"].clone();
        }
        let r = self
            .req(reqwest::Method::PUT, "/_design/auth")
            .json(&doc)
            .send()
            .await
            .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
        if !r.status().is_success() {
            return Err(ErrorRepo::Inesperado(format!(
                "_design/auth: HTTP {}",
                r.status()
            )));
        }
        Ok(())
    }

    /// Indices Mango (idempotente: CouchDB responde "exists" si ya estan).
    pub async fn asegurar_indices(&self) -> Result<(), ErrorRepo> {
        let indices = [
            json!({"index": {"fields": ["type", "lote_id", "ts"]}, "name": "idx_lote_ts", "ddoc": "idx_lote_ts", "type": "json"}),
            json!({"index": {"fields": ["type", "cooperativa_id", "ts"]}, "name": "idx_coop_ts", "ddoc": "idx_coop_ts", "type": "json"}),
        ];
        for idx in indices {
            let r = self
                .req(reqwest::Method::POST, "/_index")
                .json(&idx)
                .send()
                .await
                .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
            if !r.status().is_success() {
                return Err(ErrorRepo::Inesperado(format!(
                    "crear indice: HTTP {}",
                    r.status()
                )));
            }
        }
        Ok(())
    }
}

#[async_trait]
impl EventoRepositorio for RepoCouch {
    async fn guardar(&self, e: &EventoLote) -> Result<ResultadoGuardado, ErrorRepo> {
        let mut doc = e.a_json();
        doc["_id"] = Value::String(e.id());
        let r = self
            .req(reqwest::Method::POST, "")
            .json(&doc)
            .send()
            .await
            .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
        match r.status().as_u16() {
            201 | 202 => Ok(ResultadoGuardado::Creado),
            409 => Ok(ResultadoGuardado::Duplicado),
            c => Err(ErrorRepo::Inesperado(format!("guardar: HTTP {c}"))),
        }
    }

    async fn por_lote(&self, lote_id: &str) -> Result<Vec<EventoLote>, ErrorRepo> {
        let q = json!({
            "selector": {"type": EventoLote::TIPO, "lote_id": lote_id, "ts": {"$gte": 0}},
            "use_index": "idx_lote_ts",
            "sort": [{"type": "asc"}, {"lote_id": "asc"}, {"ts": "asc"}],
            "limit": 200
        });
        let r = self
            .req(reqwest::Method::POST, "/_find")
            .json(&q)
            .send()
            .await
            .map_err(|e| ErrorRepo::Conexion(causa(&e)))?;
        if !r.status().is_success() {
            return Err(ErrorRepo::Inesperado(format!("_find: HTTP {}", r.status())));
        }
        let cuerpo: Value = r
            .json()
            .await
            .map_err(|e| ErrorRepo::Inesperado(e.to_string()))?;
        Ok(cuerpo["docs"]
            .as_array()
            .map(|d| {
                d.iter()
                    .filter_map(|x| EventoLote::desde_json(x).ok())
                    .collect()
            })
            .unwrap_or_default())
    }
}

/// Cadena completa de causas de un error de Reqwest ("error sending request <- connection reset ...").
fn causa(e: &reqwest::Error) -> String {
    use std::error::Error;
    let mut s = e.to_string();
    let mut origen = e.source();
    while let Some(x) = origen {
        s.push_str(&format!(" <- {x}"));
        origen = x.source();
    }
    s
}
