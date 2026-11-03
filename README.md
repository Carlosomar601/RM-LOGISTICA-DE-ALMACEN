# Retail Manager Logistics & Warehouse

Demo funcional (Flutter) del módulo de **logística de almacén y piqueo FIFO** para Centeno Tire — Retail Manager.
Los datos se guardan en el PC (`C:\ProgramData\RetailManager\PiqueoFIFO\data.json`) y se respaldan según una
programación (ver *Datos y respaldos*).

- **PC instalado** (hay `config.json`): fecha real y, en el primer arranque, un almacén vacío.
- **Desarrollo** (`flutter run`, sin `config.json`) y **pruebas**: datos de demostración y fecha fija
  **15 sept 2026 · 09:00** (`lib/util/clock.dart`, `demoMode`).

## Ejecutar

```powershell
cd "D:\PROGRAMACION CARLOS OMAR\Logistica de almacen\v2"
flutter pub get
flutter run -d chrome          # web
flutter run -d windows         # escritorio Windows
```

Si `flutter` no está en el PATH, usa la ruta completa: `& "D:\FLUTTER SDK\flutter\bin\flutter.bat" run -d chrome`.

Otras tareas:

```powershell
flutter test                   # 149 pruebas: motor FIFO, estado, RM, sesión, datos guardados, respaldos, overflow a 360/768/1440 px
flutter analyze
flutter test integration_test/rm_import_live_test.dart -d windows   # E2E contra la API real (localhost:8180, solo lectura)
flutter build web              # salida en build\web
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1   # instalador fuera de línea (ver installer/README.md)
powershell -ExecutionPolicy Bypass -File installeruild_installer.ps1   # instalador fuera de línea (ver installer/README.md)
```

## Administración

La sección **Administración** (antes «Usuarios») tiene cinco pestañas: **Usuarios**, **Tiendas** (nombre, código, dirección API y clave,
botón *Probar conexión* simulado), **Canastas** (por almacén: código, zona, capacidad, activar/desactivar), **Roles**
(permisos por defecto de cada rol) y **Parámetros** (umbrales de antigüedad y nombre de empresa/almacén).
Las listas de tiendas y canastas de Transferencias y Recibido salen de aquí. El almacén central y las canastas de recepción
(RECIBO, AL-RX…) son fijos; una tienda con historial no se renombra ni elimina (se desactiva).
La dirección API de cada tienda es la URL base de su `rmapiv2` (p. ej. `http://servidor:8180/cse.api.v1`; si omites
`/cse.api.v1` se agrega sola). *Probar conexión* llama a `HealthCheck`.

### Importar recibos desde RM

En **Recibido sin ubicar → Importar desde RM** eliges una tienda con API y un rango de fechas (por defecto, el último día),
la app consulta `RecReceiptsByDate` y muestra lo que entraría. Al confirmar, cada recibo de RM se crea como `RM-<n.º de recibo>`
pendiente de ubicar, con la fecha real del recibo (alimenta el FIFO). Es **solo lectura** contra RM y es idempotente por `LineID`
(reimportar no duplica; líneas nuevas de un recibo ya importado se suman). Los productos que no existan se crean con el código
y la descripción que trae el recibo. Las cantidades decimales se redondean al entero más cercano.
La ubicación en canastas queda solo en la app; no se escribe nada de vuelta en RM.

### Órdenes y facturas de RM

Endpoints de RMApiV2 1.12.0 (solicitud original en `docs/SOLICITUD_API_ORDENES.md`): `OrdOpenOrders` (foto de órdenes
abiertas) y `SalesInvoicesByDate` (facturas; la API acepta máximo 31 días por llamada, la app pide por tramos). Contra una
API anterior, la app informa "endpoint aún no disponible" sin fallar.

- Las órdenes entran como `ORD-<n>` y las facturas como `FAC-<n>` en **Órdenes entrantes** (botón *Sincronizar con RM*).
- **Ventas en caja** (transacciones 10, 11, 12 y 19: el cliente se lleva la mercancía) **no** se despachan; la lista se cambia
  en Parámetros. De cada factura se despacha lo vendido menos lo anulado (`VoidedQuantity`); si RM anula parte de una
  factura ya importada, se ajusta (o se marca para revisar si ya se empezó a piquear).
- Una orden que cambia en RM se actualiza si aún no se piquea; si ya se empezó, queda marcada para revisar.
- **Una orden que se convierte en factura no se despacha dos veces**: la factura se enlaza a su orden ("Facturada en RM")
  y solo entra lo que exceda lo ordenado ("Adicional a ORD-n"). Lo piqueado se anota en un libro de despachos
  (`C:\ProgramData\RetailManager\PiqueoFIFO\ledger.json`, 90 días, compartido por todas las cuentas del PC; antes
  estaba en `%APPDATA%` y se copia solo la primera vez) para que esto se cumpla también después de reiniciar la app.
- Si una factura llega antes que su orden (se facturó entre dos sincronizaciones), la orden entra marcada
  "Revisar antes de piquear".

### Sincronización automática

**Administración → Parámetros → Sincronización con RM**: frecuencia (solo manual, cada hora, cada 2 horas, una vez al día,
cada 2 días), días a recuperar al abrir y botón *Sincronizar ahora*. Trae recibos del almacén central, facturas y órdenes de
cada tienda con API. Corre solo con la app abierta (la app arranca con Windows) y al abrirla si la frecuencia es automática.
La configuración se guarda en `%APPDATA%\RetailManager\PiqueoFIFO\settings.json`.

## Inicio de sesión (PIN)

La app abre en una pantalla de PIN: cada empleado entra con su **PIN de 4 dígitos** (teclado en pantalla o físico) y
todo lo que hace (recibos, piqueos, transferencias, historial) queda a su nombre. *Cerrar sesión* está al pie de la barra
lateral (en pantallas angostas, en el círculo con las iniciales), junto a *Cambiar mi PIN*.

- Los PIN se asignan en **Administración → Usuarios** (cada PIN es único). Un usuario sin PIN no puede entrar.
- 5 PIN incorrectos bloquean el teclado 30 s. La sesión se cierra sola tras 10 minutos sin uso (se cambia en
  Administración → Parámetros → Seguridad; 0 = nunca). Un piqueo en curso no se pierde al cerrar sesión.
- Usuarios, PIN (SHA-256 con sal), roles y seguridad se guardan en `C:\ProgramData\RetailManager\PiqueoFIFO\users.json`,
  compartido por todas las cuentas de Windows del PC. Cada inicio, cierre, PIN incorrecto y bloqueo se anota en
  `audit.log` (misma carpeta) y se ve en Administración → Usuarios → *Actividad de sesiones*.
- Sin `users.json` (solo al desarrollar con `flutter run`) se usan los usuarios de demostración: administrador 1111,
  supervisora 2222, piqueador 3333. En un PC instalado eso nunca ocurre: el instalador crea el primer administrador.

## Datos y respaldos

- **Guardado automático**: inventario, recibos, órdenes, piqueos en curso, transferencias, historial, tiendas, canastas
  y parámetros se escriben en `C:\ProgramData\RetailManager\PiqueoFIFO\data.json` 2 segundos después de cada cambio
  (y al cerrar la ventana), con escritura atómica. Usuarios y PIN siguen en `users.json`.
- **data.json dañado**: la app abre, avisa en la pantalla de PIN y en Administración → Respaldos, y **no guarda encima**.
  Un administrador restaura un respaldo o elige *Empezar vacío* (el archivo dañado se aparta como `data.danado-….json`).
- **Administración → Respaldos**:
  - frecuencia (solo manual, todos los días, dos veces por semana, una vez por semana, una vez al mes);
  - días de la semana o día del mes (1–28), hora;
  - carpeta (por defecto `…\PiqueoFIFO\backups`; puede ser un USB o `\\servidor\carpeta`, con *Probar carpeta*);
  - *Conservar los últimos N* (30 por defecto) y *Respaldar ahora*.
- **Cuándo corre**: con la app abierta (arranca con Windows). Si a la hora programada estaba cerrada, respalda al abrirla.
  Si la carpeta no está disponible, reintenta cada 30 min.
- **Qué guarda**: `RMLogistics-respaldo-AAAA-MM-DD_HHMM.zip` con `manifest.json`, `data.json`, `users.json` (PIN
  cifrado), `audit.log`, `ledger.json`, `settings.json` y `config.json`. Solo se borran los zip con ese nombre.
- **Restaurar** (lista de respaldos → *Restaurar*):
  - se valida el zip y se pide el PIN del administrador;
  - antes se hace un respaldo `…-antes-de-restaurar.zip`;
  - reemplaza datos, usuarios, libro de despachos y sincronización, y cierra la sesión;
  - no toca la dirección API del PC (`config.json`) ni `audit.log`;
  - un respaldo sin ningún administrador activo con PIN se rechaza.
- Cada respaldo, fallo y restauración queda en `audit.log`.

## Logo

Incluidos en `assets/` (1040×501, fondo transparente; ya traen "Logistics & Warehouse"):

- `assets/logo_on_dark.webp` — texto blanco (tema oscuro)
- `assets/logo_on_light.webp` — tinta navy #0b0e21 (tema claro), generado a partir del anterior

Si faltaran, la app muestra un logo de respaldo en texto.

## Notas técnicas

- **Tipografías**: Barlow Condensed, IBM Plex Sans e IBM Plex Mono van empaquetadas en `assets/fonts` (licencia OFL)
  en lugar de usar el paquete `google_fonts`. Ese paquete arrastra un *native-assets hook* (`objective_c`) que no compila
  cuando el SDK de Flutter está en una ruta con espacios (`D:\FLUTTER SDK`), y además así el demo funciona sin internet.
- **Estado**: un único `Notifier<AppState>` de Riverpod (`lib/state/app_state.dart`).
- **Motor de piqueo**: Dart puro, sin Flutter (`lib/state/pick_engine.dart`), con pruebas en `test/pick_engine_test.dart`.
- **Órdenes parciales**: cada artículo guarda lo ya entregado; al recalcular una orden parcial solo se piquea lo pendiente.

## Guion sugerido para la presentación

1. **Dashboard** → expandir `MI-20565R15` (bins en orden FIFO) y bajar a *Inventario sin movimiento* (4 lotes ≥ 180 días).
2. **Órdenes entrantes** → `OV-10501` → *Calcular ruta*: p3 usa C-03-02 (8) + A-02-01 (7); p6 usa A-01-04 (7) + B-01-02 (3).
3. En p6 marcar B-01-02 *No está aquí* → aparece el faltante de 3 y la sugerencia *Sucursal Bayamón · SB-02*.
4. *Transferir 3 a Almacén Central* → abre Transferencias → Entre tiendas prellenado. Enviar y *Confirmar recepción*.
5. Volver a la orden → *↺ Recalcular ruta* en p6 → marcar otra vez B-01-02 *No está aquí*: ahora la ruta completa
   con el bin de recepción `AL-RX` en lugar de declarar faltante. Verificar y confirmar.
6. **Piqueo FIFO** → 40 unidades de p1 recorren 3 canastas (14 + 20 + 6).
7. **Recibido sin ubicar** → REC-3430 en 25 / 25 / 50.
8. **Usuarios** → *Ver como este usuario* (Juan Nieves) → solo Dashboard, Órdenes, Piqueo y Resumen.
