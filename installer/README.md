# Instalador de Retail Manager Logistics & Warehouse

Instalador de Windows (Inno Setup 6) que funciona **sin internet**. Lleva dentro tres cosas:

- la aplicación (cliente);
- el servidor (`rm_server.exe`), que se registra como servicio de Windows con WinSW;
- el runtime de Visual C++.

## Cómo funciona con varios equipos

Un solo PC (el **servidor**) guarda la base de datos del almacén: `data.json`, `users.json`, `ledger.json`, los
respaldos y la auditoría, en `C:\ProgramData\RetailManager\PiqueoFIFO`.

Los demás PC con Windows y los equipos Android son **clientes**:

- Se conectan al servidor por la red local (puerto TCP **8190**).
- Ven los cambios de los demás al instante.
- No guardan datos propios.

El servidor también es el único que:

- sincroniza con RMApiV2 (cada hora, cada día, etc., aunque nadie tenga la app abierta);
- hace los respaldos programados;
- comprueba los PIN.

## Generarlo

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1     # -SkipBuild para no recompilar
```

Resultado: `installer\Output\RMLogistics-Setup-<versión>.exe`. La versión sale de `pubspec.yaml`.

Requisitos en la PC que compila: Flutter e Inno Setup 6. Internet hace falta **solo la primera vez**, para
descargar a `installer\redist\`:

- `VC_redist.x64.exe` de Microsoft (se verifica la firma de Microsoft);
- `WinSW-x64.exe` 2.12.0 de GitHub (se verifica su SHA-256).

## Tipos de instalación

| Tipo (`/TYPE=`) | Para qué PC | Qué instala |
|---|---|---|
| `both` (por defecto) | El PC principal, o una sola PC | Servidor + aplicación (la app se conecta a `localhost:8190`) |
| `server` | Un PC dedicado (puede no tener pantalla) | Solo el servidor |
| `client` | Las demás PC del almacén | Solo la aplicación; pide la dirección del servidor |

**Actualizar una instalación 1.1** (una sola PC): elige `both`. El servidor toma los datos que ya están en
`ProgramData`; no hay migración.

Instala primero el servidor y después los clientes.

## Qué hace al instalar

### Servidor (`both` o `server`)

1. Detiene el servicio si ya existía y cierra la app, para que nunca haya dos programas escribiendo los datos.
2. Copia `rm_server.exe` y el servicio a `C:\Program Files\Retail Manager\Logistics & Warehouse\server`.
3. Pide la dirección de RMApiV2 (por defecto `http://localhost:8180`), con botón *Probar conexión*.
4. **Primer administrador** (solo si aún no hay `users.json`): pide nombre y un PIN de 4 dígitos. El PIN se
   guarda cifrado (SHA-256 con sal).
5. Registra el servicio **RM Logistics Server**:
   - arranque automático;
   - se reinicia solo si falla;
   - al detenerse guarda los datos;
   - deja sus registros en `ProgramData\...\logs` y `server.log`.
6. Abre el firewall de Windows solo para la red local: TCP 8190 (conexión) y UDP 8191 (búsqueda automática).
7. Copia la configuración de sincronización que este usuario tenía en la versión 1.1.

### Cliente (`both` o `client`)

1. Copia la app y crea accesos en el menú Inicio, el escritorio y el inicio de sesión de Windows.
2. Solo `client`: pide la dirección del servidor (nombre o IP, por ejemplo `192.168.1.20`), con *Probar
   conexión*. En la app también se cambia desde la pantalla de PIN, con **Servidor: … · Cambiar**, que además
   **busca servidores en la red** automáticamente.
3. Instala el runtime de Visual C++ si falta.

### Configuración y prueba final

Todo se guarda en `C:\ProgramData\RetailManager\PiqueoFIFO\config.json`, con los campos `apiUrl`, `mode` y
`serverUrl`.

La **prueba final** cambia según el tipo:

- **Servidor:** `rm_server.exe --selftest` revisa los usuarios (un administrador activo con PIN), los datos y
  RMApiV2. Deja el resultado en `selftest.log`. Después inicia el servicio y espera a que conteste en el puerto 8190.
- **Cliente:** `piqueo_fifo_centeno.exe --selftest` comprueba que el servidor conteste (`/health`) y que sea la
  misma versión del protocolo. Deja el resultado en `selftest-cliente.log`.

El resultado aparece en la última página del asistente.

## Instalación silenciosa

```
:: Servidor (primera vez):
RMLogistics-Setup-1.3.0.exe /VERYSILENT /SUPPRESSMSGBOXES /TYPE=both /API=http://servidor:8180 /ADMINNAME="Nombre Apellido" /ADMINPIN=1234 /LOG=C:\ruta\setup.log
:: Cliente:
RMLogistics-Setup-1.3.0.exe /VERYSILENT /SUPPRESSMSGBOXES /TYPE=client /SERVER=192.168.1.20
```

- En un servidor **nuevo** (sin `users.json`) es obligatorio `/ADMINPIN`. En un cliente es obligatorio `/SERVER`.
  Si falta alguno, la instalación se cancela (código 1).
- **Cuidado:** Inno Setup copia la línea de comandos completa en el `/LOG`, así que el PIN queda escrito ahí.
  Borra ese log después, o cambia el PIN desde la app ("Cambiar mi PIN").
- **Códigos de salida:** `0` instalado y prueba final OK; `100` instalado, pero la prueba final falló.
- `Start-Process -Wait` de PowerShell no termina, porque espera también a la app que queda abierta. Usa
  `-PassThru` y espera el proceso del instalador por su cuenta.

## Desinstalar

Desde *Configuración → Aplicaciones*. Detiene y quita el servicio y las reglas del firewall.

Se conservan los datos para una reinstalación:

- `config.json`, `users.json`, `audit.log`
- `data.json`, `ledger.json`, `backup.json`
- la carpeta `backups\`

Si se borra `users.json` en un servidor instalado, nadie puede entrar (nunca vuelve a usuarios de demostración).
Vuelve a ejecutar el instalador para crear el administrador.

## Android

La misma app de Flutter compila para Android: `flutter build apk --release`. Siempre trabaja como cliente:

1. La primera vez busca servidores en la Wi-Fi.
2. Si no encuentra ninguno, se escribe la dirección.

La dirección se recuerda en el equipo.

## Prueba sin red (Windows Sandbox)

Con la característica *Windows Sandbox* activada, abre `installer\test-offline.wsb`. Arranca un Windows limpio
sin red y lanza el instalador. Elige `both`: se espera que instale el servidor y la app, y que la app se conecte
al servidor local. La prueba final marcará RMApiV2 como inaccesible, porque dentro del sandbox no hay API.
