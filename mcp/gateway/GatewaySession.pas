unit GatewaySession;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, GatewayConfig, GatewayLog, McpStdioProcess;

type
  TGatewaySession = class
  private
    FId: string;
    FProcess: TStdioMcpProcess;
    FRefLock: TCriticalSection;
    FRefCount: Integer;
    FClosing: Boolean;
    FLastAccessTick: QWord;
    FProtocolVersion: string;
  public
    constructor Create(AConfig: TGatewayConfig; ALogger: TGatewayLogger;
      const AId: string);
    destructor Destroy; override;
    procedure Start;
    function TryAcquire: Boolean;
    procedure Release;
    procedure Touch;
    procedure MarkClosing;
    function CanDestroy: Boolean;
    function IsExpired(ANowTick, ATimeoutMs: QWord): Boolean;
    function SendRequest(const AJsonLine, AIdKey: string; ATimeoutMs: QWord;
      out AResponse, AError: string): Boolean;
    function SendMessage(const AJsonLine: string; out AError: string): Boolean;
    function PollSse(const ALastEventId: string; ATimeoutMs: QWord;
      out ABody: string): Boolean;
    function IsRunning: Boolean;
    procedure SetProtocolVersion(const AValue: string);
    function ProtocolVersion: string;
    property Id: string read FId;
  end;

  TGatewaySessionManager = class;

  TSessionCleanupThread = class(TThread)
  private
    FManager: TGatewaySessionManager;
  protected
    procedure Execute; override;
  public
    constructor Create(AManager: TGatewaySessionManager);
  end;

  TGatewaySessionManager = class
  private
    FConfig: TGatewayConfig;
    FLogger: TGatewayLogger;
    FLock: TCriticalSection;
    FSessions: TStringList;
    FRetired: TList;
    FCleanupThread: TSessionCleanupThread;
    function GenerateSessionId: string;
    procedure MoveToRetiredLocked(AIndex: Integer; const AReason: string);
  public
    constructor Create(AConfig: TGatewayConfig; ALogger: TGatewayLogger);
    destructor Destroy; override;
    function CreateSession: TGatewaySession;
    function AcquireSession(const ASessionId: string): TGatewaySession;
    procedure ReleaseSession(ASession: TGatewaySession);
    function RetireSession(const ASessionId, AReason: string): Boolean;
    procedure CleanupExpired;
    procedure ReapRetired;
    function SessionCount: Integer;
  end;

implementation

constructor TGatewaySession.Create(AConfig: TGatewayConfig;
  ALogger: TGatewayLogger; const AId: string);
begin
  inherited Create;
  FId := AId;
  FProcess := TStdioMcpProcess.Create(AConfig, ALogger, Copy(AId, 1, 8));
  FRefLock := TCriticalSection.Create;
  FRefCount := 0;
  FClosing := False;
  FLastAccessTick := GetTickCount64;
  FProtocolVersion := '';
end;

destructor TGatewaySession.Destroy;
begin
  FProcess.Free;
  FRefLock.Free;
  inherited Destroy;
end;

procedure TGatewaySession.Start;
begin
  FProcess.Start;
  Touch;
end;

function TGatewaySession.TryAcquire: Boolean;
begin
  FRefLock.Acquire;
  try
    Result := not FClosing;
    if Result then
    begin
      Inc(FRefCount);
      FLastAccessTick := GetTickCount64;
    end;
  finally
    FRefLock.Release;
  end;
end;

procedure TGatewaySession.Release;
begin
  FRefLock.Acquire;
  try
    if FRefCount > 0 then
      Dec(FRefCount);
    FLastAccessTick := GetTickCount64;
  finally
    FRefLock.Release;
  end;
end;

procedure TGatewaySession.Touch;
begin
  FRefLock.Acquire;
  try
    FLastAccessTick := GetTickCount64;
  finally
    FRefLock.Release;
  end;
end;

procedure TGatewaySession.MarkClosing;
begin
  FRefLock.Acquire;
  try
    FClosing := True;
  finally
    FRefLock.Release;
  end;
end;

function TGatewaySession.CanDestroy: Boolean;
begin
  FRefLock.Acquire;
  try
    Result := FClosing and (FRefCount = 0);
  finally
    FRefLock.Release;
  end;
end;

function TGatewaySession.IsExpired(ANowTick, ATimeoutMs: QWord): Boolean;
var
  LastTick: QWord;
begin
  if ATimeoutMs = 0 then
    Exit(False);
  FRefLock.Acquire;
  try
    if FClosing or (FRefCount > 0) then
      Exit(False);
    LastTick := FLastAccessTick;
  finally
    FRefLock.Release;
  end;
  Result := (ANowTick >= LastTick) and ((ANowTick - LastTick) >= ATimeoutMs);
end;

function TGatewaySession.SendRequest(const AJsonLine, AIdKey: string;
  ATimeoutMs: QWord; out AResponse, AError: string): Boolean;
begin
  Touch;
  Result := FProcess.SendRequest(AJsonLine, AIdKey, ATimeoutMs,
    AResponse, AError);
  Touch;
end;

function TGatewaySession.SendMessage(const AJsonLine: string;
  out AError: string): Boolean;
begin
  Touch;
  Result := FProcess.SendMessage(AJsonLine, AError);
  Touch;
end;

function TGatewaySession.PollSse(const ALastEventId: string;
  ATimeoutMs: QWord; out ABody: string): Boolean;
begin
  Touch;
  Result := FProcess.PollSse(ALastEventId, ATimeoutMs, ABody);
  Touch;
end;

function TGatewaySession.IsRunning: Boolean;
begin
  Result := FProcess.IsRunning;
end;

procedure TGatewaySession.SetProtocolVersion(const AValue: string);
begin
  FRefLock.Acquire;
  try
    FProtocolVersion := Trim(AValue);
  finally
    FRefLock.Release;
  end;
end;

function TGatewaySession.ProtocolVersion: string;
begin
  FRefLock.Acquire;
  try
    Result := FProtocolVersion;
  finally
    FRefLock.Release;
  end;
end;

constructor TSessionCleanupThread.Create(AManager: TGatewaySessionManager);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FManager := AManager;
end;

procedure TSessionCleanupThread.Execute;
var
  I: Integer;
begin
  while not Terminated do
  begin
    for I := 1 to 10 do
    begin
      if Terminated then
        Exit;
      Sleep(100);
    end;
    FManager.CleanupExpired;
    FManager.ReapRetired;
  end;
end;

constructor TGatewaySessionManager.Create(AConfig: TGatewayConfig;
  ALogger: TGatewayLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FLock := TCriticalSection.Create;
  FSessions := TStringList.Create;
  FSessions.Sorted := True;
  FSessions.Duplicates := dupError;
  FRetired := TList.Create;
  FCleanupThread := TSessionCleanupThread.Create(Self);
  FCleanupThread.Start;
end;

destructor TGatewaySessionManager.Destroy;
var
  I: Integer;
  Session: TGatewaySession;
begin
  if FCleanupThread <> nil then
  begin
    FCleanupThread.Terminate;
    FCleanupThread.WaitFor;
    FreeAndNil(FCleanupThread);
  end;

  FLock.Acquire;
  try
    for I := 0 to FSessions.Count - 1 do
    begin
      Session := TGatewaySession(FSessions.Objects[I]);
      Session.MarkClosing;
      FRetired.Add(Session);
    end;
    FSessions.Clear;
  finally
    FLock.Release;
  end;

  { HTTP has already been stopped by the application before the manager is
    destroyed, so no new references can appear here. }
  for I := 0 to FRetired.Count - 1 do
    TObject(FRetired[I]).Free;
  FRetired.Clear;
  FRetired.Free;
  FSessions.Free;
  FLock.Free;
  inherited Destroy;
end;

function TGatewaySessionManager.GenerateSessionId: string;
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then
    raise Exception.Create('Sichere Session-ID konnte nicht erzeugt werden');
  Result := LowerCase(GUIDToString(Guid));
  if (Length(Result) >= 2) and (Result[1] = '{') then
  begin
    Delete(Result, 1, 1);
    Delete(Result, Length(Result), 1);
  end;
end;

function TGatewaySessionManager.CreateSession: TGatewaySession;
var
  SessionId: string;
begin
  repeat
    SessionId := GenerateSessionId;
    FLock.Acquire;
    try
      if FSessions.IndexOf(SessionId) < 0 then
        Break;
    finally
      FLock.Release;
    end;
  until False;

  Result := TGatewaySession.Create(FConfig, FLogger, SessionId);
  try
    Result.Start;
    if not Result.TryAcquire then
      raise Exception.Create('Neue Session konnte nicht reserviert werden');
    FLock.Acquire;
    try
      FSessions.AddObject(SessionId, Result);
    finally
      FLock.Release;
    end;
    FLogger.Info(Format('Session %s created (%d active)',
      [SessionId, SessionCount]));
  except
    Result.Free;
    raise;
  end;
end;

function TGatewaySessionManager.AcquireSession(
  const ASessionId: string): TGatewaySession;
var
  Index: Integer;
begin
  Result := nil;
  if Trim(ASessionId) = '' then
    Exit;
  FLock.Acquire;
  try
    Index := FSessions.IndexOf(ASessionId);
    if Index < 0 then
      Exit;
    Result := TGatewaySession(FSessions.Objects[Index]);
    if not Result.TryAcquire then
      Result := nil;
  finally
    FLock.Release;
  end;
end;

procedure TGatewaySessionManager.ReleaseSession(ASession: TGatewaySession);
begin
  if ASession = nil then
    Exit;
  ASession.Release;
  ReapRetired;
end;

procedure TGatewaySessionManager.MoveToRetiredLocked(AIndex: Integer;
  const AReason: string);
var
  Session: TGatewaySession;
begin
  Session := TGatewaySession(FSessions.Objects[AIndex]);
  FSessions.Delete(AIndex);
  Session.MarkClosing;
  FRetired.Add(Session);
  FLogger.Info(Format('Session %s retired: %s', [Session.Id, AReason]));
end;

function TGatewaySessionManager.RetireSession(const ASessionId,
  AReason: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  FLock.Acquire;
  try
    Index := FSessions.IndexOf(ASessionId);
    if Index >= 0 then
    begin
      MoveToRetiredLocked(Index, AReason);
      Result := True;
    end;
  finally
    FLock.Release;
  end;
  ReapRetired;
end;

procedure TGatewaySessionManager.CleanupExpired;
var
  I: Integer;
  NowTick: QWord;
  Session: TGatewaySession;
begin
  if FConfig.SessionTimeoutMs = 0 then
    Exit;
  NowTick := GetTickCount64;
  FLock.Acquire;
  try
    for I := FSessions.Count - 1 downto 0 do
    begin
      Session := TGatewaySession(FSessions.Objects[I]);
      if Session.IsExpired(NowTick, FConfig.SessionTimeoutMs) then
        MoveToRetiredLocked(I, 'idle timeout');
    end;
  finally
    FLock.Release;
  end;
end;

procedure TGatewaySessionManager.ReapRetired;
var
  I: Integer;
  Session: TGatewaySession;
  ToFree: TList;
begin
  ToFree := TList.Create;
  try
    FLock.Acquire;
    try
      for I := FRetired.Count - 1 downto 0 do
      begin
        Session := TGatewaySession(FRetired[I]);
        if Session.CanDestroy then
        begin
          FRetired.Delete(I);
          ToFree.Add(Session);
        end;
      end;
    finally
      FLock.Release;
    end;
    for I := 0 to ToFree.Count - 1 do
      TObject(ToFree[I]).Free;
  finally
    ToFree.Free;
  end;
end;

function TGatewaySessionManager.SessionCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FSessions.Count;
  finally
    FLock.Release;
  end;
end;

end.
