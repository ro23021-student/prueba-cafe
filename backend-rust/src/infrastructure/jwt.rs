//! Adaptador JWT (HS256) del puerto `Tokens`. `exp` e `iss` son obligatorios (Fase 3 §3.4.2).
use crate::application::puertos::{ErrorToken, Tokens};
use crate::domain::sesion::{Rol, Sesion};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: String,
    rol: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    coop: Option<String>,
    iss: String,
    exp: u64,
}

pub struct TokensJwt {
    enc: EncodingKey,
    dec: DecodingKey,
    emisor: String,
    vigencia_s: u64,
}

impl TokensJwt {
    pub fn new(secreto: &str, emisor: &str, vigencia_s: u64) -> Self {
        Self {
            enc: EncodingKey::from_secret(secreto.as_bytes()),
            dec: DecodingKey::from_secret(secreto.as_bytes()),
            emisor: emisor.into(),
            vigencia_s,
        }
    }
    fn ahora() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }
}

impl Tokens for TokensJwt {
    fn emitir(&self, s: &Sesion) -> Result<(String, u64), ErrorToken> {
        let c = Claims {
            sub: s.usuario.clone(),
            rol: s.rol.como_str().into(),
            coop: s.cooperativa.clone(),
            iss: self.emisor.clone(),
            exp: Self::ahora() + self.vigencia_s,
        };
        let t = encode(&Header::new(Algorithm::HS256), &c, &self.enc)
            .map_err(|e| ErrorToken::Emision(e.to_string()))?;
        Ok((t, self.vigencia_s))
    }

    fn verificar(&self, token: &str) -> Result<Sesion, ErrorToken> {
        let mut v = Validation::new(Algorithm::HS256);
        v.set_issuer(&[&self.emisor]);
        v.set_required_spec_claims(&["exp", "iss", "sub"]);
        v.leeway = 0;
        let c = decode::<Claims>(token, &self.dec, &v)
            .map_err(|_| ErrorToken::Invalido)?
            .claims;
        let rol = Rol::parse(&c.rol).map_err(|_| ErrorToken::Invalido)?;
        Ok(Sesion {
            usuario: c.sub,
            rol,
            cooperativa: c.coop,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ses() -> Sesion {
        Sesion {
            usuario: "ana".into(),
            rol: Rol::Tecnico,
            cooperativa: Some("C1".into()),
        }
    }

    #[test]
    fn ida_y_vuelta() {
        let t = TokensJwt::new("secreto-de-prueba-largo", "sandbox", 60);
        let (tok, vig) = t.emitir(&ses()).unwrap();
        assert_eq!(vig, 60);
        assert_eq!(t.verificar(&tok).unwrap(), ses());
    }
    #[test]
    fn rechaza_firma_ajena_emisor_distinto_vencido_y_basura() {
        let t = TokensJwt::new("secreto-de-prueba-largo", "sandbox", 60);
        let (tok, _) = t.emitir(&ses()).unwrap();
        assert!(TokensJwt::new("otro-secreto-distinto-123", "sandbox", 60)
            .verificar(&tok)
            .is_err());
        assert!(TokensJwt::new("secreto-de-prueba-largo", "otro-emisor", 60)
            .verificar(&tok)
            .is_err());
        assert!(t.verificar("no.es.jwt").is_err());
        // vigencia 0 => exp == ahora => ya vencido (leeway 0)
        let (caducado, _) = TokensJwt::new("secreto-de-prueba-largo", "sandbox", 0)
            .emitir(&ses())
            .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        assert!(t.verificar(&caducado).is_err());
    }
}
