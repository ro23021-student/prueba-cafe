//! Configuracion desde variables de entorno (sin valores por defecto para secretos).
use crate::domain::sesion::{Rol, Usuario};

pub struct Config {
    pub couch_url: String,
    pub couch_db: String,
    pub couch_user: String,
    pub couch_pass: String,
    pub jwt_secret: String,
    pub jwt_emisor: String,
    pub jwt_vigencia_s: u64,
    pub usuarios: Vec<Usuario>,
    pub metrics_addr: String,
}

/// `AUTH_USERS` = "usuario:clave:rol[:cooperativa],usuario2:clave2:rol2" (sin ':' ni ',' en los valores).
pub fn parsear_usuarios(texto: &str) -> Result<Vec<Usuario>, String> {
    let mut out = Vec::new();
    for item in texto.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        let p: Vec<&str> = item.split(':').collect();
        if !(3..=4).contains(&p.len()) || p[0].is_empty() || p[1].is_empty() {
            return Err("AUTH_USERS: cada entrada es usuario:clave:rol[:cooperativa]".into());
        }
        let rol = Rol::parse(p[2]).map_err(|e| format!("AUTH_USERS: {e}"))?;
        let cooperativa = p.get(3).filter(|c| !c.is_empty()).map(|c| c.to_string());
        if out.iter().any(|u: &Usuario| u.nombre == p[0]) {
            return Err(format!("AUTH_USERS: usuario repetido: {}", p[0]));
        }
        out.push(Usuario {
            nombre: p[0].into(),
            clave: p[1].into(),
            rol,
            cooperativa,
        });
    }
    if out.is_empty() {
        return Err("AUTH_USERS no define ningun usuario".into());
    }
    Ok(out)
}

impl Config {
    pub fn desde_entorno() -> Result<Self, String> {
        let req = |k: &str| std::env::var(k).map_err(|_| format!("Falta la variable {k}"));
        let jwt_secret = req("JWT_SECRET")?;
        if jwt_secret.len() < 16 {
            return Err("JWT_SECRET debe tener al menos 16 caracteres".into());
        }
        Ok(Self {
            couch_url: req("COUCHDB_URL")?,
            couch_db: std::env::var("COUCHDB_DB").unwrap_or_else(|_| "trazabilidad".into()),
            couch_user: req("COUCHDB_USER")?,
            couch_pass: req("COUCHDB_PASSWORD")?,
            jwt_secret,
            jwt_emisor: std::env::var("JWT_ISSUER")
                .unwrap_or_else(|_| "trazabilidad-sandbox".into()),
            jwt_vigencia_s: std::env::var("JWT_TTL_S")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(3600),
            usuarios: parsear_usuarios(&req("AUTH_USERS")?)?,
            metrics_addr: std::env::var("METRICS_ADDR").unwrap_or_else(|_| "0.0.0.0:9100".into()),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parsea_usuarios_con_y_sin_cooperativa() {
        let u = parsear_usuarios("load:abc:tecnico, ana:xyz:productor:C1").unwrap();
        assert_eq!(u.len(), 2);
        assert_eq!(u[1].cooperativa.as_deref(), Some("C1"));
        assert_eq!(u[0].cooperativa, None);
    }
    #[test]
    fn rechaza_entradas_malas() {
        for malo in [
            "",
            "solo",
            "a:b:root",
            ":b:tecnico",
            "a:b:tecnico,a:c:auditor",
        ] {
            assert!(parsear_usuarios(malo).is_err(), "{malo}");
        }
    }
}
