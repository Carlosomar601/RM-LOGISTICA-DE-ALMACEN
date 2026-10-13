# Piqueo FIFO Centeno

Demo funcional (Flutter) del módulo de **logística de almacén y piqueo FIFO** para Centeno Tire — Retail Manager.
Sin backend ni persistencia: todo el estado vive en memoria y se reinicia al cerrar o recargar la app.
La fecha "hoy" del demo es fija: **15 sept 2026 · 09:00** (`lib/util/clock.dart`).

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
flutter test                   # 29 pruebas: motor FIFO, estado, flujos y overflow a 360/768/1440 px
flutter analyze
flutter build web              # salida en build\web
```

## Logo

Copia los dos archivos (520×253, fondo transparente) en `assets/`:

- `assets/logo_on_dark.webp` — texto blanco (tema oscuro)
- `assets/logo_on_light.webp` — tinta navy #0b0e21 (tema claro)

Mientras no estén, la app muestra un logo de respaldo en texto.

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
