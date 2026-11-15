//! Entidad de dominio: un evento en la cadena de trazabilidad de un lote de cafe.
//! Esquema flexible: los campos conocidos se validan; el resto (`extra`) se conserva tal cual.
use super::error::ErrorDominio;
use serde_json::{Map, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Etapa {
    Recoleccion,
    Beneficio,
    Secado,
    Almacen,
    Despacho,
}

impl Etapa {
    pub fn parse(s: &str) -> Result<Self, ErrorDominio> {
        match s {
            "recoleccion" => Ok(Self::Recoleccion),
            "beneficio" => Ok(Self::Beneficio),
            "secado" => Ok(Self::Secado),
            "almacen" => Ok(Self::Almacen),
            "despacho" => Ok(Self::Despacho),
            _ => Err(ErrorDominio::Invalido("Etapa invalida".into())),
        }
    }
    pub fn como_str(&self) -> &'static str {
        match self {
            Self::Recoleccion => "recoleccion",
            Self::Beneficio => "beneficio",
            Self::Secado => "secado",
            Self::Almacen => "almacen",
            Self::Despacho => "despacho",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct EventoLote {
    pub lote_id: String,
    pub cooperativa_id: String,
    pub etapa: Etapa,
    pub ts: i64,
    pub owner: String,
    pub extra: Map<String, Value>,
}

const CONOCIDOS: [&str; 6] = ["type", "lote_id", "cooperativa_id", "etapa", "ts", "owner"];

impl EventoLote {
    pub const TIPO: &'static str = "evento_lote";

    /// Construye y valida desde JSON (tambien sirve para documentos leidos de la BD).
    pub fn desde_json(v: &Value) -> Result<Self, ErrorDominio> {
        let obj = v
            .as_object()
            .ok_or_else(|| ErrorDominio::Invalido("El documento debe ser un objeto JSON".into()))?;
        for campo in CONOCIDOS {
            if !obj.contains_key(campo) {
                return Err(ErrorDominio::Invalido(format!(
                    "Campo obligatorio: {campo}"
                )));
            }
        }
        if obj["type"].as_str() != Some(Self::TIPO) {
            return Err(ErrorDominio::Invalido(format!(
                "type debe ser \"{}\"",
                Self::TIPO
            )));
        }
        let texto = |k: &str| -> Result<String, ErrorDominio> {
            match obj[k].as_str() {
                Some(s) if !s.trim().is_empty() => Ok(s.to_string()),
                _ => Err(ErrorDominio::Invalido(format!(
                    "{k} debe ser texto no vacio"
                ))),
            }
        };
        let ts = obj["ts"]
            .as_i64()
            .ok_or_else(|| ErrorDominio::Invalido("ts debe ser un entero (epoch)".into()))?;
        let etapa = Etapa::parse(obj["etapa"].as_str().unwrap_or(""))?;
        let extra = obj
            .iter()
            .filter(|(k, _)| !CONOCIDOS.contains(&k.as_str()) && !k.starts_with('_'))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        Ok(Self {
            lote_id: texto("lote_id")?,
            cooperativa_id: texto("cooperativa_id")?,
            etapa,
            ts,
            owner: texto("owner")?,
            extra,
        })
    }

    /// Identificador determinista: un reintento del cliente produce el mismo _id (idempotencia).
    pub fn id(&self) -> String {
        format!("{}:{}", self.lote_id, self.ts)
    }

    pub fn a_json(&self) -> Value {
        let mut m = self.extra.clone();
        m.insert("type".into(), Self::TIPO.into());
        m.insert("lote_id".into(), self.lote_id.clone().into());
        m.insert("cooperativa_id".into(), self.cooperativa_id.clone().into());
        m.insert("etapa".into(), self.etapa.como_str().into());
        m.insert("ts".into(), self.ts.into());
        m.insert("owner".into(), self.owner.clone().into());
        Value::Object(m)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn base() -> Value {
        json!({"type":"evento_lote","lote_id":"L-1","cooperativa_id":"C1","etapa":"secado","ts":1700000000,"owner":"u1","peso_kg":42.5})
    }

    #[test]
    fn acepta_y_conserva_campos_extra() {
        let e = EventoLote::desde_json(&base()).unwrap();
        assert_eq!(e.etapa, Etapa::Secado);
        assert_eq!(e.extra["peso_kg"], json!(42.5));
        assert_eq!(e.a_json()["peso_kg"], json!(42.5));
        assert_eq!(e.id(), "L-1:1700000000");
    }
    #[test]
    fn rechaza_etapa_tipo_ts_y_vacios() {
        for (campo, valor) in [
            ("etapa", json!("x")),
            ("type", json!("otro")),
            ("ts", json!("hoy")),
            ("owner", json!("  ")),
        ] {
            let mut d = base();
            d[campo] = valor;
            assert!(EventoLote::desde_json(&d).is_err(), "{campo}");
        }
        let mut d = base();
        d.as_object_mut().unwrap().remove("lote_id");
        assert!(EventoLote::desde_json(&d).is_err());
        assert!(EventoLote::desde_json(&json!([1])).is_err());
    }
    #[test]
    fn ignora_campos_internos_de_couchdb() {
        let mut d = base();
        d["_id"] = json!("a");
        d["_rev"] = json!("1-x");
        assert!(!EventoLote::desde_json(&d)
            .unwrap()
            .extra
            .contains_key("_rev"));
    }
}
