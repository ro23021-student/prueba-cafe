//! Utilidades compartidas por las pruebas de integracion: CouchDB falso y API con auth.
#![allow(dead_code)]
use axum::{
    extract::State,
    http::StatusCode,
    routing::{post, put},
    Json, Router,
};
use backend_rust::{
    application::{auth::ServicioAuth, casos_uso::ServicioTrazabilidad},
    domain::sesion::{Rol, Usuario},
    infrastructure::{couchdb::RepoCouch, jwt::TokensJwt},
    interface::http::router,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

pub const SECRETO: &str = "secreto-de-integracion-0123456789";

pub type Docs = Arc<Mutex<Vec<Value>>>;

pub async fn falso_couch() -> (String, Docs) {
    let docs: Docs = Arc::new(Mutex::new(vec![]));
    let r = Router::new()
        .route(
            "/trazabilidad",
            put(|| async { (StatusCode::CREATED, "{}") }).post(
                |State(d): State<Docs>, Json(doc): Json<Value>| async move {
                    let mut g = d.lock().unwrap();
                    if g.iter().any(|x| x["_id"] == doc["_id"]) {
                        return (StatusCode::CONFLICT, Json(json!({"error":"conflict"})));
                    }
                    g.push(doc);
                    (StatusCode::CREATED, Json(json!({"ok": true})))
                },
            ),
        )
        .route(
            "/trazabilidad/_security",
            put(|Json(s): Json<Value>| async move {
                assert!(s["members"]["roles"].as_array().unwrap().len() >= 3);
                Json(json!({"ok": true}))
            }),
        )
        .route(
            "/trazabilidad/_design/auth",
            axum::routing::get(|| async { (StatusCode::NOT_FOUND, "{}") }).put(
                |Json(d): Json<Value>| async move {
                    assert!(d["validate_doc_update"]
                        .as_str()
                        .unwrap()
                        .contains("userCtx"));
                    (StatusCode::CREATED, Json(json!({"ok": true})))
                },
            ),
        )
        .route(
            "/trazabilidad/_index",
            post(|| async { Json(json!({"result":"created"})) }),
        )
        .route(
            "/trazabilidad/_find",
            post(|State(d): State<Docs>, Json(q): Json<Value>| async move {
                let id = q["selector"]["lote_id"].clone();
                let v: Vec<Value> = d
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|x| x["lote_id"] == id)
                    .cloned()
                    .collect();
                Json(json!({"docs": v}))
            }),
        )
        .with_state(docs.clone());
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", l.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(l, r).await.unwrap() });
    (url, docs)
}

pub fn usuarios() -> Vec<Usuario> {
    let u = |n: &str, r: Rol, c: Option<&str>| Usuario {
        nombre: n.into(),
        clave: format!("clave-{n}"),
        rol: r,
        cooperativa: c.map(Into::into),
    };
    vec![
        u("tec", Rol::Tecnico, None),
        u("aud", Rol::Auditor, None),
        u("prod", Rol::Productor, None),
        u("tec2", Rol::Tecnico, Some("OTRA")),
    ]
}

pub fn servicio_auth() -> ServicioAuth {
    ServicioAuth::new(usuarios(), Arc::new(TokensJwt::new(SECRETO, "sandbox", 60)))
}

pub async fn api_con(repo: RepoCouch) -> String {
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", l.local_addr().unwrap());
    let app = router(ServicioTrazabilidad::new(Arc::new(repo)), servicio_auth());
    tokio::spawn(async move { axum::serve(l, app).await.unwrap() });
    url
}

pub async fn api(couch: &str) -> String {
    let repo = RepoCouch::new(reqwest::Client::new(), couch, "trazabilidad", "a", "b");
    repo.asegurar_db().await.unwrap();
    repo.asegurar_politicas().await.unwrap();
    repo.asegurar_indices().await.unwrap();
    api_con(repo).await
}

/// Inicia sesion y devuelve el token.
pub async fn token(url: &str, user: &str) -> String {
    let r = reqwest::Client::new()
        .post(format!("{url}/auth/login"))
        .json(&json!({"user": user, "pass": format!("clave-{user}")}))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 200);
    r.json::<Value>().await.unwrap()["token"]
        .as_str()
        .unwrap()
        .to_string()
}

pub fn evento() -> Value {
    json!({"type":"evento_lote","lote_id":"L-1","cooperativa_id":"C1","etapa":"recoleccion","ts":1700000000,"owner":"u1","peso_kg":40})
}
