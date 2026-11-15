// E1: estres del backend (sin degradacion de red). Meta original p95 < 15 ms (no alcanzable en 2 nucleos); meta revisada p95 < 1000 ms hasta 100 usuarios (Fase 5).
import http from 'k6/http';
import { check } from 'k6';
import { Trend } from 'k6/metrics';
const TARGET = __ENV.TARGET || 'http://api-rust:8080';
const VUS = parseInt(__ENV.VUS || '500', 10);
const DURACION = __ENV.DURATION || '240s';
const SUBIDA = __ENV.RAMP_UP || '30s';
const BAJADA = __ENV.RAMP_DOWN || '30s';
const tWrite = new Trend('lat_write', true);
export const options = {
  scenarios: {
    carga: { executor: 'ramping-vus', startVUs: 0,
      stages: [{duration: SUBIDA, target: VUS}, {duration: DURACION, target: VUS}, {duration: BAJADA, target: 0}] },
  },
  thresholds: { http_req_failed: ['rate<0.01'], lat_write: ['p(95)<1000'] },
};
export function setup() {
  // Todas las arquitecturas (T, C0, C1) exigen JWT: el login se hace una vez, fuera de la medicion.
  if (!__ENV.LOAD_PASS) throw new Error('Falta LOAD_PASS (variable del .env)');
  const r = http.post(`${TARGET}/auth/login`, JSON.stringify({user: 'load', pass: __ENV.LOAD_PASS}),
                      {headers: {'Content-Type': 'application/json'}});
  if (r.status !== 200) throw new Error(`Login fallido (HTTP ${r.status}): ${r.body}`);
  return { token: r.json('token') };
}
export default function (d) {
  const h = { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${d.token}` } };
  const doc = { type: 'evento_lote', lote_id: `L-${__VU}-${__ITER}`, cooperativa_id: 'COOP-01',
                etapa: 'recoleccion', ts: Math.floor(Date.now() / 1000), owner: 'load', peso_kg: 42.5 };
  const w = http.post(`${TARGET}/v1/eventos`, JSON.stringify(doc), h);
  tWrite.add(w.timings.duration);
  check(w, { 'escritura 2xx': (r) => r.status >= 200 && r.status < 300 });
  http.get(`${TARGET}/v1/lotes/${doc.lote_id}`, { ...h, tags: { name: 'GET /v1/lotes/:id' } });
}
