//! Integracion extremo a extremo con un CouchDB falso (axum): HTTP -> auth -> casos de uso -> adaptador.
mod common;
use backend_rust::infrastructure::couchdb::RepoCouch;
use common::*;
use serde_json::{json, Value};

#[tokio::test]
async fn crea_reintento_y_lectura() {
    let (couch, docs) = falso_couch().await;
    let url = api(&couch).await;
    let t = token(&url, "tec").await;
    let c = reqwest::Client::new();
    let post = |d: Value| {
        c.post(format!("{url}/v1/eventos"))
            .bearer_auth(&t)
            .json(&d)
            .send()
    };
    assert_eq!(post(evento()).await.unwrap().status(), 201);
    assert_eq!(post(evento()).await.unwrap().status(), 200); // idempotente
    assert_eq!(docs.lock().unwrap().len(), 1);
    assert_eq!(docs.lock().unwrap()[0]["_id"], "L-1:1700000000");
    let r: Value = c
        .get(format!("{url}/v1/lotes/L-1"))
        .bearer_auth(&t)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(r["eventos"].as_array().unwrap().len(), 1);
    assert_eq!(r["eventos"][0]["peso_kg"], 40);
}

#[tokio::test]
async fn rechaza_invalidos_sin_tocar_la_bd() {
    let (couch, docs) = falso_couch().await;
    let url = api(&couch).await;
    let t = token(&url, "tec").await;
    let c = reqwest::Client::new();
    let mut malo = evento();
    malo["etapa"] = json!("inventada");
    assert_eq!(
        c.post(format!("{url}/v1/eventos"))
            .bearer_auth(&t)
            .json(&malo)
            .send()
            .await
            .unwrap()
            .status(),
        422
    );
    assert_eq!(
        c.post(format!("{url}/v1/eventos"))
            .bearer_auth(&t)
            .json(&json!({"lote_id":"X"}))
            .send()
            .await
            .unwrap()
            .status(),
        422
    );
    assert!(docs.lock().unwrap().is_empty());
    assert_eq!(
        c.get(format!("{url}/health"))
            .send()
            .await
            .unwrap()
            .text()
            .await
            .unwrap(),
        "ok"
    );
}

#[tokio::test]
async fn bd_caida_devuelve_502() {
    let repo_caido = RepoCouch::new(
        reqwest::Client::new(),
        "http://127.0.0.1:1",
        "trazabilidad",
        "a",
        "b",
    );
    let u2 = api_con(repo_caido).await;
    let t = token(&u2, "tec").await;
    let r = reqwest::Client::new()
        .post(format!("{u2}/v1/eventos"))
        .bearer_auth(&t)
        .json(&evento())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 502);
}

#[tokio::test]
async fn sin_token_o_token_malo_es_401_y_nada_se_guarda() {
    let (couch, docs) = falso_couch().await;
    let url = api(&couch).await;
    let c = reqwest::Client::new();
    let r = c
        .post(format!("{url}/v1/eventos"))
        .json(&evento())
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 401);
    assert_eq!(r.headers()["www-authenticate"], "Bearer");
    assert_eq!(
        c.post(format!("{url}/v1/eventos"))
            .bearer_auth("basura.no.jwt")
            .json(&evento())
            .send()
            .await
            .unwrap()
            .status(),
        401
    );
    assert_eq!(
        c.get(format!("{url}/v1/lotes/L-1"))
            .send()
            .await
            .unwrap()
            .status(),
        401
    );
    assert!(docs.lock().unwrap().is_empty());
}

#[tokio::test]
async fn login_valida_credenciales() {
    let (couch, _) = falso_couch().await;
    let url = api(&couch).await;
    let c = reqwest::Client::new();
    let mal = c
        .post(format!("{url}/auth/login"))
        .json(&json!({"user":"tec","pass":"incorrecta"}))
        .send()
        .await
        .unwrap();
    assert_eq!(mal.status(), 401);
    let inexistente = c
        .post(format!("{url}/auth/login"))
        .json(&json!({"user":"nadie","pass":"x"}))
        .send()
        .await
        .unwrap();
    assert_eq!(inexistente.status(), 401);
    let ok: Value = c
        .post(format!("{url}/auth/login"))
        .json(&json!({"user":"aud","pass":"clave-aud"}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(ok["rol"], "auditor");
    assert_eq!(ok["expires_in"], 60);
}

#[tokio::test]
async fn rbac_auditor_productor_y_cooperativa() {
    let (couch, docs) = falso_couch().await;
    let url = api(&couch).await;
    let c = reqwest::Client::new();
    let enviar = |tok: String, d: Value| {
        let (c, url) = (c.clone(), url.clone());
        async move {
            c.post(format!("{url}/v1/eventos"))
                .bearer_auth(tok)
                .json(&d)
                .send()
                .await
                .unwrap()
                .status()
                .as_u16()
        }
    };
    // auditor: solo lectura
    assert_eq!(enviar(token(&url, "aud").await, evento()).await, 403);
    // productor: owner distinto de su usuario => 403; propio => 201
    assert_eq!(enviar(token(&url, "prod").await, evento()).await, 403);
    let mut propio = evento();
    propio["owner"] = json!("prod");
    assert_eq!(enviar(token(&url, "prod").await, propio).await, 201);
    // tecnico limitado a otra cooperativa no puede escribir en C1
    assert_eq!(enviar(token(&url, "tec2").await, evento()).await, 403);
    assert_eq!(docs.lock().unwrap().len(), 1);
    // lectura: el auditor ve el lote; el productor "prod" ve el suyo; otro tecnico de OTRA coop no lo ve
    let leer = |tok: String| {
        let (c, url) = (c.clone(), url.clone());
        async move {
            c.get(format!("{url}/v1/lotes/L-1"))
                .bearer_auth(tok)
                .send()
                .await
                .unwrap()
                .json::<Value>()
                .await
                .unwrap()["eventos"]
                .as_array()
                .unwrap()
                .len()
        }
    };
    assert_eq!(leer(token(&url, "aud").await).await, 1);
    assert_eq!(leer(token(&url, "prod").await).await, 1);
    assert_eq!(leer(token(&url, "tec2").await).await, 0);
}
