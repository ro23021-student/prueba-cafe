//! Middleware que mide cada peticion HTTP: latencia por endpoint, conteo por codigo y concurrencia.
use axum::{
    extract::{MatchedPath, Request},
    middleware::Next,
    response::Response,
};
use metrics::{counter, gauge, histogram};
use std::time::Instant;

pub async fn medir(req: Request, next: Next) -> Response {
    // La ruta con plantilla (/v1/lotes/:id) evita una serie por cada lote (cardinalidad acotada).
    let endpoint = req
        .extensions()
        .get::<MatchedPath>()
        .map_or_else(|| "no_encontrado".to_string(), |m| m.as_str().to_string());
    let metodo = req.method().as_str().to_string();
    gauge!("http_requests_in_flight").increment(1.0);
    let t = Instant::now();
    let resp = next.run(req).await;
    let seg = t.elapsed().as_secs_f64();
    gauge!("http_requests_in_flight").decrement(1.0);
    let codigo = resp.status().as_u16().to_string();
    histogram!("http_request_duration_seconds", "endpoint" => endpoint.clone(), "method" => metodo.clone()).record(seg);
    counter!("http_requests_total", "endpoint" => endpoint, "method" => metodo, "status" => codigo)
        .increment(1);
    resp
}
