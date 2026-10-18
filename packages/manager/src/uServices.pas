unit uServices;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses Classes, SysUtils, Process;

type
  TLogEvent = procedure(const S: string) of object;

  TLocalServices = class
  private
    FRoot: string;
    FPHP, FNginx, FRAG, FMCP: TProcess;
    FNginxPID, FPHPPID: LongInt;
    FOnLog: TLogEvent;
    FStartedWithRAG, FStartedWithAgent: Boolean;
    procedure Log(const S: string);
    function Path(const Relative: string): string;
    function Binary(const Relative: string): string;
    function NginxPrefix: string;
    function StartProcess(const Exe, WorkDir: string; const Args: array of string;
      Wait: Boolean): TProcess;
    procedure StopProcess(var P: TProcess);
    procedure CheckAvailable(const WithRAG, WithAgent: Boolean);
    procedure StartPHP;
    procedure StartNginx;
    procedure StartRAG;
    procedure StartAgent;
    procedure StopNginx;
    procedure StopPHP;
    procedure StartCAUpdate;
    function ReadPID(const FileName: string): LongInt;
    function PIDAlive(PID: LongInt): Boolean;
    {$IFDEF UNIX}
    function GetUnixIdentity(const Flag: string): string;
    procedure WriteFPMConfig;
    {$ENDIF}
  public
    constructor Create(const PackageRoot: string);
    destructor Destroy; override;
    procedure Start(const WithRAG, WithAgent: Boolean);
    procedure Stop;
    procedure Restart(const WithRAG, WithAgent: Boolean);
    function PHPAlive: Boolean;
    function NginxAlive: Boolean;
    function RAGAlive: Boolean;
    function MCPAlive: Boolean;
    function NetworkAccessEnabled: Boolean;
    procedure SetNetworkAccessEnabled(EnableLAN: Boolean);
    property Root: string read FRoot;
    property StartedWithRAG: Boolean read FStartedWithRAG;
    property StartedWithAgent: Boolean read FStartedWithAgent;
    property OnLog: TLogEvent read FOnLog write FOnLog;
  end;

implementation

{$IFDEF WINDOWS}
uses Windows, uPrerequisites, uNetworkConfig;
{$ELSE}
uses BaseUnix, uNetworkConfig;
{$ENDIF}

constructor TLocalServices.Create(const PackageRoot: string);
begin
  inherited Create;
  FRoot := IncludeTrailingPathDelimiter(ExpandFileName(PackageRoot));
end;

destructor TLocalServices.Destroy;
begin
  // Call Stop explicitly on normal Quit; do not kill services just because a GUI object is freed.
  FreeAndNil(FPHP);
  FreeAndNil(FNginx);
  FreeAndNil(FRAG);
  FreeAndNil(FMCP);
  inherited Destroy;
end;

procedure TLocalServices.Log(const S: string);
begin
  if Assigned(FOnLog) then FOnLog(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
end;

function TLocalServices.Path(const Relative: string): string;
begin
  Result := ExpandFileName(FRoot + Relative);
end;

function TLocalServices.Binary(const Relative: string): string;
begin
  {$IFDEF WINDOWS}
  Result := Path(Relative + '.exe');
  {$ELSE}
  Result := Path(Relative);
  {$ENDIF}
end;

function TLocalServices.NginxPrefix: string;
begin
  Result := IncludeTrailingPathDelimiter(Path('nginx'));
  {$IFDEF WINDOWS}
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
  {$ENDIF}
end;

function TLocalServices.StartProcess(const Exe, WorkDir: string;
  const Args: array of string; Wait: Boolean): TProcess;
var
  I: Integer;
begin
  Result := TProcess.Create(nil);
  try
    Result.Executable := Exe;
    Result.CurrentDirectory := WorkDir;
    for I := Low(Args) to High(Args) do Result.Parameters.Add(Args[I]);
    Result.Options := [poNoConsole];
    if Wait then Result.Options := Result.Options + [poWaitOnExit];
    Result.Execute;
    if Wait and (Result.ExitStatus <> 0) then
      raise Exception.CreateFmt('%s: exit code %d', [ExtractFileName(Exe), Result.ExitStatus]);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

procedure TLocalServices.StopProcess(var P: TProcess);
begin
  if P = nil then Exit;
  try
    if P.Running then
    begin
      {$IFDEF UNIX}
      fpKill(P.ProcessID, SIGTERM);
      {$ELSE}
      P.Terminate(0);
      {$ENDIF}
    end;
  finally
    FreeAndNil(P);
  end;
end;

function TLocalServices.ReadPID(const FileName: string): LongInt;
var
  L: TStringList;
begin
  Result := 0;
  if not FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    if L.Count > 0 then Result := StrToIntDef(Trim(L[0]), 0);
  except
    Result := 0;
  end;
  L.Free;
end;

function TLocalServices.PIDAlive(PID: LongInt): Boolean;
{$IFDEF WINDOWS}
var
  H: THandle;
{$ENDIF}
begin
  Result := False;
  if PID <= 0 then Exit;
  {$IFDEF WINDOWS}
  H := OpenProcess(SYNCHRONIZE, False, DWORD(PID));
  if H = 0 then Exit;
  try
    Result := WaitForSingleObject(H, 0) = WAIT_TIMEOUT;
  finally
    CloseHandle(H);
  end;
  {$ELSE}
  Result := fpKill(PID, 0) = 0;
  {$ENDIF}
end;

function TLocalServices.PHPAlive: Boolean;
begin
  {$IFDEF WINDOWS}
  Result := (FPHP <> nil) and FPHP.Running;
  {$ELSE}
  Result := (FPHPPID > 0) and (ReadPID(Path('php/php-fpm.pid')) = FPHPPID)
     and PIDAlive(FPHPPID);
  {$ENDIF}
end;

function TLocalServices.NginxAlive: Boolean;
begin
  Result := ((FNginxPID > 0) and
    (ReadPID(Path('nginx/logs/nginx.pid')) = FNginxPID) and PIDAlive(FNginxPID))
    or ((FNginx <> nil) and FNginx.Running);
end;

function TLocalServices.RAGAlive: Boolean;
begin
  Result := (FRAG <> nil) and FRAG.Running;
end;

function TLocalServices.MCPAlive: Boolean;
begin
  Result := (FMCP <> nil) and FMCP.Running;
end;

function TLocalServices.NetworkAccessEnabled: Boolean;
begin
  Result := uNetworkConfig.GetNetworkAccess(Path('nginx/conf/nginx.conf'));
end;

procedure TLocalServices.SetNetworkAccessEnabled(EnableLAN: Boolean);
begin
  uNetworkConfig.SetNetworkAccess(Path('nginx/conf/nginx.conf'), EnableLAN);
  Log('nginx listener changed to ' + BoolToStr(EnableLAN, 'LAN', 'localhost') +
    ' (effective after service restart)');
end;

procedure TLocalServices.CheckAvailable(const WithRAG, WithAgent: Boolean);
var
  N: string;
begin
  N := Binary('nginx/nginx');
  if not FileExists(N) then raise Exception.Create('nginx missing: ' + N);
  {$IFDEF WINDOWS}
  N := Binary('php/php-cgi');
  {$ELSE}
  N := Binary('php/php-fpm');
  {$ENDIF}
  if not FileExists(N) then raise Exception.Create('PHP missing: ' + N);
  if not FileExists(Path('nginx/conf/nginx.conf')) then
    raise Exception.Create('nginx/conf/nginx.conf missing');
  if WithRAG then
  begin
    N := Binary('rag/ragd');
    if not FileExists(N) then raise Exception.Create('RAG missing: ' + N);
  end;
  if WithAgent then
  begin
    N := Binary('mcp/server/mcp_server');
    if not FileExists(N) then raise Exception.Create('Agent missing: ' + N);
  end;
end;

{$IFDEF UNIX}
function TLocalServices.GetUnixIdentity(const Flag: string): string;
var
  P: TProcess;
  Buf: array[0..511] of Byte;
  Count: LongInt;
begin
  Result := '';
  P := TProcess.Create(nil);
  try
    P.Executable := '/usr/bin/id';
    P.Parameters.Add(Flag);
    P.Options := [poWaitOnExit, poUsePipes];
    P.Execute;
    if P.ExitStatus <> 0 then raise Exception.Create('id ' + Flag + ' failed');
    Count := P.Output.Read(Buf, SizeOf(Buf));
    if Count > 0 then SetString(Result, PAnsiChar(@Buf[0]), Count);
    Result := Trim(Result);
  finally
    P.Free;
  end;
  if Result = '' then raise Exception.Create('Could not determine user/group name');
end;

procedure TLocalServices.WriteFPMConfig;
var
  L: TStringList;
begin
  ForceDirectories(Path('php/logs'));
  L := TStringList.Create;
  try
    L.Add('[global]');
    L.Add('pid = ' + Path('php/php-fpm.pid'));
    L.Add('error_log = ' + Path('php/logs/error.log'));
    L.Add('daemonize = yes');
    L.Add('');
    L.Add('[www]');
    L.Add('user = ' + GetUnixIdentity('-un'));
    L.Add('group = ' + GetUnixIdentity('-gn'));
    L.Add('listen = 127.0.0.1:9002');
    L.Add('pm = dynamic');
    L.Add('pm.max_children = 15');
    L.Add('pm.start_servers = 2');
    L.Add('pm.min_spare_servers = 1');
    L.Add('pm.max_spare_servers = 3');
    L.Add('catch_workers_output = yes');
    L.Add('request_terminate_timeout = 999s');
    L.Add('php_admin_value[memory_limit] = 1024M');
    L.Add('php_admin_value[max_execution_time] = 999');
    L.Add('php_admin_value[max_input_time] = 999');
    L.Add('php_admin_value[post_max_size] = 200M');
    L.Add('php_admin_value[upload_max_filesize] = 200M');
    L.Add('php_admin_value[max_file_uploads] = 20');
    L.Add('php_admin_value[default_socket_timeout] = 999');
    L.Add('env[PATH] = /usr/local/bin:/usr/bin:/bin');
    L.SaveToFile(Path('php/php-fpm.conf'));
  finally
    L.Free;
  end;
end;
{$ENDIF}

procedure TLocalServices.StartPHP;
var
  P: TProcess;
  {$IFDEF UNIX}I: Integer;{$ENDIF}
begin
  {$IFDEF WINDOWS}
  P := StartProcess(Binary('php/php-cgi'), Path('php'),
      ['-b', '127.0.0.1:9002'], False);
  FPHP := P;
  {$ELSE}
  WriteFPMConfig;
  P := StartProcess(Binary('php/php-fpm'), Path('php'),
      ['-y', Path('php/php-fpm.conf'), '--prefix', Path('php')], True);
  P.Free;
  for I := 1 to 15 do
  begin
    FPHPPID := ReadPID(Path('php/php-fpm.pid'));
    if PIDAlive(FPHPPID) then Break;
    Sleep(100);
  end;
  if not PIDAlive(FPHPPID) then
    raise Exception.Create('php-fpm did not create a valid PID file');
  {$ENDIF}
  Log('PHP started');
end;

procedure TLocalServices.StartNginx;
var
  I: Integer;
begin
  ForceDirectories(Path('nginx/logs'));
  FNginx := StartProcess(Binary('nginx/nginx'), Path('nginx'),
    ['-p', NginxPrefix,
     '-c', 'conf/nginx.conf'], False);
  // nginx usually daemonizes on Linux; on Windows it can remain our child.
  // A PID in the package log directory is required to manage its shutdown.
  for I := 1 to 20 do
  begin
    FNginxPID := ReadPID(Path('nginx/logs/nginx.pid'));
    if PIDAlive(FNginxPID) then Break;
    Sleep(100);
  end;
  if not PIDAlive(FNginxPID) then
    raise Exception.Create('nginx failed to start (no live master PID)');
  Log('nginx started (PID: ' + IntToStr(FNginxPID) + ')');
end;

procedure TLocalServices.StartRAG;
begin
  FRAG := StartProcess(Binary('rag/ragd'), Path('rag'), [], False);
  Log('RAG started');
end;

procedure TLocalServices.StartAgent;
begin
  FMCP := StartProcess(Binary('mcp/server/mcp_server'), Path('mcp/server'), [], False);
  Log('Agent started');
end;

procedure TLocalServices.StartCAUpdate;
{$IFDEF WINDOWS}
var
  P: TProcess;
  Script: string;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  Script := Path('tools/update_cacert.ps1');
  if not FileExists(Script) then
  begin
    Log('Notice: CA updater not found');
    Exit;
  end;
  try
    P := StartProcess('powershell.exe', FRoot,
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
       '-File', Script, '-Root', FRoot], False);
    // Detached child continues independently; releasing TProcess doesn't kill it.
    P.Free;
    Log('CA update started in background');
  except
    on E: Exception do Log('Could not start CA update: ' + E.Message);
  end;
  {$ENDIF}
end;

procedure TLocalServices.Start(const WithRAG, WithAgent: Boolean);
{$IFDEF WINDOWS}
var
  P: TProcess;
{$ENDIF}
var
  Existing: LongInt;
begin
  if PHPAlive or NginxAlive or RAGAlive or MCPAlive then
    raise Exception.Create('Services were already started by this manager');
  CheckAvailable(WithRAG, WithAgent);
  {$IFDEF WINDOWS}
  EnsureVCRuntime(FRoot);
  {$ENDIF}
  // No global kill. Refuse to overwrite a service already using our package PID file.
  Existing := ReadPID(Path('nginx/logs/nginx.pid'));
  if PIDAlive(Existing) then
    raise Exception.Create('nginx is already running from this package (PID ' + IntToStr(Existing) + ')');
  {$IFDEF UNIX}
  Existing := ReadPID(Path('php/php-fpm.pid'));
  if PIDAlive(Existing) then
    raise Exception.Create('php-fpm is already running from this package (PID ' + IntToStr(Existing) + ')');
  {$ENDIF}
  {$IFDEF WINDOWS}
  if FileExists(Binary('php/PatchPHPConfig')) then
  begin
    P := StartProcess(Binary('php/PatchPHPConfig'), Path('php'), [], True);
    P.Free;
    Log('PHP configuration updated');
  end
  else
    Log('Warning: PatchPHPConfig.exe missing');
  {$ENDIF}
  try
    StartPHP;
    StartNginx;
    if WithRAG then StartRAG;
    if WithAgent then StartAgent;
    FStartedWithRAG := WithRAG;
    FStartedWithAgent := WithAgent;
    StartCAUpdate;
  except
    Stop;
    raise;
  end;
end;

procedure TLocalServices.StopNginx;
var
  Current: LongInt;
  P: TProcess;
  I: Integer;
begin
  Current := ReadPID(Path('nginx/logs/nginx.pid'));
  if (FNginxPID > 0) and (Current = FNginxPID) and PIDAlive(Current) then
  begin
    try
      P := StartProcess(Binary('nginx/nginx'), Path('nginx'),
        ['-p', NginxPrefix,
         '-c', 'conf/nginx.conf', '-s', 'quit'], True);
      P.Free;
      Log('nginx: graceful quit sent to owned PID');
      for I := 1 to 15 do
      begin
        if not PIDAlive(Current) then Break;
        Sleep(100);
      end;
    except
      on E: Exception do Log('nginx quit: ' + E.Message);
    end;
  end;
  // A stale/different PID must never be killed. If nginx itself is still
  // our direct child we can terminate just that process.
  if (FNginx <> nil) and FNginx.Running then StopProcess(FNginx)
  else FreeAndNil(FNginx);
  FNginxPID := 0;
end;

procedure TLocalServices.StopPHP;
begin
  {$IFDEF WINDOWS}
  StopProcess(FPHP);
  {$ELSE}
  if (FPHPPID > 0) and (ReadPID(Path('php/php-fpm.pid')) = FPHPPID)
    and PIDAlive(FPHPPID) then fpKill(FPHPPID, SIGQUIT);
  if FPHPPID > 0 then Sleep(300);
  FPHPPID := 0;
  {$ENDIF}
  Log('PHP stop requested');
end;

procedure TLocalServices.Stop;
begin
  StopProcess(FMCP);
  StopProcess(FRAG);
  StopNginx;
  StopPHP;
  FStartedWithRAG := False;
  FStartedWithAgent := False;
  Log('Stop requested (owned services only)');
end;

procedure TLocalServices.Restart(const WithRAG, WithAgent: Boolean);
begin
  Stop;
  Sleep(400);
  Start(WithRAG, WithAgent);
end;

end.
