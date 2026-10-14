; Instalador fuera de línea de Piqueo FIFO Centeno (Inno Setup 6).
; Compilar con installer\build_installer.ps1 (pasa /DAppVersion=... desde pubspec.yaml).
;
; Instalación silenciosa:
;   PiqueoFIFO-Setup-x.y.z.exe /VERYSILENT /API=http://servidor:8180 /LOG=C:\ruta\setup.log
; Primera instalación en un PC (aún no hay users.json): además /ADMINNAME="Nombre" /ADMINPIN=1234.
; Código de salida 100 = instalado, pero el autodiagnóstico falló (ver selftest.log).

#define AppName "Piqueo FIFO Centeno"
#define AppPublisher "Retail Manager"
#define AppExe "piqueo_fifo_centeno.exe"
#define BuildDir "..\build\windows\x64\runner\Release"
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
DefaultDirName={autopf}\Retail Manager\Piqueo FIFO
DefaultGroupName=Retail Manager
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=PiqueoFIFO-Setup-{#AppVersion}
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

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"
Name: "startup"; Description: "Abrir {#AppName} al iniciar sesión en Windows"; GroupDescription: "Inicio automático:"

[Dirs]
; Carpeta compartida (configuración, usuarios y PIN, auditoría): los empleados con cuentas
; estándar de Windows deben poder guardar cambios de usuarios.
Name: "{commonappdata}\RetailManager\PiqueoFIFO"; Permissions: users-modify

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Runtime de Visual C++ empaquetado: se extrae y ejecuta desde el código solo si falta.
Source: "redist\VC_redist.x64.exe"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{commonstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startup

[Run]
; Se abre también en instalaciones silenciosas, para dejar la app corriendo.
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall runasoriginaluser

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "CerrarApp"

[UninstallDelete]
; Se conservan config.json, users.json (usuarios y PIN) y audit.log para una reinstalación.
Type: files; Name: "{commonappdata}\RetailManager\PiqueoFIFO\selftest.log"

[Code]
const
  DefaultApi = 'http://localhost:8180';

var
  ApiPage: TInputQueryWizardPage;
  AdminPage: TInputQueryWizardPage;
  TestButton: TNewButton;
  TestLabel: TNewStaticText;
  SelfTestText: String;
  SelfTestPassed: Boolean;

function ConfigDir: String;
begin
  Result := ExpandConstant('{commonappdata}\RetailManager\PiqueoFIFO');
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

{ Llama a HealthCheck con WinHTTP (incluido en Windows, no requiere internet). }
function CheckApi(Url: String; var Msg: String): Boolean;
var
  Req: Variant;
begin
  Result := False;
  if not LooksLikeUrl(Url) then
  begin
    Msg := 'La dirección debe comenzar con http:// o https://';
    Exit;
  end;
  try
    Req := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Req.SetTimeouts(5000, 5000, 5000, 10000);
    Req.Open('GET', NormalizeApi(Url) + '/HealthCheck', False);
    Req.Send('');
    if Req.Status = 200 then
    begin
      Result := True;
      Msg := 'Conexión OK con RMApiV2.';
    end
    else if Req.Status = 503 then
      Msg := 'La API responde, pero no alcanza su base de datos (HTTP 503).'
    else
      Msg := 'HealthCheck respondió HTTP ' + IntToStr(Req.Status) + '.';
  except
    Msg := 'No se pudo conectar: ' + GetExceptionMessage;
  end;
end;

{ Lee apiUrl de un config.json existente (instalación previa). }
function PreviousApi: String;
var
  S: AnsiString;
  P: Integer;
  Txt: String;
begin
  Result := '';
  if not LoadStringFromFile(ConfigDir + '\config.json', S) then Exit;
  Txt := String(S);
  P := Pos('"apiUrl"', Txt);
  if P = 0 then Exit;
  Delete(Txt, 1, P + 7);
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

procedure InitializeWizard;
var
  Initial: String;
begin
  ApiPage := CreateInputQueryPage(wpSelectTasks,
    'Conexión con RMApiV2',
    'Dirección de la API de Retail Manager del almacén',
    'La aplicación importa los recibos desde RMApiV2. Si la API corre en esta misma PC, deja el valor por defecto.');
  ApiPage.Add('Dirección API (por ejemplo http://servidor:8180):', False);

  Initial := ExpandConstant('{param:API|}');
  if Initial = '' then Initial := PreviousApi;
  if Initial = '' then Initial := DefaultApi;
  ApiPage.Values[0] := Initial;

  TestButton := TNewButton.Create(ApiPage);
  TestButton.Parent := ApiPage.Surface;
  TestButton.Caption := 'Probar conexión';
  TestButton.Top := ApiPage.Edits[0].Top + ApiPage.Edits[0].Height + ScaleY(12);
  TestButton.Left := 0;
  TestButton.Width := ScaleX(140);
  TestButton.Height := ScaleY(26);
  TestButton.OnClick := @TestButtonClick;

  TestLabel := TNewStaticText.Create(ApiPage);
  TestLabel.Parent := ApiPage.Surface;
  TestLabel.Top := TestButton.Top + TestButton.Height + ScaleY(10);
  TestLabel.Left := 0;
  TestLabel.Width := ApiPage.SurfaceWidth;
  TestLabel.WordWrap := True;
  TestLabel.AutoSize := True;
  TestLabel.Caption := '';

  { Primer administrador: solo si este PC aún no tiene users.json. }
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
  Result := (AdminPage <> nil) and (PageID = AdminPage.ID) and FileExists(UsersFile);
end;

{ Instalación silenciosa en un PC nuevo: sin /ADMINPIN nadie podría entrar. }
function InitializeSetup: Boolean;
begin
  Result := True;
  if WizardSilent and not FileExists(UsersFile) and not IsPin(ExpandConstant('{param:ADMINPIN|}')) then
  begin
    Log('Falta /ADMINPIN=#### (4 dígitos) para crear el primer administrador.');
    SuppressibleMsgBox('Primera instalación en este PC: falta /ADMINPIN=#### (4 dígitos) para crear el administrador.',
      mbCriticalError, MB_OK, IDOK);
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
  end;
end;

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
  Json: String;
begin
  ForceDirectories(ConfigDir);
  Json := '{' + #13#10 + '  "apiUrl": "' + JsonEscape(Trim(ApiPage.Values[0])) + '"' + #13#10 + '}' + #13#10;
  if SaveStringToFile(ConfigDir + '\config.json', Json, False) then
    Log('Configuración escrita en ' + ConfigDir + '\config.json')
  else
    Log('No se pudo escribir config.json');
end;

procedure RunSelfTest;
var
  Code: Integer;
  S: AnsiString;
  LogFile: String;
begin
  WizardForm.StatusLabel.Caption := 'Verificando la instalación (autodiagnóstico)...';
  LogFile := ConfigDir + '\selftest.log';
  DeleteFile(LogFile);
  SelfTestPassed := Exec(ExpandConstant('{app}\{#AppExe}'), '--selftest', ExpandConstant('{app}'), SW_HIDE,
    ewWaitUntilTerminated, Code) and (Code = 0);
  if LoadStringFromFile(LogFile, S) then
    SelfTestText := String(S)
  else
    SelfTestText := 'No se generó selftest.log (código ' + IntToStr(Code) + ').';
  Log('Autodiagnóstico: ' + #13#10 + SelfTestText);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    InstallVCRedist;
    WriteConfig;
    WriteUsersFile;
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
        'Revisa la dirección API en Administración → Tiendas o vuelve a ejecutar el instalador.';
    WizardForm.FinishedLabel.AutoSize := True;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if SelfTestPassed then Result := 0 else Result := 100;
end;
