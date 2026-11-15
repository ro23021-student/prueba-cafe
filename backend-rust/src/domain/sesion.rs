//! Identidad autenticada y reglas de acceso por rol (RBAC). Replica en el backend las reglas de
//! `validate_doc_update` de CouchDB (defensa en profundidad, Fase 3 §3.4.2): el backend entra a
//! CouchDB como administrador, asi que la politica real para los clientes se aplica aqui.
use super::{error::ErrorDominio, evento::EventoLote};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rol {
    /// Crea y edita eventos de lotes de su cooperativa.
    Tecnico,
    /// Solo escribe y lee documentos donde `owner` es el mismo.
    Productor,
    /// Solo lectura (certificadoras y compradores).
    Auditor,
}

impl Rol {
    pub fn parse(s: &str) -> Result<Self, ErrorDominio> {
        match s {
            "tecnico" => Ok(Self::Tecnico),
            "productor" => Ok(Self::Productor),
            "auditor" => Ok(Self::Auditor),
            otro => Err(ErrorDominio::Invalido(format!("rol desconocido: {otro}"))),
        }
    }
    pub fn como_str(&self) -> &'static str {
        match self {
            Self::Tecnico => "tecnico",
            Self::Productor => "productor",
            Self::Auditor => "auditor",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sesion {
    pub usuario: String,
    pub rol: Rol,
    /// `None` = sin restriccion de cooperativa.
    pub cooperativa: Option<String>,
}

impl Sesion {
    fn en_su_cooperativa(&self, e: &EventoLote) -> bool {
        self.cooperativa
            .as_deref()
            .is_none_or(|c| c == e.cooperativa_id)
    }

    pub fn autorizar_escritura(&self, e: &EventoLote) -> Result<(), ErrorDominio> {
        match self.rol {
            Rol::Auditor => Err(ErrorDominio::Prohibido(
                "El rol auditor es de solo lectura.".into(),
            )),
            Rol::Productor if e.owner != self.usuario => Err(ErrorDominio::Prohibido(
                "Un productor solo escribe documentos propios.".into(),
            )),
            _ if !self.en_su_cooperativa(e) => Err(ErrorDominio::Prohibido(
                "El evento pertenece a otra cooperativa.".into(),
            )),
            _ => Ok(()),
        }
    }

    pub fn puede_leer(&self, e: &EventoLote) -> bool {
        match self.rol {
            Rol::Productor => e.owner == self.usuario,
            Rol::Tecnico | Rol::Auditor => self.en_su_cooperativa(e),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Usuario {
    pub nombre: String,
    pub clave: String,
    pub rol: Rol,
    pub cooperativa: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn ev(owner: &str, coop: &str) -> EventoLote {
        EventoLote::desde_json(&json!({"type":"evento_lote","lote_id":"L","cooperativa_id":coop,"etapa":"secado","ts":1,"owner":owner})).unwrap()
    }
    fn s(rol: Rol, usuario: &str, coop: Option<&str>) -> Sesion {
        Sesion {
            usuario: usuario.into(),
            rol,
            cooperativa: coop.map(Into::into),
        }
    }

    #[test]
    fn auditor_no_escribe_pero_lee_su_cooperativa() {
        let a = s(Rol::Auditor, "a", Some("C1"));
        assert!(a.autorizar_escritura(&ev("x", "C1")).is_err());
        assert!(a.puede_leer(&ev("x", "C1")));
        assert!(!a.puede_leer(&ev("x", "C2")));
    }
    #[test]
    fn productor_solo_lo_propio() {
        let p = s(Rol::Productor, "p1", None);
        assert!(p.autorizar_escritura(&ev("p1", "C1")).is_ok());
        assert!(p.autorizar_escritura(&ev("p2", "C1")).is_err());
        assert!(p.puede_leer(&ev("p1", "C9")));
        assert!(!p.puede_leer(&ev("p2", "C9")));
    }
    #[test]
    fn tecnico_limitado_por_cooperativa() {
        let t = s(Rol::Tecnico, "t", Some("C1"));
        assert!(t.autorizar_escritura(&ev("cualquiera", "C1")).is_ok());
        assert!(matches!(
            t.autorizar_escritura(&ev("x", "C2")),
            Err(ErrorDominio::Prohibido(_))
        ));
        assert!(s(Rol::Tecnico, "t", None)
            .autorizar_escritura(&ev("x", "C2"))
            .is_ok());
    }
    #[test]
    fn rol_desconocido_se_rechaza() {
        assert!(Rol::parse("root").is_err());
        assert_eq!(Rol::parse("auditor").unwrap().como_str(), "auditor");
    }
}
