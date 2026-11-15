use thiserror::Error;

#[derive(Debug, Error, PartialEq)]
pub enum ErrorDominio {
    #[error("{0}")]
    Invalido(String),
    /// El usuario esta autenticado pero su rol no permite la operacion (HTTP 403).
    #[error("{0}")]
    Prohibido(String),
}
