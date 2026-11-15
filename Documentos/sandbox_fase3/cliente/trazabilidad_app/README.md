# Cliente Flutter (Fase 4)

Estructura: `trazabilidad_core/` (Dart puro, compartido con el futuro client-sim) y `trazabilidad_app/` (Flutter).

## 1. Probar el núcleo (sin emulador)
    cd trazabilidad_core
    dart pub get
    dart analyze
    dart test

## 2. Preparar la app (una sola vez)
    cd trazabilidad_app
    flutter create --project-name trazabilidad_app --platforms=android,windows,linux .
    # si flutter create reemplazó lib/main.dart o pubspec.yaml, restaura los del zip
    flutter pub get
    flutter analyze

Android + sandbox (HTTP sin TLS): en `android/app/src/main/AndroidManifest.xml`, dentro de `<application ...>`,
añade `android:usesCleartextTraffic="true"` (solo para el sandbox; en producción se usa HTTPS).

## 3. Ejecutar contra el sandbox
    cd sandbox && docker compose --profile treatment up -d
    cd ../cliente/trazabilidad_app && flutter run

- Emulador Android: la URL por defecto ya es `http://10.0.2.2:8080`.
- Teléfono físico: en la pestaña Sincronización pon `http://IP_DE_TU_PC:8080`.
- Escritorio (Windows/Linux): `http://localhost:8080`.

## 3b. Iniciar sesión (JWT) y roles
La API exige token. En la pestaña **Sincronización** escribe usuario y clave (los del `.env` del sandbox:
`load`/`sim` = técnico, `auditor` = solo lectura, `productor` = solo documentos propios). La app recuerda la URL
y el usuario; la clave y la clave de cifrado de la cola se guardan en el almacén seguro del sistema
(`flutter_secure_storage`). Sin sesión, los eventos se guardan en el teléfono y quedan *Pendientes*.
La cola local está cifrada (AES-256-GCM). Si el sistema restaura el archivo pero no la clave, la app conserva
el archivo ilegible aparte y avisa; el workflow de APK desactiva `allowBackup` para evitarlo.

## 4. Prueba de offline-first
1. Registra un evento con el sandbox encendido -> pasa a «Sincronizado».
2. `docker compose --profile treatment stop api-rust`, registra otro -> queda «Pendiente».
3. `docker compose --profile treatment start api-rust` -> en pocos segundos pasa a «Sincronizado».
4. Verifica: `curl http://localhost:8080/v1/lotes/ID_DEL_LOTE`
