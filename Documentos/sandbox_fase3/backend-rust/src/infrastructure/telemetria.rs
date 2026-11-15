//! Telemetria (Fase 3 §3.3 / Fase 4 punto 3): exportador Prometheus, duracion de cada transaccion
//! contra la base y muestreo de recursos del propio proceso (hilos, memoria, CPU).
use crate::application::puertos::{ErrorRepo, EventoRepositorio, ResultadoGuardado};
use crate::domain::evento::EventoLote;
use async_trait::async_trait;
use metrics::{counter, gauge, histogram};
use metrics_exporter_prometheus::{
    Matcher, PrometheusBuilder, PrometheusHandle, PrometheusRecorder,
};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};

/// Cubetas en segundos: de 0,25 ms a 5 s (la meta SMART es p95 < 15 ms, hace falta resolucion ahi).
const CUBETAS: [f64; 16] = [
    0.00025, 0.0005, 0.001, 0.002, 0.003, 0.005, 0.0075, 0.010, 0.015, 0.025, 0.050, 0.100, 0.250,
    0.500, 1.0, 5.0,
];

fn constructor() -> PrometheusBuilder {
    PrometheusBuilder::new()
        .set_buckets_for_metric(Matcher::Suffix("_seconds".into()), &CUBETAS)
        .expect("cubetas validas")
}

/// Arranca el servidor `/metrics` en `addr` y registra el recorder global. Llamar dentro de Tokio.
pub fn instalar(addr: std::net::SocketAddr) -> Result<(), String> {
    constructor()
        .with_http_listener(addr)
        .install()
        .map_err(|e| e.to_string())
}

/// Recorder global sin servidor HTTP: devuelve un handle para leer el texto de Prometheus (pruebas).
pub fn instalar_en_memoria() -> PrometheusHandle {
    let recorder: PrometheusRecorder = constructor().build_recorder();
    let handle = recorder.handle();
    metrics::set_global_recorder(recorder).expect("recorder global ya instalado");
    handle
}

/// Decorador del repositorio: mide la duracion de cada transaccion con la base.
pub struct RepoMedido {
    interno: Arc<dyn EventoRepositorio>,
}

impl RepoMedido {
    pub fn new(interno: Arc<dyn EventoRepositorio>) -> Self {
        Self { interno }
    }
}

fn resultado<T, E>(r: &Result<T, E>) -> &'static str {
    if r.is_ok() {
        "ok"
    } else {
        "error"
    }
}

#[async_trait]
impl EventoRepositorio for RepoMedido {
    async fn guardar(&self, e: &EventoLote) -> Result<ResultadoGuardado, ErrorRepo> {
        let t = Instant::now();
        let r = self.interno.guardar(e).await;
        histogram!("db_tx_duration_seconds", "op" => "guardar", "resultado" => resultado(&r))
            .record(t.elapsed().as_secs_f64());
        if matches!(r, Ok(ResultadoGuardado::Duplicado)) {
            counter!("eventos_duplicados_total").increment(1);
        }
        r
    }

    async fn por_lote(&self, lote_id: &str) -> Result<Vec<EventoLote>, ErrorRepo> {
        let t = Instant::now();
        let r = self.interno.por_lote(lote_id).await;
        histogram!("db_tx_duration_seconds", "op" => "por_lote", "resultado" => resultado(&r))
            .record(t.elapsed().as_secs_f64());
        r
    }
}

/// Lee `Threads`, `VmRSS` (kB) y CPU acumulada (s) de /proc/self. `None` fuera de Linux.
fn leer_proc() -> Option<(f64, f64, f64)> {
    let estado = std::fs::read_to_string("/proc/self/status").ok()?;
    let campo = |k: &str| -> Option<f64> {
        estado
            .lines()
            .find_map(|l| l.strip_prefix(k))
            .and_then(|v| v.split_whitespace().next())
            .and_then(|v| v.parse().ok())
    };
    let hilos = campo("Threads:")?;
    let rss_bytes = campo("VmRSS:")? * 1024.0;
    // /proc/self/stat: utime y stime son los campos 14 y 15; se cuentan tras el ")" del nombre.
    let stat = std::fs::read_to_string("/proc/self/stat").ok()?;
    let resto: Vec<&str> = stat.rsplit_once(')')?.1.split_whitespace().collect();
    let ticks: f64 = resto.get(11)?.parse::<f64>().ok()? + resto.get(12)?.parse::<f64>().ok()?;
    Some((hilos, rss_bytes, ticks / 100.0)) // CLK_TCK = 100 en Linux
}

/// Publica cada segundo hilos del SO, memoria, CPU y estado del runtime de Tokio.
pub fn lanzar_muestreo_proceso() {
    tokio::spawn(async move {
        let rt = tokio::runtime::Handle::current();
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        loop {
            tick.tick().await;
            let m = rt.metrics();
            gauge!("tokio_workers").set(m.num_workers() as f64);
            gauge!("tokio_alive_tasks").set(m.num_alive_tasks() as f64);
            if let Some((hilos, rss, cpu)) = leer_proc() {
                gauge!("process_threads").set(hilos);
                gauge!("process_resident_memory_bytes").set(rss);
                gauge!("process_cpu_seconds_total").set(cpu);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    #[test]
    #[cfg(target_os = "linux")]
    fn lee_recursos_del_proceso() {
        let (hilos, rss, _cpu) = super::leer_proc().unwrap();
        assert!(hilos >= 1.0 && rss > 0.0);
    }
}
