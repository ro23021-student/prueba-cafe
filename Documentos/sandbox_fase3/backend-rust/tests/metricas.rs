//! Las metricas se registran en un recorder global, por eso esta prueba vive en su propio binario.
mod common;
use backend_rust::infrastructure::telemetria::{instalar_en_memoria, RepoMedido};
use backend_rust::{
    application::casos_uso::ServicioTrazabilidad, infrastructure::couchdb::RepoCouch,
    interface::http::router,
};
use common::*;
use std::sync::Arc;

#[tokio::test]
async fn expone_latencia_por_endpoint_transacciones_y_rechazos() {
    let handle = instalar_en_memoria();
    let (couch, _) = falso_couch().await;
    let repo = RepoCouch::new(reqwest::Client::new(), &couch, "trazabilidad", "a", "b");
    repo.asegurar_db().await.unwrap();
    repo.asegurar_politicas().await.unwrap();
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", l.local_addr().unwrap());
    let app = router(
        ServicioTrazabilidad::new(Arc::new(RepoMedido::new(Arc::new(repo)))),
        servicio_auth(),
    );
    tokio::spawn(async move { axum::serve(l, app).await.unwrap() });

    let t = token(&url, "tec").await;
    let c = reqwest::Client::new();
    c.post(format!("{url}/v1/eventos"))
        .bearer_auth(&t)
        .json(&evento())
        .send()
        .await
        .unwrap();
    c.get(format!("{url}/v1/lotes/L-1"))
        .bearer_auth(&t)
        .send()
        .await
        .unwrap();
    c.get(format!("{url}/v1/lotes/L-2"))
        .bearer_auth(&t)
        .send()
        .await
        .unwrap();
    c.get(format!("{url}/v1/lotes/L-1")).send().await.unwrap(); // sin token

    let texto = handle.render();
    assert!(
        texto.contains(
            "http_request_duration_seconds_bucket{endpoint=\"/v1/eventos\",method=\"POST\""
        ),
        "{texto}"
    );
    // la ruta usa plantilla: dos lotes distintos comparten una sola serie
    assert!(texto.contains("endpoint=\"/v1/lotes/:id\""));
    assert!(!texto.contains("L-2"));
    assert!(texto.contains("db_tx_duration_seconds_bucket{op=\"guardar\",resultado=\"ok\""));
    assert!(texto.contains("auth_rechazos_total{motivo=\"sin_token\"} 1"));
    assert!(texto.contains(
        "http_requests_total{endpoint=\"/v1/eventos\",method=\"POST\",status=\"201\"} 1"
    ));
}
