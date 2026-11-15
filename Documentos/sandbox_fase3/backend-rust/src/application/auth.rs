//! Caso de uso de autenticacion: valida credenciales y emite/verifica tokens (via el puerto `Tokens`).
use super::puertos::{ErrorToken, Tokens};
use crate::domain::sesion::{Sesion, Usuario};
use std::sync::Arc;
use subtle::ConstantTimeEq;
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ErrorAuth {
    #[error("credenciales invalidas")]
    Credenciales,
    #[error(transparent)]
    Token(#[from] ErrorToken),
}

#[derive(Clone)]
pub struct ServicioAuth {
    usuarios: Arc<Vec<Usuario>>,
    tokens: Arc<dyn Tokens>,
}

pub struct TokenEmitido {
    pub token: String,
    pub expira_en_s: u64,
    pub sesion: Sesion,
}

impl ServicioAuth {
    pub fn new(usuarios: Vec<Usuario>, tokens: Arc<dyn Tokens>) -> Self {
        Self {
            usuarios: Arc::new(usuarios),
            tokens,
        }
    }

    pub fn login(&self, nombre: &str, clave: &str) -> Result<TokenEmitido, ErrorAuth> {
        // Se compara contra todos los usuarios y en tiempo constante para no filtrar por tiempo
        // cual de los dos datos (usuario o clave) fallo.
        let mut hallado: Option<&Usuario> = None;
        for u in self.usuarios.iter() {
            let ok = u.nombre.as_bytes().ct_eq(nombre.as_bytes())
                & u.clave.as_bytes().ct_eq(clave.as_bytes());
            if bool::from(ok) {
                hallado = Some(u);
            }
        }
        let u = hallado.ok_or(ErrorAuth::Credenciales)?;
        let sesion = Sesion {
            usuario: u.nombre.clone(),
            rol: u.rol,
            cooperativa: u.cooperativa.clone(),
        };
        let (token, expira_en_s) = self.tokens.emitir(&sesion)?;
        Ok(TokenEmitido {
            token,
            expira_en_s,
            sesion,
        })
    }

    pub fn verificar(&self, token: &str) -> Result<Sesion, ErrorAuth> {
        Ok(self.tokens.verificar(token)?)
    }
}
