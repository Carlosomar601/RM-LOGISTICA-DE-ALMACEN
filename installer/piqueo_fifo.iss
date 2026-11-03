; Instalador fuera de línea de Retail Manager Logistics & Warehouse (Inno Setup 6).
; Compilar con installer\build_installer.ps1 (pasa /DAppVersion=... desde pubspec.yaml).
;
; Tres tipos de instalación (página «Tipo de instalación» o /TYPE=):
;   both    Servidor y aplicación en este PC (PC principal o un solo PC). Opción por defecto.
;   server  Solo el servidor (servicio de Windows con la base de datos del almacén).
;   client  Solo la aplicación, conectada al servidor de otro PC.
;
; Instalación silenciosa:
;   Servidor:  RMLogistics-Setup-x.y.z.exe /VERYSILENT /TYPE=both /API=http://servidor:8180 /LOG=C:\ruta\setup.log
;              Primera vez en el servidor (aún no hay users.json): además /ADMINNAME="Nombre" /ADMINPIN=1234.
;   Cliente:   RMLogistics-Setup-x.y.z.exe /VERYSILENT /TYPE=client /SERVER=192.168.1.20
; Código de salida 100 = instalado, pero el autodiagnóstico falló (ver selftest.log / selftest-cliente.log).

#define AppName "Retail Manager Logistics & Warehouse"
; Igual, para textos de casillas (en Inno "&" marca la tecla de acceso; "&&" es un "&").
#define AppNameUI "Retail Manager Logistics && Warehouse"
#define AppPublisher "Retail Manager"
#define AppExe "piqueo_fifo_centeno.exe"
#define BuildDir "..\build\windows\x64\runner\Release"
#define ServerBuildDir "..\build\server"
#define ServiceId "RMLogisticsServer"
#define ServerPort "8190"
#define DiscoveryPort "8191"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8F3C2A51-6B7E-4D2A-9C1F-5E4B3A2D1C0F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Retail Manager\Logistics & Warehouse
DefaultGroupName=Retail Manager
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=RMLogistics-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=force
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Types]
Name: "both"; Description: "Servidor y aplicación en este PC (PC principal o un solo PC)"
Name: "server"; Description: "Solo servidor (base de datos del almacén, sin la aplicación)"
Name: "client"; Description: "Solo aplicación, conectada al servidor de otro PC"

[Components]
Name: "server"; Description: "Servidor RM Logistics: base de datos del almacén (servicio de Windows, puerto {#ServerPort})"; Types: both server; Flags: fixed
Name: "client"; Description: "Aplicación {#AppNameUI}"; Types: both client; Flags: fixed

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Components: client
Name: "startup"; Description: "Abrir {#AppNameUI} al iniciar sesión en Windows"; GroupDescription: "Inicio automático:"; Components: client

[Dirs]
; Carpeta compartida (configuración, datos del servidor, registros).
Name: "{commonappdata}\RetailManager\PiqueoFIFO"; Permissions: users-modify

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: client
Source: "{#ServerBuildDir}\rm_server.exe"; DestDir: "{app}\server"; Flags: ignoreversion; Components: server
; WinSW: convierte rm_server.exe en un servicio de Windows (se renombra con el ID del servicio).
Source: "redist\WinSW-x64.exe"; DestDir: "{app}\server"; DestName: "{#ServiceId}.exe"; Flags: ignoreversion; Components: server
Source: "service\{#ServiceId}.xml"; DestDir: "{app}\server"; Flags: ignoreversion; Components: server
; Runtime de Visual C++ empaquetado (lo necesita la aplicación): se ejecuta desde el código solo si falta.
Source: "redist\VC_redist.x64.exe"; Flags: dontcopy

[InstallDelete]
; Accesos con el nombre anterior de la app (Piqueo FIFO Centeno).
Type: files; Name: "{autoprograms}\Piqueo FIFO Centeno.lnk"
Type: files; Name: "{autodesktop}\Piqueo FIFO Centeno.lnk"
Type: files; Name: "{commonstartup}\Piqueo FIFO Centeno.lnk"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Components: client
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon; Components: client
Name: "{commonstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startup; Components: client

[Run]
; Se abre también en instalaciones silenciosas, para dejar la app corriendo.
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppNameUI}"; Flags: nowait postinstall runasoriginaluser; Components: client

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "CerrarApp"
Filename: "{app}\server\{#ServiceId}.exe"; Parameters: "stop"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "DetenerServicio"
Filename: "{app}\server\{#ServiceId}.exe"; Parameters: "uninstall"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "QuitarServicio"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""RM Logistics Server"""; Flags: runhidden; RunOnceId: "QuitarFirewall"

[UninstallDelete]
; Se conservan config.json, users.json (usuarios y PIN), audit.log, data.json (datos del almacén),
; ledger.json, backup.json y la carpeta backups\ para una reinstalación.
Type: files; Name: "{commonappdata}\RetailManager\PiqueoFIFO\selftest.log"
Type: files; Name: "{commonappdata}\RetailManager\PiqueoFIFO\selftest-cliente.log"

[Code]
const
  DefaultApi = 'http://localhost:8180';

var
  ApiPage: TInputQueryWizardPage;
  AdminPage: TInputQueryWizardPage;
  ServerPage: TInputQueryWizardPage;
  TestButton: TNewButton;
  TestLabel: TNewStaticText;
  ServerTestButton: TNewButton;
  ServerTestLabel: TNewStaticText;
  SelfTestText: String;
  SelfTestPassed: Boolean;

function ConfigDir: String;
begin
  Result := ExpandConstant('{commonappdata}\RetailManager\PiqueoFIFO');
end;

function WithServer: Boolean;
begin
  Result := WizardIsComponentSelected('server');
end;

function WithClient: Boolean;
begin
  Result := WizardIsComponentSelected('client');
end;

{ Solo aplicación: se conecta al servidor de otro PC. }
function ClientOnly: Boolean;
begin
  Result := WithClient and not WithServer;
end;

function InstallMode: String;
begin
  if WithServer and WithClient then Result := 'both'
  else if WithServer then Result := 'server'
  else Result := 'client';
end;

{ Agrega /cse.api.v1 si el usuario solo escribió host:puerto. }
function NormalizeApi(Url: String): String;
begin
  Result := Trim(Url);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
  if Pos('/cse.api.v1', Lowercase(Result)) = 0 then
    Result := Result + '/cse.api.v1';
end;

function LooksLikeUrl(Url: String): Boolean;
var
  U: String;
begin
  U := Lowercase(Trim(Url));
  Result := ((Pos('http://', U) = 1) and (Length(U) > 7)) or ((Pos('https://', U) = 1) and (Length(U) > 8));
end;

{ "192.168.1.20", "http://srv:8190/" → "192.168.1.20:8190", "srv:8190". }
function NormalizeServer(S: String): String;
var
  P: Integer;
begin
  Result := Trim(S);
  if Pos('http://', Lowercase(Result)) = 1 then Delete(Result, 1, 7);
  if Pos('https://', Lowercase(Result)) = 1 then Delete(Result, 1, 8);
  if Pos('ws://', Lowercase(Result)) = 1 then Delete(Result, 1, 5);
  P := Pos('/', Result);
  if P > 0 then Result := Copy(Result, 1, P - 1);
  if (Result <> '') and (Pos(':', Result) = 0) then Result := Result + ':{#ServerPort}';
end;

{ GET con WinHTTP (incluido en Windows, no requiere internet). }
function HttpGet(Url: String; var Status: Integer; var Body: String; var Msg: String): Boolean;
var
  Req: Variant;
begin
  Result := False;
  try
    Req := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Req.SetTimeouts(5000, 5000, 5000, 10000);
    Req.Open('GET', Url, False);
    Req.Send('');
    Status := Req.Status;
    Body := Req.ResponseText;
    Result := True;
  except
    Msg := 'No se pudo conectar: ' + GetExceptionMessage;
  end;
end;

{ HealthCheck de RMApiV2. }
function CheckApi(Url: String; var Msg: String): Boolean;
var
  Status: Integer;
  Body: String;
begin
  Result := False;
  if not LooksLikeUrl(Url) then
  begin
    Msg := 'La dirección debe comenzar con http:// o https://';
    Exit;
  end;
  if not HttpGet(NormalizeApi(Url) + '/HealthCheck', Status, Body, Msg) then Exit;
  if Status = 200 then
  begin
    Result := True;
    Msg := 'Conexión OK con RMApiV2.';
  end
  else if Status = 503 then
    Msg := 'La API responde, pero no alcanza su base de datos (HTTP 503).'
  else
    Msg := 'HealthCheck respondió HTTP ' + IntToStr(Status) + '.';
end;

{ /health del servidor de RM Logistics. }
function CheckServer(Address: String; var Msg: String): Boolean;
var
  Status: Integer;
  Body, A: String;
begin
  Result := False;
  A := NormalizeServer(Address);
  if A = '' then
  begin
    Msg := 'Escribe el nombre o la dirección IP del PC servidor.';
    Exit;
  end;
  if not HttpGet('http://' + A + '/health', Status, Body, Msg) then
  begin
    Msg := Msg + #13#10 + 'Revisa que el servidor esté instalado y encendido, y que estén en la misma red.';
    Exit;
  end;
  if (Status = 200) and (Pos('"ok":true', Body) > 0) then
  begin
    Result := True;
    Msg := 'Conexión OK con el servidor ' + A + '.';
  end
  else
    Msg := 'En ' + A + ' respondió algo que no es el servidor de RM Logistics (HTTP ' + IntToStr(Status) + ').';
end;

{ Lee un valor de texto de un config.json existente (instalación previa). }
function PreviousValue(Key: String): String;
var
  S: AnsiString;
  P: Integer;
  Txt: String;
begin
  Result := '';
  if not LoadStringFromFile(ConfigDir + '\config.json', S) then Exit;
  Txt := String(S);
  P := Pos('"' + Key + '"', Txt);
  if P = 0 then Exit;
  Delete(Txt, 1, P + Length(Key) + 1);
  P := Pos('"', Txt);
  if P = 0 then Exit;
  Delete(Txt, 1, P);
  P := Pos('"', Txt);
  if P = 0 then Exit;
  Result := Copy(Txt, 1, P - 1);
end;

function JsonEscape(S: String): String;
begin
  Result := S;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '"', '\"', True);
end;

procedure TestButtonClick(Sender: TObject);
var
  Msg: String;
begin
  TestLabel.Caption := 'Probando...';
  WizardForm.Refresh;
  CheckApi(ApiPage.Values[0], Msg);
  TestLabel.Caption := Msg;
end;

procedure ServerTestButtonClick(Sender: TObject);
var
  Msg: String;
begin
  ServerTestLabel.Caption := 'Probando...';
  WizardForm.Refresh;
  CheckServer(ServerPage.Values[0], Msg);
  ServerTestLabel.Caption := Msg;
end;

procedure AddTestButton(Page: TInputQueryWizardPage; var Button: TNewButton; var Lbl: TNewStaticText; OnClick: TNotifyEvent);
begin
  Button := TNewButton.Create(Page);
  Button.Parent := Page.Surface;
  Button.Caption := 'Probar conexión';
  Button.Top := Page.Edits[0].Top + Page.Edits[0].Height + ScaleY(12);
  Button.Left := 0;
  Button.Width := ScaleX(140);
  Button.Height := ScaleY(26);
  Button.OnClick := OnClick;

  Lbl := TNewStaticText.Create(Page);
  Lbl.Parent := Page.Surface;
  Lbl.Top := Button.Top + Button.Height + ScaleY(10);
  Lbl.Left := 0;
  Lbl.Width := Page.SurfaceWidth;
  Lbl.WordWrap := True;
  Lbl.AutoSize := True;
  Lbl.Caption := '';
end;

procedure InitializeWizard;
var
  Initial: String;
begin
  { Servidor: dirección de RMApiV2 (el servidor sincroniza con RM). }
  ApiPage := CreateInputQueryPage(wpSelectTasks,
    'Conexión con RMApiV2',
    'Dirección de la API de Retail Manager del almacén',
    'El servidor importa recibos, órdenes y facturas desde RMApiV2. Si la API corre en esta misma PC, deja el valor por defecto.');
  ApiPage.Add('Dirección API (por ejemplo http://servidor:8180):', False);
  Initial := ExpandConstant('{param:API|}');
  if Initial = '' then Initial := PreviousValue('apiUrl');
  if Initial = '' then Initial := DefaultApi;
  ApiPage.Values[0] := Initial;
  AddTestButton(ApiPage, TestButton, TestLabel, @TestButtonClick);

  { Primer administrador: solo en el servidor y si aún no hay users.json. }
  AdminPage := CreateInputQueryPage(ApiPage.ID,
    'Administrador',
    'Primer usuario administrador',
    'Los empleados entran a la aplicación con un PIN de 4 dígitos. Crea el administrador; ' +
    'después podrá agregar a los demás en Administración → Usuarios.');
  AdminPage.Add('Nombre y apellido:', False);
  AdminPage.Add('PIN (4 dígitos):', True);
  AdminPage.Add('Confirmar PIN:', True);
  AdminPage.Values[0] := ExpandConstant('{param:ADMINNAME|Administrador}');
  { En silencioso Inno también pasa por esta página: se valida con los valores de la línea de comandos. }
  AdminPage.Values[1] := ExpandConstant('{param:ADMINPIN|}');
  AdminPage.Values[2] := ExpandConstant('{param:ADMINPIN|}');

  { Solo aplicación: dirección del servidor. }
  ServerPage := CreateInputQueryPage(AdminPage.ID,
    'Servidor',
    'Servidor de RM Logistics',
    'Esta PC trabaja conectada al servidor, donde está la base de datos del almacén. Escribe el nombre o la ' +
    'dirección IP del PC servidor. También se puede cambiar después desde la pantalla de PIN («Cambiar servidor»).');
  ServerPage.Add('Servidor (por ejemplo 192.168.1.20 o SERVIDOR):', False);
  Initial := ExpandConstant('{param:SERVER|}');
  if Initial = '' then Initial := PreviousValue('serverUrl');
  if Lowercase(Copy(Initial, 1, 9)) = 'localhost' then Initial := '';
  ServerPage.Values[0] := Initial;
  AddTestButton(ServerPage, ServerTestButton, ServerTestLabel, @ServerTestButtonClick);
end;

function UsersFile: String;
begin
  Result := ConfigDir + '\users.json';
end;

function IsPin(S: String): Boolean;
var
  I: Integer;
begin
  Result := Length(S) = 4;
  for I := 1 to Length(S) do
    if (S[I] < '0') or (S[I] > '9') then Result := False;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (ApiPage <> nil) and (PageID = ApiPage.ID) then Result := not WithServer
  else if (AdminPage <> nil) and (PageID = AdminPage.ID) then Result := (not WithServer) or FileExists(UsersFile)
  else if (ServerPage <> nil) and (PageID = ServerPage.ID) then Result := not ClientOnly;
end;

{ Instalación silenciosa: datos mínimos según el tipo. }
function InitializeSetup: Boolean;
var
  T: String;
begin
  Result := True;
  if not WizardSilent then Exit;
  T := Lowercase(ExpandConstant('{param:TYPE|both}'));
  if (T <> 'client') and not FileExists(UsersFile) and not IsPin(ExpandConstant('{param:ADMINPIN|}')) then
  begin
    Log('Falta /ADMINPIN=#### (4 dígitos) para crear el primer administrador del servidor.');
    SuppressibleMsgBox('Primera instalación del servidor en este PC: falta /ADMINPIN=#### (4 dígitos) para crear el administrador.',
      mbCriticalError, MB_OK, IDOK);
    Result := False;
  end
  else if (T = 'client') and (Trim(ExpandConstant('{param:SERVER|}')) = '') and (PreviousValue('serverUrl') = '') then
  begin
    Log('Falta /SERVER=<dirección del servidor> para instalar solo la aplicación.');
    SuppressibleMsgBox('Instalación de solo aplicación: falta /SERVER=<dirección del PC servidor>.', mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;

function AdminPin: String;
begin
  Result := AdminPage.Values[1];
end;

function RandomHex(Bytes: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Bytes do
    Result := Result + Lowercase(Format('%.2x', [Random(256)]));
end;

{ users.json con el primer administrador. El PIN se guarda como SHA-256(sal + PIN), igual que la app. }
procedure WriteUsersFile;
var
  Salt, Hash, Json, Name: String;
begin
  if FileExists(UsersFile) then
  begin
    Log('users.json ya existe: se conservan los usuarios.');
    Exit;
  end;
  Name := Trim(AdminPage.Values[0]);
  if Name = '' then Name := 'Administrador';
  Salt := RandomHex(16);
  Hash := GetSHA256OfString(AnsiString(Salt + AdminPin));
  Json := '{' + #13#10 +
    ' "version": 1,' + #13#10 +
    ' "users": [' + #13#10 +
    '  {"id": "u1", "name": "' + JsonEscape(Name) + '", "email": "", "role": "Administrador", "active": true,' + #13#10 +
    '   "perms": ["dashboard", "receiving", "orders", "picking", "transfers", "history", "users"],' + #13#10 +
    '   "pinSalt": "' + Salt + '", "pinHash": "' + Hash + '"}' + #13#10 +
    ' ],' + #13#10 +
    ' "autoLogoutMinutes": 10' + #13#10 +
    '}' + #13#10;
  ForceDirectories(ConfigDir);
  if SaveStringToFile(UsersFile, Json, False) then
    Log('users.json creado con el administrador ' + Name + ' (el PIN no se registra).')
  else
    Log('No se pudo escribir users.json');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Msg: String;
begin
  Result := True;
  if CurPageID = ApiPage.ID then
  begin
    if not LooksLikeUrl(ApiPage.Values[0]) then
    begin
      SuppressibleMsgBox('La dirección debe comenzar con http:// o https://', mbError, MB_OK, IDOK);
      Result := False;
      Exit;
    end;
    if not CheckApi(ApiPage.Values[0], Msg) then
    begin
      TestLabel.Caption := Msg;
      Result := SuppressibleMsgBox(Msg + #13#10#13#10 +
        'Puedes continuar e instalar de todos modos; la prueba final lo indicará. ¿Continuar?',
        mbConfirmation, MB_YESNO, IDYES) = IDYES;
    end;
  end
  else if CurPageID = AdminPage.ID then
  begin
    if Trim(AdminPage.Values[0]) = '' then
    begin
      SuppressibleMsgBox('Escribe el nombre del administrador.', mbError, MB_OK, IDOK);
      Result := False;
    end
    else if not IsPin(AdminPage.Values[1]) then
    begin
      SuppressibleMsgBox('El PIN debe tener exactamente 4 dígitos.', mbError, MB_OK, IDOK);
      Result := False;
    end
    else if AdminPage.Values[1] <> AdminPage.Values[2] then
    begin
      SuppressibleMsgBox('Los dos PIN no coinciden.', mbError, MB_OK, IDOK);
      Result := False;
    end;
  end
  else if CurPageID = ServerPage.ID then
  begin
    if NormalizeServer(ServerPage.Values[0]) = '' then
    begin
      SuppressibleMsgBox('Escribe el nombre o la dirección IP del PC servidor.', mbError, MB_OK, IDOK);
      Result := False;
      Exit;
    end;
    if not CheckServer(ServerPage.Values[0], Msg) then
    begin
      ServerTestLabel.Caption := Msg;
      Result := SuppressibleMsgBox(Msg + #13#10#13#10 +
        'Puedes continuar e instalar de todos modos; la aplicación se conectará cuando el servidor esté disponible. ¿Continuar?',
        mbConfirmation, MB_YESNO, IDYES) = IDYES;
    end;
  end;
end;

{ ---------- Servicio de Windows y firewall ---------- }

function ServiceExists: Boolean;
var
  Code: Integer;
begin
  { sc query devuelve 1060 si el servicio no existe. }
  Result := Exec(ExpandConstant('{sys}\sc.exe'), 'query {#ServiceId}', '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
end;

procedure StopService;
var
  Code, I: Integer;
begin
  if not ServiceExists then Exit;
  Log('Deteniendo el servicio {#ServiceId}...');
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop {#ServiceId}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  { Espera a que guarde y termine (WinSW le da hasta 20 s). }
  for I := 1 to 25 do
  begin
    Exec(ExpandConstant('{sys}\cmd.exe'), '/c sc query {#ServiceId} | find "STOPPED"', '', SW_HIDE, ewWaitUntilTerminated, Code);
    if Code = 0 then Break;
    Sleep(1000);
  end;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM rm_server.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

{ Antes de copiar: detener el servidor y cerrar la app (en una actualización desde 1.1 la app
  guardaba los datos ella misma: no puede quedar abierta junto al servidor). }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  Result := '';
  StopService;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

procedure InstallService;
var
  Code: Integer;
  Wrapper: String;
begin
  WizardForm.StatusLabel.Caption := 'Registrando el servicio RM Logistics Server...';
  Wrapper := ExpandConstant('{app}\server\{#ServiceId}.exe');
  if not ServiceExists then
  begin
    if Exec(Wrapper, 'install', ExpandConstant('{app}\server'), SW_HIDE, ewWaitUntilTerminated, Code) then
      Log('Servicio instalado (código ' + IntToStr(Code) + ')')
    else
      Log('No se pudo instalar el servicio: ' + SysErrorMessage(Code));
  end;
  { Firewall: solo la red local (TCP del servidor y UDP de la búsqueda automática). }
  Exec(ExpandConstant('{sys}\netsh.exe'), 'advfirewall firewall delete rule name="RM Logistics Server"', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\netsh.exe'),
    'advfirewall firewall add rule name="RM Logistics Server" dir=in action=allow protocol=TCP localport={#ServerPort} remoteip=localsubnet profile=any',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
  Log('Firewall TCP {#ServerPort}: código ' + IntToStr(Code));
  Exec(ExpandConstant('{sys}\netsh.exe'),
    'advfirewall firewall add rule name="RM Logistics Server" dir=in action=allow protocol=UDP localport={#DiscoveryPort} remoteip=localsubnet profile=any',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
  Log('Firewall UDP {#DiscoveryPort}: código ' + IntToStr(Code));
end;

procedure StartService;
var
  Code: Integer;
begin
  WizardForm.StatusLabel.Caption := 'Iniciando el servidor...';
  Exec(ExpandConstant('{sys}\sc.exe'), 'start {#ServiceId}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Log('sc start: código ' + IntToStr(Code));
end;

{ Espera a que el servidor conteste en este PC (hasta ~20 s). }
function WaitForServer(var Msg: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to 20 do
  begin
    if CheckServer('localhost:{#ServerPort}', Msg) then
    begin
      Result := True;
      Exit;
    end;
    Sleep(1000);
  end;
end;

{ La sincronización con RM ahora corre en el servidor: se trae la configuración que tenía este usuario. }
procedure MigrateSyncSettings;
var
  Old, New: String;
begin
  New := ConfigDir + '\settings.json';
  Old := ExpandConstant('{userappdata}\RetailManager\PiqueoFIFO\settings.json');
  if (not FileExists(New)) and FileExists(Old) then
  begin
    if CopyFile(Old, New, True) then Log('Configuración de sincronización copiada a ' + New);
  end;
end;

{ ---------- Runtime, configuración y autodiagnóstico ---------- }

function VCRedistNeeded: Boolean;
var
  Installed: Cardinal;
begin
  Result := not (RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed)
    and (Installed = 1));
end;

procedure InstallVCRedist;
var
  Code: Integer;
begin
  if not VCRedistNeeded then
  begin
    Log('Visual C++ Runtime ya instalado.');
    Exit;
  end;
  WizardForm.StatusLabel.Caption := 'Instalando Microsoft Visual C++ Runtime...';
  ExtractTemporaryFile('VC_redist.x64.exe');
  if Exec(ExpandConstant('{tmp}\VC_redist.x64.exe'), '/install /quiet /norestart', '', SW_HIDE,
    ewWaitUntilTerminated, Code) then
    Log('VC_redist terminó con código ' + IntToStr(Code))  { 0 OK, 3010 requiere reinicio, 1638 ya hay una versión más nueva }
  else
    Log('No se pudo ejecutar VC_redist: ' + SysErrorMessage(Code));
end;

procedure WriteConfig;
var
  Json, Api, Server: String;
begin
  ForceDirectories(ConfigDir);
  if WithServer then Api := Trim(ApiPage.Values[0]) else Api := PreviousValue('apiUrl');
  if ClientOnly then Server := NormalizeServer(ServerPage.Values[0])
  else if WithClient then Server := 'localhost:{#ServerPort}'
  else Server := '';
  Json := '{' + #13#10 +
    '  "apiUrl": "' + JsonEscape(Api) + '",' + #13#10 +
    '  "mode": "' + InstallMode + '",' + #13#10 +
    '  "serverUrl": "' + JsonEscape(Server) + '"' + #13#10 +
    '}' + #13#10;
  if SaveStringToFile(ConfigDir + '\config.json', Json, False) then
    Log('Configuración escrita en ' + ConfigDir + '\config.json (' + InstallMode + ')')
  else
    Log('No se pudo escribir config.json');
end;

{ Ejecuta un autodiagnóstico y agrega su resultado al texto de la última página. }
function RunCheck(Exe, Params, LogName, Title: String): Boolean;
var
  Code: Integer;
  S: AnsiString;
  LogFile: String;
begin
  LogFile := ConfigDir + '\' + LogName;
  DeleteFile(LogFile);
  Result := Exec(Exe, Params, ExtractFileDir(Exe), SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
  if LoadStringFromFile(LogFile, S) then
    SelfTestText := SelfTestText + '[' + Title + ']' + #13#10 + String(S) + #13#10
  else
    SelfTestText := SelfTestText + '[' + Title + ']' + #13#10 + 'No se generó ' + LogName + ' (código ' + IntToStr(Code) + ').' + #13#10;
end;

procedure RunSelfTest;
var
  Ok: Boolean;
  Msg: String;
begin
  WizardForm.StatusLabel.Caption := 'Verificando la instalación (autodiagnóstico)...';
  SelfTestText := '';
  Ok := True;
  if WithServer then
  begin
    Ok := RunCheck(ExpandConstant('{app}\server\rm_server.exe'), '--selftest', 'selftest.log', 'Servidor') and Ok;
    StartService;
    if WaitForServer(Msg) then
      SelfTestText := SelfTestText + 'OK   Servicio RM Logistics Server: escuchando en el puerto {#ServerPort}' + #13#10#13#10
    else
    begin
      Ok := False;
      SelfTestText := SelfTestText + 'FAIL Servicio RM Logistics Server: ' + Msg + #13#10 +
        '     Revisa C:\ProgramData\RetailManager\PiqueoFIFO\server.log' + #13#10#13#10;
    end;
  end;
  if WithClient then
    Ok := RunCheck(ExpandConstant('{app}\{#AppExe}'), '--selftest', 'selftest-cliente.log', 'Aplicación') and Ok;
  SelfTestPassed := Ok;
  Log('Autodiagnóstico: ' + #13#10 + SelfTestText);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WithClient then InstallVCRedist;
    WriteConfig;
    if WithServer then
    begin
      WriteUsersFile;
      MigrateSyncSettings;
      InstallService;
    end;
    RunSelfTest;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    if SelfTestPassed then
      WizardForm.FinishedLabel.Caption :=
        '{#AppName} quedó instalado y la prueba final pasó.' + #13#10#13#10 + SelfTestText
    else
      WizardForm.FinishedLabel.Caption :=
        '{#AppName} quedó instalado, pero la prueba final encontró problemas:' + #13#10#13#10 + SelfTestText + #13#10 +
        'Revisa la dirección API (servidor) o la dirección del servidor (cliente) y vuelve a ejecutar el instalador.';
    WizardForm.FinishedLabel.AutoSize := True;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if SelfTestPassed then Result := 0 else Result := 100;
end;
