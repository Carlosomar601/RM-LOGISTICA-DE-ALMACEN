# Instalador de Piqueo FIFO Centeno

Instalador de Windows (Inno Setup 6) que funciona **sin internet**: lleva dentro la app y el runtime de Visual C++.

## Generarlo

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1     # -SkipBuild para no recompilar
```

Resultado: `installer\Output\PiqueoFIFO-Setup-<versión>.exe` (~34 MB). La versión sale de `pubspec.yaml`.
Requisitos en la PC que compila: Flutter, Inno Setup 6 e internet **solo la primera vez**, para descargar
`VC_redist.x64.exe` de Microsoft a `installer\redist\` (se verifica la firma de Microsoft).

## Qué hace al instalar

1. Copia la app a `C:\Program Files\Retail Manager\Piqueo FIFO`.
2. Instala el runtime de Visual C++ si falta (desde el propio instalador).
3. Pide la dirección de RMApiV2 (por defecto `http://localhost:8180`), con botón *Probar conexión*.
   La guarda en `C:\ProgramData\RetailManager\PiqueoFIFO\config.json`; la app la usa al abrir.
4. **Primer administrador** (solo si el PC aún no tiene `users.json`): pide nombre y un PIN de 4 dígitos. Crea
   `C:\ProgramData\RetailManager\PiqueoFIFO\users.json` con el PIN cifrado (SHA-256 con sal, nunca en claro).
   Reinstalar o actualizar no toca los usuarios existentes.
5. Da permiso de escritura a los empleados (cuentas estándar de Windows) sobre esa carpeta, para guardar usuarios y PIN.
6. Crea accesos en el menú Inicio y el escritorio, y la abre al iniciar sesión en Windows (opciones marcadas por defecto).
7. **Prueba final**: ejecuta `piqueo_fifo_centeno.exe --selftest` (sin ventana), que revisa los usuarios (al menos un
   administrador activo con PIN; si no, falla), la configuración, `HealthCheck` y `RecReceiptsByDate` (solo lectura).
   El resultado aparece en la última página del asistente y en `C:\ProgramData\RetailManager\PiqueoFIFO\selftest.log`.
   Las órdenes (`OrdOpenOrders`) y facturas (`SalesInvoicesByDate`) se revisan sin hacer fallar la prueba:
   si la API aún no las tiene, aparecen como "aún no disponible".
8. Deja la app abierta, en la pantalla de PIN.

## Instalación silenciosa

```
PiqueoFIFO-Setup-1.0.0.exe /VERYSILENT /SUPPRESSMSGBOXES /API=http://servidor:8180 /LOG=C:\ruta\setup.log
```

En un PC **nuevo** (sin `users.json`) agrega `/ADMINNAME="Nombre Apellido" /ADMINPIN=1234`; sin ellos la instalación
se cancela (código 1) para no dejar una app a la que nadie puede entrar.
**Cuidado:** Inno Setup copia la línea de comandos completa en el `/LOG`, así que el PIN queda escrito ahí. Borra ese
log después, o cambia el PIN desde la app ("Cambiar mi PIN").

Código de salida: `0` instalado y prueba final OK; `100` instalado, pero la prueba final falló (ver `selftest.log`).
Nota: `Start-Process -Wait` de PowerShell no termina, porque espera también a la app que queda abierta;
usa `-PassThru` y espera el proceso del instalador por su cuenta.

Desinstalar desde *Configuración → Aplicaciones*; se conservan `config.json`, `users.json` y `audit.log` para una
reinstalación. Si se borra `users.json` en un PC instalado, la app no deja entrar a nadie (nunca vuelve a usuarios de
demostración): vuelve a ejecutar el instalador para crear el administrador.

## Prueba sin red (Windows Sandbox)

Con la característica *Windows Sandbox* activada, abre `installer\test-offline.wsb`: arranca un Windows limpio sin red
y lanza el instalador. Se espera que instale todo y abra la app; la prueba final marcará la API como inaccesible,
porque dentro del sandbox no hay RMApiV2.
