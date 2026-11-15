//! Raiz de composicion: aqui (y solo aqui) se conectan las capas.
use backend_rust::{
    application::{auth::ServicioAuth, casos_uso::ServicioTrazabilidad},
    config::Config,
    infrastructure::{couchdb::RepoCouch, jwt::TokensJwt, telemetria},
    interface::http::router,
};
use std::{sync::Arc, time::Duration};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    let c = Config::desde_entorno().unwrap_or_else(|e| panic!("{e}"));
    let metrics_addr = c
        .metrics_addr
        .parse()
        .unwrap_or_else(|e| panic!("METRICS_ADDR invalida: {e}"));
    telemetria::instalar(metrics_addr).unwrap_or_else(|e| panic!("No se pudo abrir /metrics: {e}"));
    telemetria::lanzar_muestreo_proceso();

    let http = reqwest::Client::builder()
        .pool_max_idle_per_host(64)
        .build()
        .unwrap();
    let repo = RepoCouch::new(
        http,
        &c.couch_url,
        &c.couch_db,
        &c.couch_user,
        &c.couch_pass,
    );
    for intento in 1..=10 {
        let r = match repo.asegurar_db().await {
            Ok(()) => match repo.asegurar_politicas().await {
                Ok(()) => repo.asegurar_indices().await,
                e => e,
            },
            e => e,
        };
        match r {
            Ok(()) => break,
            Err(e) if intento == 10 => panic!("No se pudo preparar CouchDB: {e}"),
            Err(e) => {
                tracing::warn!("CouchDB no listo ({e}), reintento {intento}/10");
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
    let servicio = ServicioTrazabilidad::new(Arc::new(telemetria::RepoMedido::new(Arc::new(repo))));
    let tokens = TokensJwt::new(&c.jwt_secret, &c.jwt_emisor, c.jwt_vigencia_s);
    let auth = ServicioAuth::new(c.usuarios, Arc::new(tokens));
    let app = router(servicio, auth);
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await.unwrap();
    tracing::info!("API escuchando en :8080 (metricas en {})", c.metrics_addr);
    axum::serve(listener, app).await.unwrap();
}
