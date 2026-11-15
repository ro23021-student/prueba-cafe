//! Capa de interfaz: traduce HTTP <-> casos de uso. Sin logica de negocio.
//! Rutas: /health (libre), POST /auth/login (libre), /v1/* (exige JWT).
use crate::application::{
    auth::{ErrorAuth, ServicioAuth},
    casos_uso::{ErrorApp, ServicioTrazabilidad},
    puertos::{ErrorRepo, ResultadoGuardado},
};
use crate::domain::{error::ErrorDominio, sesion::Sesion};
use axum::{
    extract::{Path, Request, State},
    http::{header::AUTHORIZATION, StatusCode},
    middleware::{from_fn, from_fn_with_state, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
    Extension, Json, Router,
};
use metrics::counter;
use serde::Deserialize;
use serde_json::{json, Value};

pub fn router(servicio: ServicioTrazabilidad, auth: ServicioAuth) -> Router {
    let protegidas = Router::new()
        .route("/v1/eventos", post(crear_evento))
        .route("/v1/lotes/:id", get(leer_lote))
        .with_state(servicio)
        .route_layer(from_fn_with_state(auth.clone(), exigir_sesion));
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/auth/login", post(login).with_state(auth))
        .merge(protegidas)
        .layer(from_fn(super::telemetria::medir))
}

enum ErrorHttp {
    App(ErrorApp),
    Auth(ErrorAuth),
    SinToken,
}

impl IntoResponse for ErrorHttp {
    fn into_response(self) -> Response {
        let (codigo, msg) = match &self {
            Self::App(ErrorApp::Dominio(ErrorDominio::Invalido(m))) => {
                (StatusCode::UNPROCESSABLE_ENTITY, m.clone())
            }
            Self::App(ErrorApp::Dominio(ErrorDominio::Prohibido(m))) => {
                (StatusCode::FORBIDDEN, m.clone())
            }
            Self::App(ErrorApp::Repo(e)) => {
                // Diagnostico de los 502: sin esto no se sabe si fue timeout, conexion
                // rechazada o un 5xx de CouchDB bajo saturacion.
                let (tipo, m) = match e {
                    ErrorRepo::Conexion(m) => ("conexion", m),
                    ErrorRepo::Inesperado(m) => ("inesperado", m),
                };
                counter!("errores_repo_total", "tipo" => tipo).increment(1);
                tracing::warn!(tipo, detalle = %m, "502: fallo del repositorio");
                (StatusCode::BAD_GATEWAY, m.clone())
            }
            Self::Auth(ErrorAuth::Credenciales) => {
                (StatusCode::UNAUTHORIZED, "credenciales invalidas".into())
            }
            Self::Auth(ErrorAuth::Token(e)) => (StatusCode::UNAUTHORIZED, e.to_string()),
            Self::SinToken => (
                StatusCode::UNAUTHORIZED,
                "falta el encabezado Authorization: Bearer <token>".into(),
            ),
        };
        let mut resp = (codigo, Json(json!({ "error": msg }))).into_response();
        if codigo == StatusCode::UNAUTHORIZED {
            resp.headers_mut().insert(
                "www-authenticate",
                "Bearer".parse().expect("valor fijo valido"),
            );
        }
        resp
    }
}

impl From<ErrorApp> for ErrorHttp {
    fn from(e: ErrorApp) -> Self {
        Self::App(e)
    }
}

/// Verifica el JWT y deja la `Sesion` disponible para los handlers.
async fn exigir_sesion(
    State(auth): State<ServicioAuth>,
    mut req: Request,
    next: Next,
) -> Result<Response, ErrorHttp> {
    let token = req
        .headers()
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or(ErrorHttp::SinToken)
        .inspect_err(|_| counter!("auth_rechazos_total", "motivo" => "sin_token").increment(1))?;
    let sesion = auth
        .verificar(token)
        .map_err(ErrorHttp::Auth)
        .inspect_err(|_| {
            counter!("auth_rechazos_total", "motivo" => "token_invalido").increment(1)
        })?;
    req.extensions_mut().insert(sesion);
    Ok(next.run(req).await)
}

#[derive(Deserialize)]
struct Credenciales {
    user: String,
    pass: String,
}

async fn login(
    State(auth): State<ServicioAuth>,
    Json(c): Json<Credenciales>,
) -> Result<Json<Value>, ErrorHttp> {
    match auth.login(&c.user, &c.pass) {
        Ok(t) => {
            counter!("auth_login_total", "resultado" => "ok").increment(1);
            Ok(Json(json!({
                "token": t.token,
                "expires_in": t.expira_en_s,
                "rol": t.sesion.rol.como_str(),
                "cooperativa": t.sesion.cooperativa,
            })))
        }
        Err(e) => {
            counter!("auth_login_total", "resultado" => "error").increment(1);
            Err(ErrorHttp::Auth(e))
        }
    }
}

async fn crear_evento(
    State(s): State<ServicioTrazabilidad>,
    Extension(sesion): Extension<Sesion>,
    Json(entrada): Json<Value>,
) -> Result<(StatusCode, Json<Value>), ErrorHttp> {
    match s.registrar_evento(&sesion, &entrada).await? {
        ResultadoGuardado::Creado => Ok((StatusCode::CREATED, Json(json!({ "ok": true })))),
        ResultadoGuardado::Duplicado => Ok((StatusCode::OK, Json(json!({ "duplicado": true })))),
    }
}

async fn leer_lote(
    State(s): State<ServicioTrazabilidad>,
    Extension(sesion): Extension<Sesion>,
    Path(id): Path<String>,
) -> Result<Json<Value>, ErrorHttp> {
    let eventos = s.consultar_lote(&sesion, &id).await?;
    Ok(Json(
        json!({ "lote_id": id, "eventos": eventos.iter().map(|e| e.a_json()).collect::<Vec<_>>() }),
    ))
}
