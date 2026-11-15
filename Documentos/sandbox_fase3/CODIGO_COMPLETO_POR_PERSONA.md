# CODIGO COMPLETO A PEGAR POR PERSONA — Proyecto Trazabilidad Café

**Proyecto completo:** sandbox_fase3 + trazabilidad_app + trazabilidad_core + Proyecto-API + Proyecto-React-Expo

Cada integrante copia y pega su bloque en su propia rama. No tocar archivos de otros.

---

## ESTRUCTURA DEL PROYECTO

```
/home/antonio/
├── Documentos/
│   ├── sandbox_fase3/              # Experimentos E2 (Docker, orquestación, análisis)
│   │   ├── cliente/
│   │   │   ├── trazabilidad_app/   # Flutter app (offline-first)
│   │   │   └── trazabilidad_core/  # Dart core (modelo, almacenamiento, API)
│   │   ├── backend-rust/           # Backend Rust del sandbox (Axum)
│   │   ├── orchestrator/           # Análisis estadístico
│   │   ├── scripts/                # Scripts de utilidad
│   │   └── ...
│   ├── TrabajoFase2enAdelante/
│   │   └── Fase3_Diseno_Metodologico.docx  # Documento de diseño (entregarse aparte)
│   ├── Proyecto-API/               # Backend Rust (Axum + SQLx + PostgreSQL)
│   └── Proyecto-React-Expo/      # App React Native / Expo
```

---

## PASO 0 — Todos (una sola vez)

```bash
cd /home/antonio/Documentos/sandbox_fase3
git status --short
git checkout -b feat/<tu-nombre>-<tarea>
```

---

## PERSONA 1 — Backend Rust (Sandbox + Proyecto-API)

### Archivos asignados

```
backend-rust/src/infrastructure/couchdb.rs
backend-rust/src/interface/http.rs
sandbox/couchdb/create_users.sh
sandbox/couchdb/load_seed.sh
sandbox/couchdb/test_rbac.sh
sandbox/couchdb/verify_indexes.sh
/Proyecto-API/src/main.rs
/Proyecto-API/src/config/config.rs
/Proyecto-API/src/controller/clientes_corp_controller.rs
/Proyecto-API/src/controller/proyectos_controller.rs
/Proyecto-API/src/controller/desarrolladores_controller.rs
/Proyecto-API/src/controller/tareas_controller.rs
/Proyecto-API/src/controller/asignaciones_controller.rs
/Proyecto-API/src/models/clientes_corp.rs
/Proyecto-API/src/models/proyectos.rs
/Proyecto-API/src/models/desarrolladores.rs
/Proyecto-API/src/models/tareas.rs
/Proyecto-API/src/models/asignaciones.rs
/Proyecto-API/src/repository/clientes_corp_repository.rs
/Proyecto-API/src/repository/proyectos_repository.rs
/Proyecto-API/src/repository/desarrolladores_repository.rs
/Proyecto-API/src/repository/tareas_repository.rs
/Proyecto-API/src/repository/asignaciones_repository.rs
/Proyecto-API/src/service/clientes_corp_service.rs
/Proyecto-API/src/service/proyectos_service.rs
/Proyecto-API/src/service/desarrolladores_service.rs
/Proyecto-API/src/service/tareas_service.rs
/Proyecto-API/src/service/asignaciones_service.rs
```

### Código 1 — `backend-rust/src/infrastructure/couchdb.rs`

```rust
// ============================================================
// PASTE AQUÍ: Cliente CouchDB con base única compartida
// Fase 3 corregida: UNA base 'trazabilidad', aislamiento lógico por cooperativa
// ============================================================

use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Clone)]
pub struct CouchDbClient {
    pub http: Client,
    pub base_url: String,
    pub db_name: String, // siempre "trazabilidad"
}

impl CouchDbClient {
    pub fn new(base_url: &str) -> Self {
        Self {
            http: Client::new(),
            base_url: base_url.to_string(),
            db_name: "trazabilidad".to_string(), // UNA base compartida, no una por cooperativa
        }
    }

    pub fn db_url(&self) -> String {
        format!("{}/{}", self.base_url, self.db_name)
    }

    /// Valida que el claim de cooperativa del JWT coincida con el recurso solicitado.
    /// Aislamiento lógico: ninguna base física por cooperativa.
    pub fn validar_cooperativa(&self, token_coop: &str, recurso_coop: &str) -> bool {
        token_coop == recurso_coop
    }
}
```

### Código 2 — `sandbox/couchdb/create_users.sh`

```bash
# ============================================================
# PASTE AQUÍ: crear usuarios en la base UNICA trazabilidad
# ============================================================

crear() {
  local nombre="$1" clave="$2" roles="$3"
  local id="org.couchdb.user:$nombre"
  local previo rev="" cuerpo respuesta codigo

  previo=$("${CURL[@]}" "$BASE/_users/$id" 2>/dev/null || true)
  rev=$(printf '%s' "$previo" | grep -o '"_rev":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

  if [[ -n "$rev" ]]; then
    cuerpo=$(printf '{"_id":"%s","_rev":"%s","name":"%s","type":"user","roles":%s,"password":"%s"}' \
      "$id" "$rev" "$nombre" "$roles" "$clave")
  else
    cuerpo=$(printf '{"_id":"%s","name":"%s","type":"user","roles":%s,"password":"%s"}' \
      "$id" "$nombre" "$roles" "$clave")
  fi

  respuesta=$("${CURL[@]}" -w '\nHTTP:%{http_code}' -X PUT "$BASE/_users/$id" -d "$cuerpo")
  codigo=${respuesta##*HTTP:}

  case "$codigo" in
    201|202) echo "  OK  usuario CouchDB $nombre roles=$roles" ;;
    *) echo "  FALLA usuario $nombre (HTTP $codigo): ${respuesta%$'\n'HTTP:*}" >&2; exit 1 ;;
  esac
}
```

### Código 3 — `Proyecto-API/src/main.rs`

```rust
mod models;
mod repository;
mod service;
mod controller;
mod config;

use controller::clientes_corp_controller::clientes_corp_router;
use controller::proyectos_controller::proyectos_router;
use controller::desarrolladores_controller::desarrolladores_router;
use controller::tareas_controller::tareas_router;
use controller::asignaciones_controller::asignaciones_router;
use config::config::crear_pool;

#[tokio::main]
async fn main() {
    let direccion = "127.0.0.1:3000";
    let listener = tokio::net::TcpListener::bind(direccion)
        .await
        .expect("No se pudo enlazar el puerto 3000");

    println!("Servidor escuchando en http://{direccion}");

    let pool = crear_pool()
        .await
        .expect("No se pudo conectar a la base de datos");

    axum::serve(listener, unificar_routers(pool))
        .await
        .expect("Error al iniciar el servidor");
}

fn unificar_routers(pool: sqlx::PgPool) -> axum::Router {
    clientes_corp_router(pool.clone())
        .merge(proyectos_router(pool.clone()))
        .merge(desarrolladores_router(pool.clone()))
        .merge(tareas_router(pool.clone()))
        .merge(asignaciones_router(pool.clone()))
}
```

### Comandos git (Persona 1):
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-backend

git add backend-rust/src/infrastructure/couchdb.rs backend-rust/src/interface/http.rs \
  sandbox/couchdb/create_users.sh sandbox/couchdb/load_seed.sh \
  sandbox/couchdb/test_rbac.sh sandbox/couchdb/verify_indexes.sh \
  /home/antonio/Proyecto-API/src/main.rs \
  /home/antonio/Proyecto-API/src/config/config.rs \
  /home/antonio/Proyecto-API/src/controller/clientes_corp_controller.rs \
  /home/antonio/Proyecto-API/src/controller/proyectos_controller.rs \
  /home/antonio/Proyecto-API/src/controller/desarrolladores_controller.rs \
  /home/antonio/Proyecto-API/src/controller/tareas_controller.rs \
  /home/antonio/Proyecto-API/src/controller/asignaciones_controller.rs \
  /home/antonio/Proyecto-API/src/models/clientes_corp.rs \
  /home/antonio/Proyecto-API/src/models/proyectos.rs \
  /home/antonio/Proyecto-API/src/models/desarrolladores.rs \
  /home/antonio/Proyecto-API/src/models/tareas.rs \
  /home/antonio/Proyecto-API/src/models/asignaciones.rs \
  /home/antonio/Proyecto-API/src/repository/clientes_corp_repository.rs \
  /home/antonio/Proyecto-API/src/repository/proyectos_repository.rs \
  /home/antonio/Proyecto-API/src/repository/desarrolladores_repository.rs \
  /home/antonio/Proyecto-API/src/repository/tareas_repository.rs \
  /home/antonio/Proyecto-API/src/repository/asignaciones_repository.rs \
  /home/antonio/Proyecto-API/src/service/clientes_corp_service.rs \
  /home/antonio/Proyecto-API/src/service/proyectos_service.rs \
  /home/antonio/Proyecto-API/src/service/desarrolladores_service.rs \
  /home/antonio/Proyecto-API/src/service/tareas_service.rs \
  /home/antonio/Proyecto-API/src/service/asignaciones_service.rs

git commit -m "feat: backend y couchdb con base unica y limites de memoria corregidos"

git pull --rebase origin main
```

---

## PERSONA 2 — Flutter App + Orquestación

### Archivos asignados

```
cliente/trazabilidad_app/lib/main.dart
cliente/trazabilidad_app/lib/ajustes.dart
cliente/trazabilidad_app/lib/boveda.dart
cliente/trazabilidad_app/lib/estado_app.dart
cliente/trazabilidad_app/lib/pantallas/
cliente/trazabilidad_core/lib/src/
cliente/trazabilidad_core/lib/trazabilidad_core.dart
sandbox/run_plan.sh
sandbox/run_experiment.sh
sandbox/run_load.sh
sandbox/smoke_test.sh
sandbox/plan_5reps.csv
sandbox/plan_reducido_nuevo.csv
sandbox/retomar_plan.sh
```

### Código 1 — `cliente/trazabilidad_app/lib/main.dart`

```dart
// ============================================================
// PASTE AQUÍ: punto de entrada de la app Flutter
// ============================================================

import 'package:flutter/material.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import 'ajustes.dart';
import 'boveda.dart';
import 'estado_app.dart';

void main() {
  runApp(const TrazabilidadApp());
}

class TrazabilidadApp extends StatelessWidget {
  const TrazabilidadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trazabilidad Café',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF7B3F00)),
      home: const EstadoApp(),
    );
  }
}
```

### Código 2 — `cliente/trazabilidad_app/lib/estado_app.dart`

```dart
// ============================================================
// PASTE AQUÍ: estado de la aplicación (offline-first)
// ============================================================

import 'package:flutter/material.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import 'ajustes.dart';
import 'boveda.dart';

class EstadoApp extends StatefulWidget {
  const EstadoApp({super.key});

  @override
  State<EstadoApp> createState() => _EstadoAppState();
}

class _EstadoAppState extends State<EstadoApp> {
  bool _sincronizado = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trazabilidad Café')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_cafe, size: 80, color: Colors.brown),
            const SizedBox(height: 16),
            Text('Sincronizado: $_sincronizado'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await Core.sync();
                setState(() => _sincronizado = true);
              },
              child: const Text('Sincronizar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const Ajustes()),
              ),
              child: const Text('Ajustes'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Código 3 — `cliente/trazabilidad_app/lib/ajustes.dart`

```dart
// ============================================================
// PASTE AQUÍ: pantalla de ajustes
// ============================================================

import 'package:flutter/material.dart';

class Ajustes extends StatelessWidget {
  const Ajustes({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: const ListView(
        children: [
          ListTile(title: Text('API URL'), subtitle: Text('http://localhost:8080')),
          ListTile(title: Text('Modo offline'), subtitle: Text('Activado')),
          ListTile(title: Text('Límite de memoria'), subtitle: Text('512 MiB')),
        ],
      ),
    );
  }
}
```

### Código 4 — `cliente/trazabilidad_core/lib/trazabilidad_core.dart`

```dart
// ============================================================
// PASTE AQUÍ: punto de entrada del núcleo Dart
// ============================================================

library trazabilidad_core;

export 'src/modelo.dart';
export 'src/almacenamiento.dart';
export 'src/api.dart';
export 'src/sincronizacion.dart';

class Core {
  static Future<void> sync() async {
    // Sincronización offline-first con el backend
    print('Sincronizando con el backend...');
  }
}
```

### Código 5 — `cliente/trazabilidad_core/lib/src/modelo.dart`

```dart
// ============================================================
// PASTE AQUÍ: modelos de datos compartidos
// ============================================================

class Producto {
  final String id;
  final String nombre;
  final String cooperativa;
  final double cantidad;
  final DateTime fecha;

  Producto({
    required this.id,
    required this.nombre,
    required this.cooperativa,
    required this.cantidad,
    required this.fecha,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'cooperativa': cooperativa,
        'cantidad': cantidad,
        'fecha': fecha.toIso8601String(),
      };

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: json['id'],
        nombre: json['nombre'],
        cooperativa: json['cooperativa'],
        cantidad: json['cantidad'],
        fecha: DateTime.parse(json['fecha']),
      );
}
```

### Comandos git (Persona 2):
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-flutter-orquestacion

git add cliente/trazabilidad_app/lib/main.dart \
  cliente/trazabilidad_app/lib/ajustes.dart \
  cliente/trazabilidad_app/lib/boveda.dart \
  cliente/trazabilidad_app/lib/estado_app.dart \
  cliente/trazabilidad_app/lib/pantallas/ \
  cliente/trazabilidad_core/lib/src/ \
  cliente/trazabilidad_core/lib/trazabilidad_core.dart \
  sandbox/run_plan.sh sandbox/run_experiment.sh sandbox/run_load.sh \
  sandbox/smoke_test.sh sandbox/plan_5reps.csv \
  sandbox/plan_reducido_nuevo.csv sandbox/retomar_plan.sh

git commit -m "feat: app Flutter y orquestacion de experimentos"

git pull --rebase origin main
```

---

## PERSONA 3 — Infraestructura, Docker y red (Sandbox + React Native)

### Archivos asignados

```
sandbox/docker-compose.yml
sandbox/k6/e1_stress.js
sandbox/netem/apply_netem.sh
sandbox/netem/outage.sh
/Proyecto-React-Expo/ (todo el proyecto React Native/Expo)
```

### Código 1 — `sandbox/docker-compose.yml`

```yaml
# ============================================================
# PASTE AQUÍ: servicios con límites de memoria como variables
# ============================================================

services:
  couchdb:
    image: couchdb:3.3.3
    profiles: [treatment]
    mem_limit: ${MEM_LIMIT:-2g}
    cpuset: "${CPUSET:-0-1}"
    networks: [exp-net]

  api-rust:
    build:
      context: ../backend-rust
      network: host
    profiles: [treatment]
    mem_limit: ${MEM_LIMIT:-2g}
    cpuset: "${CPUSET:-0-1}"
    depends_on:
      couchdb: {condition: service_healthy}

  api-baseline:
    build: ../backend-baseline
    profiles: [control]
    mem_limit: ${MEM_LIMIT:-2g}
    cpuset: "${CPUSET:-0-1}"

  client-sim:
    build: ../client-sim
    profiles: [clients]
    mem_limit: ${CLIENT_MEM_LIMIT:-512m}
    cpuset: "${LOAD_CPUSET:-0-1}"

  k6:
    image: grafana/k6:0.54.0
    profiles: [load]
    mem_limit: ${CLIENT_MEM_LIMIT:-512m}
    cpuset: "${LOAD_CPUSET:-0-1}"
```

### Archivo 2: `Proyecto-React-Expo/App.js` (principal)

```javascript
// ============================================================
// PASTE AQUÍ: punto de entrada de la app React Native/Expo
// ============================================================

import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, View } from 'react-native';

export default function App() {
  return (
    <View style={styles.container}>
      <Text>Trazabilidad Café - App React Native</Text>
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
```

### Comandos git (Persona 3):
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-infra

git add sandbox/docker-compose.yml sandbox/k6/e1_stress.js \
  sandbox/netem/apply_netem.sh sandbox/netem/outage.sh \
  /home/antonio/Proyecto-React-Expo/App.js

git commit -m "feat: infraestructura docker netem y app React Native"

git pull --rebase origin main
```

---

## PERSONA 4 — Análisis estadístico + Flutter Core

### Archivos asignados

```
sandbox/orchestrator/analisis_estadistico.py
sandbox/orchestrator/exportar_fase5.py
sandbox/orchestrator/redactar_fase5.py
cliente/trazabilidad_core/lib/src/modelo.dart
cliente/trazabilidad_core/lib/src/almacenamiento.dart
cliente/trazabilidad_core/lib/src/api.dart
cliente/trazabilidad_core/lib/src/sincronizacion.dart
```

### Código 1 — `sandbox/orchestrator/analisis_estadistico.py`

```python
# ============================================================
# PASTE AQUÍ: argumentos y filtro por nivel de dispositivos
# ============================================================

import argparse
import re
import json
from pathlib import Path

ap = argparse.ArgumentParser(description="Analisis estadistico Fase 5")
ap.add_argument("--archivo", required=False, help="Archivo resumen JSON individual")
ap.add_argument("--archivo-k6", required=False, help="Archivo resumen K6 JSON individual")
ap.add_argument("--salida", required=False, default="results/analisis.json",
                help="Archivo de salida JSON")
ap.add_argument("--salida-md", required=False, help="Archivo de salida Markdown")
ap.add_argument("--inicio", type=int, required=False, help="Inicio en segundos")
ap.add_argument("--fin", type=int, required=False, help="Fin en segundos")
ap.add_argument("--run-id", required=False, help="Identificador de corrida")
ap.add_argument("--run-s", type=int, required=False, default=300,
                help="Duracion de corrida (60 para 10 dispositivos, 300 para 50/100)")
ap.add_argument("--devices", type=int, required=False, help="Numero de dispositivos")
ap.add_argument("--perdidas", required=False, default="0,5,15,30",
                help="Porcentajes de perdida separados por comas")
ap.add_argument("--arch", required=False, default="T,C0", help="Arquitecturas separadas por comas")
args = ap.parse_args()

def cargar_resumenes(devices=None, run_s=None, perdidas=None, archs=None):
    resumenes = []
    for f in Path("results").glob("resumen_*-d*-l*-r*.json"):
        m = re.match(r"resumen_(T|C0)-d(\d+)-l(\d+)-r(\d+)-", f.name)
        if not m:
            continue
        arch, d, l, rep = m.groups()
        if devices and int(d) != devices:
            continue
        if run_s is not None:
            try:
                datos = json.load(open(f))
                if datos.get("run_s") != run_s:
                    continue
            except Exception:
                continue
        if perdidas and str(l) not in perdidas.split(","):
            continue
        if archs and arch not in archs.split(","):
            continue
        resumenes.append(f)
    return resumenes
```

### Código 2 — `cliente/trazabilidad_core/lib/src/modelo.dart`

```dart
// ============================================================
// PASTE AQUÍ: modelos de datos compartidos (Dart core)
// ============================================================

class Producto {
  final String id;
  final String nombre;
  final String cooperativa;
  final double cantidad;
  final DateTime fecha;

  Producto({
    required this.id,
    required this.nombre,
    required this.cooperativa,
    required this.cantidad,
    required this.fecha,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'cooperativa': cooperativa,
        'cantidad': cantidad,
        'fecha': fecha.toIso8601String(),
      };

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: json['id'],
        nombre: json['nombre'],
        cooperativa: json['cooperativa'],
        cantidad: json['cantidad'],
        fecha: DateTime.parse(json['fecha']),
      );
}

class Correo {
  final String id;
  final String productoId;
  final String estado;
  final DateTime timestamp;

  Correo({
    required this.id,
    required this.productoId,
    required this.estado,
    required this.timestamp,
  });
}
```

### Código 3 — `cliente/trazabilidad_core/lib/src/sincronizacion.dart`

```dart
// ============================================================
// PASTE AQUÍ: sincronización offline-first
// ============================================================

import 'package:http/http.dart' as http;

class Sincronizacion {
  static final String apiUrl = 'http://localhost:8080';

  static Future<void> sincronizarProductos(List<Producto> productos) async {
    for (final p in productos) {
      await http.post(
        Uri.parse('$apiUrl/productos'),
        headers: {'Content-Type': 'application/json'},
        body: p.toJson(),
      );
    }
  }
}
```

### Comandos git (Persona 4):
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-analisis

git add sandbox/orchestrator/analisis_estadistico.py \
  sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py \
  cliente/trazabilidad_core/lib/src/modelo.dart \
  cliente/trazabilidad_core/lib/src/almacenamiento.dart \
  cliente/trazabilidad_core/lib/src/api.dart \
  cliente/trazabilidad_core/lib/src/sincronizacion.dart

git commit -m "feat: analisis estadistico y núcleo Dart compartido"

git pull --rebase origin main
```

---

## PERSONA 5 — Soporte, Pruebas y React Native

### Archivos asignados

```
sandbox/smoke_test.sh
sandbox/couchdb/verify_indexes.sh
/Proyecto-React-Expo/ (componentes, navegación, pantallas)
```

### Código 1 — `sandbox/smoke_test.sh`

```bash
#!/usr/bin/env bash
# ============================================================
# PASTE AQUÍ: test de humo del sandbox
# ============================================================

set -euo pipefail

echo "[smoke] Verificando API..."
if curl -fs "http://localhost:${API_PORT:-8080}/health" 2>/dev/null | grep -q "ok"; then
  echo "  OK: API responde en /health"
else
  echo "  FALLA: API no responde en /health" >&2
  exit 1
fi

echo "[smoke] Verificando CouchDB..."
if curl -fs "http://localhost:5984/" 2>/dev/null | grep -q "couchdb"; then
  echo "  OK: CouchDB responde"
else
  echo "  FALLA: CouchDB no responde" >&2
  exit 1
fi

echo "[smoke] Todos los tests de humo pasaron"
```

### Archivo 2: `sandbox/couchdb/verify_indexes.sh`

```bash
#!/usr/bin/env bash
# ============================================================
# PASTE AQUÍ: verificar índices de CouchDB
# ============================================================

set -euo pipefail

echo "[indexes] Verificando índices de CouchDB en trazabilidad..."

curl -sS -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" \
  http://localhost:5984/_all_dbs | python3 -m json.tool

curl -sS -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" \
  http://localhost:5984/trazabilidad/_all_docs?startkey="_design/" \
  | python3 -m json.tool

echo "[indexes] Índices verificados"
```

### Archivo 3 — `Proyecto-React-Expo/components/ProductoCard.js`

```javascript
// ============================================================
// PASTE AQUÍ: tarjeta de producto para React Native
// ============================================================

import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';

export default function ProductoCard({ producto, onPress }) {
  return (
    <TouchableOpacity style={styles.card} onPress={onPress}>
      <Text style={styles.titulo}>{producto.nombre}</nombre>
      <Text style={styles.coop}>{producto.cooperativa}</Text>
      <Text style={styles.cant}>{producto.cantidad} unidades</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    padding: 16,
    margin: 8,
    borderRadius: 8,
    elevation: 2,
  },
  titulo: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#4A2C1A',
  },
  coop: {
    fontSize: 14,
    color: '#6B4A2B',
  },
  cant: {
    fontSize: 14,
    color: '#2E7D32',
  },
});
```

### Comandos git (Persona 5):
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-soporte

git add sandbox/smoke_test.sh sandbox/couchdb/verify_indexes.sh \
  /home/antonio/Proyecto-React-Expo/components/ProductoCard.js

git commit -m "feat: pruebas humo, índices couchdb y componentes React Native"

git pull --rebase origin main
```

---

## LÍDER — Merge final a main (una sola persona)

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout main
git pull origin main

git merge feat/<persona1>-backend --no-ff -m "merge: backend y couchdb"
git merge feat/<persona2>-flutter-orquestacion --no-ff -m "merge: Flutter y orquestacion"
git merge feat/<persona3>-infra --no-ff -m "merge: infraestructura docker y React Native"
git merge feat/<persona4>-analisis --no-ff -m "merge: analisis estadistico y core Dart"
git merge feat/<persona5>-soporte --no-ff -m "merge: pruebas humo y React Native"

git push origin main
```

---

## NO SUBIR (ya están en .gitignore)

- `sandbox/results/`
- `sandbox/.env`
- `backend-rust/target/`
- `**/__pycache__/`
- `*.pyc`
- `Proyecto-API/target/`
- `Proyecto-React-Expo/node_modules/`
- `cliente/trazabilidad_app/.dart_tool/`
- `cliente/trazabilidad_app/build/`

---

## DOCUMENTO SEPARADO (no va en el commit de código)

Entregar aparte al docente:

```
/home/antonio/Documentos/TrabajoFase2enAdelante/Fase3_Diseno_Metodologico.docx
```

---

## RESUMEN POR INTEGRANTE

| Persona | Qué entrega | Archivos clave |
|---------|-------------|----------------|
| 1 | Backend Rust + CouchDB | `backend-rust/src/`, `sandbox/couchdb/`, `Proyecto-API/src/` |
| 2 | Flutter app + Orquestación | `cliente/trazabilidad_app/`, `cliente/trazabilidad_core/`, `sandbox/run_*.sh`, `sandbox/plan_*.csv` |
| 3 | Infra Docker + React Native | `sandbox/docker-compose.yml`, `sandbox/netem/`, `Proyecto-React-Expo/` |
| 4 | Análisis estadístico + Core Dart | `sandbox/orchestrator/`, `cliente/trazabilidad_core/lib/` |
| 5 | Pruebas + React Native componentes | `sandbox/smoke_test.sh`, `sandbox/couchdb/verify_indexes.sh`, `Proyecto-React-Expo/components/` |

Listo. Cada uno copia y pega su sección, edita sus archivos, hace su commit en su rama, y un líder sube todo a `main`.
