//! Casos de uso. Orquestan dominio + puertos; no conocen HTTP ni CouchDB.
use super::puertos::{ErrorRepo, EventoRepositorio, ResultadoGuardado};
use crate::domain::{error::ErrorDominio, evento::EventoLote, sesion::Sesion};
use serde_json::Value;
use std::sync::Arc;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ErrorApp {
    #[error(transparent)]
    Dominio(#[from] ErrorDominio),
    #[error(transparent)]
    Repo(#[from] ErrorRepo),
}

#[derive(Clone)]
pub struct ServicioTrazabilidad {
    repo: Arc<dyn EventoRepositorio>,
}

impl ServicioTrazabilidad {
    pub fn new(repo: Arc<dyn EventoRepositorio>) -> Self {
        Self { repo }
    }

    /// Valida el esquema, aplica el RBAC de la sesion y solo entonces toca la base.
    pub async fn registrar_evento(
        &self,
        sesion: &Sesion,
        entrada: &Value,
    ) -> Result<ResultadoGuardado, ErrorApp> {
        let evento = EventoLote::desde_json(entrada)?;
        sesion.autorizar_escritura(&evento)?;
        Ok(self.repo.guardar(&evento).await?)
    }

    /// Devuelve solo los eventos que la sesion puede ver.
    pub async fn consultar_lote(
        &self,
        sesion: &Sesion,
        lote_id: &str,
    ) -> Result<Vec<EventoLote>, ErrorApp> {
        if lote_id.trim().is_empty() {
            return Err(ErrorDominio::Invalido("lote_id vacio".into()).into());
        }
        let mut eventos = self.repo.por_lote(lote_id).await?;
        eventos.retain(|e| sesion.puede_leer(e));
        Ok(eventos)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::sesion::Rol;
    use async_trait::async_trait;
    use serde_json::json;
    use std::{collections::HashMap, sync::Mutex};

    #[derive(Default)]
    struct Memoria(Mutex<HashMap<String, EventoLote>>);

    #[async_trait]
    impl EventoRepositorio for Memoria {
        async fn guardar(&self, e: &EventoLote) -> Result<ResultadoGuardado, ErrorRepo> {
            let mut m = self.0.lock().unwrap();
            if m.contains_key(&e.id()) {
                return Ok(ResultadoGuardado::Duplicado);
            }
            m.insert(e.id(), e.clone());
            Ok(ResultadoGuardado::Creado)
        }
        async fn por_lote(&self, l: &str) -> Result<Vec<EventoLote>, ErrorRepo> {
            Ok(self
                .0
                .lock()
                .unwrap()
                .values()
                .filter(|e| e.lote_id == l)
                .cloned()
                .collect())
        }
    }

    fn tecnico() -> Sesion {
        Sesion {
            usuario: "t".into(),
            rol: Rol::Tecnico,
            cooperativa: None,
        }
    }

    fn ev() -> Value {
        json!({"type":"evento_lote","lote_id":"L-1","cooperativa_id":"C1","etapa":"beneficio","ts":5,"owner":"u"})
    }

    #[tokio::test]
    async fn registrar_es_idempotente_y_consultable() {
        let s = ServicioTrazabilidad::new(Arc::new(Memoria::default()));
        let t = tecnico();
        assert_eq!(
            s.registrar_evento(&t, &ev()).await.unwrap(),
            ResultadoGuardado::Creado
        );
        assert_eq!(
            s.registrar_evento(&t, &ev()).await.unwrap(),
            ResultadoGuardado::Duplicado
        );
        assert_eq!(s.consultar_lote(&t, "L-1").await.unwrap().len(), 1);
    }
    #[tokio::test]
    async fn no_llega_al_repositorio_si_el_dominio_rechaza() {
        let s = ServicioTrazabilidad::new(Arc::new(Memoria::default()));
        assert!(matches!(
            s.registrar_evento(&tecnico(), &json!({"x":1})).await,
            Err(ErrorApp::Dominio(_))
        ));
        assert!(s.consultar_lote(&tecnico(), " ").await.is_err());
    }
    #[tokio::test]
    async fn auditor_no_escribe_y_productor_solo_ve_lo_suyo() {
        let s = ServicioTrazabilidad::new(Arc::new(Memoria::default()));
        let auditor = Sesion {
            usuario: "a".into(),
            rol: Rol::Auditor,
            cooperativa: None,
        };
        assert!(matches!(
            s.registrar_evento(&auditor, &ev()).await,
            Err(ErrorApp::Dominio(ErrorDominio::Prohibido(_)))
        ));
        s.registrar_evento(&tecnico(), &ev()).await.unwrap(); // owner = "u"
        let ajeno = Sesion {
            usuario: "otro".into(),
            rol: Rol::Productor,
            cooperativa: None,
        };
        let dueno = Sesion {
            usuario: "u".into(),
            rol: Rol::Productor,
            cooperativa: None,
        };
        assert!(s.consultar_lote(&ajeno, "L-1").await.unwrap().is_empty());
        assert_eq!(s.consultar_lote(&dueno, "L-1").await.unwrap().len(), 1);
    }
}
