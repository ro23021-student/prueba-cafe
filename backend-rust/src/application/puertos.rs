//! Puertos: contratos que la infraestructura debe cumplir.
use crate::domain::{evento::EventoLote, sesion::Sesion};
use async_trait::async_trait;
use thiserror::Error;

#[derive(Debug, PartialEq, Eq)]
pub enum ResultadoGuardado {
    Creado,
    Duplicado,
}

#[derive(Debug, Error)]
pub enum ErrorRepo {
    #[error("sin conexion con la base de datos: {0}")]
    Conexion(String),
    #[error("respuesta inesperada de la base de datos: {0}")]
    Inesperado(String),
}

#[async_trait]
pub trait EventoRepositorio: Send + Sync {
    async fn guardar(&self, evento: &EventoLote) -> Result<ResultadoGuardado, ErrorRepo>;
    async fn por_lote(&self, lote_id: &str) -> Result<Vec<EventoLote>, ErrorRepo>;
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ErrorToken {
    #[error("token invalido o vencido")]
    Invalido,
    #[error("no se pudo emitir el token: {0}")]
    Emision(String),
}

/// Emision y verificacion de tokens de sesion (la infraestructura usa JWT).
pub trait Tokens: Send + Sync {
    /// Devuelve el token y su vigencia en segundos.
    fn emitir(&self, sesion: &Sesion) -> Result<(String, u64), ErrorToken>;
    fn verificar(&self, token: &str) -> Result<Sesion, ErrorToken>;
}
