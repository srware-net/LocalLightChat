unit McpStdioProcess;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, SyncObjs, GatewayConfig, GatewayLog;

type
  EStdioMcpProcess = class(Exception);

  TPendingMcpCall = class
  private
    FEvent: TEvent;
    FLock: TCriticalSection;
    FResponse: string;
    FError: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Complete(const AResponse: string);
    procedure Fail(const AError: string);
    function WaitFor(AWaitMs: QWord; out AResponse, AError: string): Boolean;
  end;

  TQueuedMcpMessage = class
  public
    Sequence: QWord;
    Data: string;
  end;

  TStdioMcpProcess = class;

  TPipeReaderKind = (prkStdout, prkStderr);

  TPipeReaderThread = class(TThread)
  private
    FOwner: TStdioMcpProcess;
    FStream: TStream;
    FKind: TPipeReaderKind;
    FBuffer: RawByteString;
    procedure ConsumeBuffer(AFlush: Boolean);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TStdioMcpProcess; AStream: TStream;
      AKind: TPipeReaderKind);
  end;

  TStdioMcpProcess = class
  private
    FConfig: TGatewayConfig;
    FLogger: TGatewayLogger;
    FSessionLabel: string;
    FProcess: TProcess;
    FStdoutThread: TPipeReaderThread;
    FStderrThread: TPipeReaderThread;
    FWriteLock: TCriticalSection;
    FPendingLock: TCriticalSection;
    FPending: TStringList;
    FStateLock: TCriticalSection;
    FAlive: Boolean;
    FClosing: Boolean;
    FExitReason: string;
    FQueueLock: TCriticalSection;
    FQueueEvent: TEvent;
    FHistory: TList;
    FNextEventSequence: QWord;
    FDeliveryCursor: QWord;
    FSseLock: TCriticalSection;
    procedure ConfigureProcess;
    procedure LoadChildEnvironment;
    function JsonIdKeyFromMessage(const AJsonLine: string;
      out AIsResponse: Boolean): string;
    procedure DeliverResponse(const AIdKey, AJsonLine: string);
    procedure QueueUnsolicited(const AJsonLine: string);
    procedure SignalPendingFailure(const AReason: string);
    function WriteJsonLine(const AJsonLine: string; out AError: string): Boolean;
    function AliveState(out AReason: string): Boolean;
    procedure SetDead(const AReason: string);
    function BuildSseAfter(ACursor: QWord; out ABody: string;
      out ALastSequence: QWord): Boolean;
  public
    constructor Create(AConfig: TGatewayConfig; ALogger: TGatewayLogger;
      const ASessionLabel: string);
    destructor Destroy; override;
    procedure Start;
    procedure Close;
    function SendRequest(const AJsonLine, AIdKey: string; ATimeoutMs: QWord;
      out AResponse, AError: string): Boolean;
    function SendMessage(const AJsonLine: string; out AError: string): Boolean;
    function PollSse(const ALastEventId: string; ATimeoutMs: QWord;
      out ABody: string): Boolean;
    function IsRunning: Boolean;
    procedure HandlePipeLine(AKind: TPipeReaderKind; const ALine: string);
    procedure HandlePipeEnded(AKind: TPipeReaderKind);
    property ExitReason: string read FExitReason;
  end;

function JsonRpcIdKey(AIdJson: string): string;

implementation

uses
  fpjson, jsonparser
  {$IFDEF UNIX}
  , BaseUnix, Unix
  {$ENDIF};

const
  MAX_EVENT_HISTORY = 512;

function JsonRpcIdKey(AIdJson: string): string;
begin
  Result := Trim(AIdJson);
end;

function JsonQuote(const AValue: string): string;
var
  ValueData: TJSONString;
begin
  ValueData := TJSONString.Create(AValue);
  try
    Result := ValueData.AsJSON;
  finally
    ValueData.Free;
  end;
end;

constructor TPendingMcpCall.Create;
begin
  inherited Create;
  FEvent := TEvent.Create(nil, True, False, '');
  FLock := TCriticalSection.Create;
end;

destructor TPendingMcpCall.Destroy;
begin
  FLock.Free;
  FEvent.Free;
  inherited Destroy;
end;

procedure TPendingMcpCall.Complete(const AResponse: string);
begin
  FLock.Acquire;
  try
    FResponse := AResponse;
    FError := '';
  finally
    FLock.Release;
  end;
  FEvent.SetEvent;
end;

procedure TPendingMcpCall.Fail(const AError: string);
begin
  FLock.Acquire;
  try
    if FResponse = '' then
      FError := AError;
  finally
    FLock.Release;
  end;
  FEvent.SetEvent;
end;

function TPendingMcpCall.WaitFor(AWaitMs: QWord; out AResponse,
  AError: string): Boolean;
var
  WaitValue: Cardinal;
begin
  if AWaitMs > High(Cardinal) then
    WaitValue := High(Cardinal)
  else
    WaitValue := Cardinal(AWaitMs);
  Result := FEvent.WaitFor(WaitValue) = wrSignaled;
  FLock.Acquire;
  try
    AResponse := FResponse;
    AError := FError;
  finally
    FLock.Release;
  end;
  Result := Result and (AResponse <> '');
end;

constructor TPipeReaderThread.Create(AOwner: TStdioMcpProcess;
  AStream: TStream; AKind: TPipeReaderKind);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FStream := AStream;
  FKind := AKind;
  FBuffer := '';
end;

procedure TPipeReaderThread.ConsumeBuffer(AFlush: Boolean);
var
  P: SizeInt;
  Line: RawByteString;
begin
  repeat
    P := Pos(#10, FBuffer);
    if P = 0 then
      Break;
    Line := Copy(FBuffer, 1, P - 1);
    Delete(FBuffer, 1, P);
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);
    FOwner.HandlePipeLine(FKind, UTF8Decode(Line));
  until False;

  if AFlush and (FBuffer <> '') then
  begin
    Line := FBuffer;
    FBuffer := '';
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);
    FOwner.HandlePipeLine(FKind, UTF8Decode(Line));
  end;
end;

procedure TPipeReaderThread.Execute;
var
  Buf: array[0..8191] of Byte;
  Count, OldLength: LongInt;
begin
  try
    while not Terminated do
    begin
      Count := FStream.Read(Buf, SizeOf(Buf));
      if Count <= 0 then
        Break;
      OldLength := Length(FBuffer);
      SetLength(FBuffer, OldLength + Count);
      Move(Buf[0], FBuffer[OldLength + 1], Count);
      ConsumeBuffer(False);
    end;
    ConsumeBuffer(True);
  except
    on E: Exception do
      if not Terminated then
        FOwner.HandlePipeLine(prkStderr,
          'Gateway pipe reader error: ' + E.Message);
  end;
  FOwner.HandlePipeEnded(FKind);
end;

constructor TStdioMcpProcess.Create(AConfig: TGatewayConfig;
  ALogger: TGatewayLogger; const ASessionLabel: string);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FSessionLabel := ASessionLabel;
  FProcess := TProcess.Create(nil);
  FWriteLock := TCriticalSection.Create;
  FPendingLock := TCriticalSection.Create;
  FPending := TStringList.Create;
  FPending.Sorted := True;
  FPending.Duplicates := dupError;
  FStateLock := TCriticalSection.Create;
  FQueueLock := TCriticalSection.Create;
  FQueueEvent := TEvent.Create(nil, True, False, '');
  FHistory := TList.Create;
  FSseLock := TCriticalSection.Create;
  FNextEventSequence := 0;
  FDeliveryCursor := 0;
  FAlive := False;
  FClosing := False;
end;

destructor TStdioMcpProcess.Destroy;
var
  I: Integer;
begin
  Close;
  FSseLock.Free;
  FQueueLock.Acquire;
  try
    for I := 0 to FHistory.Count - 1 do
      TObject(FHistory[I]).Free;
    FHistory.Clear;
  finally
    FQueueLock.Release;
  end;
  FHistory.Free;
  FQueueEvent.Free;
  FQueueLock.Free;
  FStateLock.Free;
  FPending.Free;
  FPendingLock.Free;
  FWriteLock.Free;
  FProcess.Free;
  inherited Destroy;
end;

procedure TStdioMcpProcess.LoadChildEnvironment;
var
  I: Integer;
begin
  FProcess.Environment.Clear;
  for I := 1 to GetEnvironmentVariableCount do
    FProcess.Environment.Add(GetEnvironmentString(I));
  for I := 0 to FConfig.Environment.Count - 1 do
    FProcess.Environment.Values[FConfig.Environment.Names[I]] :=
      FConfig.Environment.ValueFromIndex[I];
end;

procedure TStdioMcpProcess.ConfigureProcess;
var
  I: Integer;
  ShellPath: string;
begin
  FProcess.Options := [poUsePipes];
  if FConfig.WorkingDirectory <> '' then
    FProcess.CurrentDirectory := ExpandFileName(FConfig.WorkingDirectory);
  LoadChildEnvironment;

  if FConfig.UsesShell then
  begin
    {$IFDEF WINDOWS}
    ShellPath := GetEnvironmentVariable('COMSPEC');
    if ShellPath = '' then
      ShellPath := 'cmd.exe';
    FProcess.Executable := ShellPath;
    FProcess.Parameters.Add('/S');
    FProcess.Parameters.Add('/C');
    FProcess.Parameters.Add(FConfig.StdioCommand);
    {$ELSE}
    ShellPath := '/bin/sh';
    FProcess.Executable := ShellPath;
    FProcess.Parameters.Add('-c');
    { exec prevents the shell from surviving as an unnecessary parent and
      makes termination reliable for the normal one-process MCP case. }
    FProcess.Parameters.Add('exec ' + FConfig.StdioCommand);
    {$ENDIF}
  end
  else
  begin
    FProcess.Executable := FConfig.Executable;
    for I := 0 to FConfig.Arguments.Count - 1 do
      FProcess.Parameters.Add(FConfig.Arguments[I]);
  end;
end;

procedure TStdioMcpProcess.Start;
begin
  ConfigureProcess;
  FLogger.Debug(Format('[%s] starting child: %s %s', [FSessionLabel,
    FProcess.Executable, FProcess.Parameters.Text]));
  try
    FProcess.Execute;
  except
    on E: Exception do
      raise EStdioMcpProcess.Create('MCP-Prozess konnte nicht gestartet werden: ' +
        E.Message);
  end;

  FStateLock.Acquire;
  try
    FAlive := True;
    FClosing := False;
    FExitReason := '';
  finally
    FStateLock.Release;
  end;

  FStdoutThread := TPipeReaderThread.Create(Self, FProcess.Output, prkStdout);
  FStderrThread := TPipeReaderThread.Create(Self, FProcess.Stderr, prkStderr);
  FStdoutThread.Start;
  FStderrThread.Start;
  FLogger.Info(Format('[%s] child started, pid=%d',
    [FSessionLabel, FProcess.ProcessID]));
end;

function TStdioMcpProcess.AliveState(out AReason: string): Boolean;
begin
  FStateLock.Acquire;
  try
    Result := FAlive and not FClosing;
    AReason := FExitReason;
  finally
    FStateLock.Release;
  end;
  if (not Result) and (AReason = '') then
    AReason := 'MCP-Prozess ist nicht aktiv';
end;

function TStdioMcpProcess.IsRunning: Boolean;
var
  Reason: string;
begin
  Result := AliveState(Reason);
end;

procedure TStdioMcpProcess.SetDead(const AReason: string);
var
  WasAlive: Boolean;
begin
  FStateLock.Acquire;
  try
    WasAlive := FAlive;
    FAlive := False;
    if FExitReason = '' then
      FExitReason := AReason;
  finally
    FStateLock.Release;
  end;
  if WasAlive then
  begin
    FLogger.Error(Format('[%s] %s', [FSessionLabel, AReason]));
    SignalPendingFailure(AReason);
    FQueueEvent.SetEvent;
  end;
end;

procedure TStdioMcpProcess.SignalPendingFailure(const AReason: string);
var
  I: Integer;
begin
  FPendingLock.Acquire;
  try
    for I := 0 to FPending.Count - 1 do
      TPendingMcpCall(FPending.Objects[I]).Fail(AReason);
  finally
    FPendingLock.Release;
  end;
end;

function TStdioMcpProcess.WriteJsonLine(const AJsonLine: string;
  out AError: string): Boolean;
var
  Payload: UTF8String;
  Reason: string;
begin
  Result := False;
  AError := '';
  if not AliveState(Reason) then
  begin
    AError := Reason;
    Exit;
  end;

  Payload := UTF8Encode(Trim(AJsonLine) + #10);
  FWriteLock.Acquire;
  try
    try
      if Length(Payload) > 0 then
        FProcess.Input.WriteBuffer(Payload[1], Length(Payload));
      Result := True;
    except
      on E: Exception do
      begin
        AError := 'Schreiben an MCP-Prozess fehlgeschlagen: ' + E.Message;
        SetDead(AError);
      end;
    end;
  finally
    FWriteLock.Release;
  end;
end;

function TStdioMcpProcess.SendRequest(const AJsonLine, AIdKey: string;
  ATimeoutMs: QWord; out AResponse, AError: string): Boolean;
var
  Pending: TPendingMcpCall;
  Index: Integer;
begin
  Result := False;
  AResponse := '';
  AError := '';
  Pending := TPendingMcpCall.Create;
  try
    FPendingLock.Acquire;
    try
      if FPending.IndexOf(AIdKey) >= 0 then
        raise EStdioMcpProcess.Create('JSON-RPC-ID ist bereits ausstehend: ' + AIdKey);
      FPending.AddObject(AIdKey, Pending);
    finally
      FPendingLock.Release;
    end;

    if not WriteJsonLine(AJsonLine, AError) then
      Exit;
    FLogger.Debug(Format('[%s] HTTP -> child: %s',
      [FSessionLabel, AJsonLine]));

    if not Pending.WaitFor(ATimeoutMs, AResponse, AError) then
    begin
      if AError = '' then
        AError := Format('Zeitüberschreitung nach %d ms', [ATimeoutMs]);
      Exit;
    end;
    Result := True;
  finally
    FPendingLock.Acquire;
    try
      Index := FPending.IndexOf(AIdKey);
      if (Index >= 0) and (FPending.Objects[Index] = Pending) then
        FPending.Delete(Index);
    finally
      FPendingLock.Release;
    end;
    Pending.Free;
  end;
end;

function TStdioMcpProcess.SendMessage(const AJsonLine: string;
  out AError: string): Boolean;
begin
  Result := WriteJsonLine(AJsonLine, AError);
  if Result then
    FLogger.Debug(Format('[%s] HTTP -> child: %s',
      [FSessionLabel, AJsonLine]));
end;

function TStdioMcpProcess.JsonIdKeyFromMessage(const AJsonLine: string;
  out AIsResponse: Boolean): string;
var
  Data, IdData: TJSONData;
  Obj: TJSONObject;
begin
  Result := '';
  AIsResponse := False;
  Data := nil;
  try
    Data := GetJSON(AJsonLine);
    if Data.JSONType <> jtObject then
      Exit;
    Obj := TJSONObject(Data);
    IdData := Obj.Find('id');
    AIsResponse := (IdData <> nil) and (Obj.Find('method') = nil) and
      ((Obj.Find('result') <> nil) or (Obj.Find('error') <> nil));
    if AIsResponse then
      Result := JsonRpcIdKey(IdData.AsJSON);
  finally
    Data.Free;
  end;
end;

procedure TStdioMcpProcess.DeliverResponse(const AIdKey,
  AJsonLine: string);
var
  Index: Integer;
  Pending: TPendingMcpCall;
begin
  Pending := nil;
  FPendingLock.Acquire;
  try
    Index := FPending.IndexOf(AIdKey);
    if Index >= 0 then
      Pending := TPendingMcpCall(FPending.Objects[Index]);
    if Pending <> nil then
      Pending.Complete(AJsonLine);
  finally
    FPendingLock.Release;
  end;
  if Pending = nil then
    QueueUnsolicited(AJsonLine);
end;

procedure TStdioMcpProcess.QueueUnsolicited(const AJsonLine: string);
var
  Item: TQueuedMcpMessage;
begin
  Item := TQueuedMcpMessage.Create;
  Item.Data := AJsonLine;
  FQueueLock.Acquire;
  try
    Inc(FNextEventSequence);
    Item.Sequence := FNextEventSequence;
    FHistory.Add(Item);
    while FHistory.Count > MAX_EVENT_HISTORY do
    begin
      TObject(FHistory[0]).Free;
      FHistory.Delete(0);
    end;
    FQueueEvent.SetEvent;
  finally
    FQueueLock.Release;
  end;
  FLogger.Debug(Format('[%s] child message queued for SSE: %s',
    [FSessionLabel, AJsonLine]));
end;

procedure TStdioMcpProcess.HandlePipeLine(AKind: TPipeReaderKind;
  const ALine: string);
var
  Line, IdKey: string;
  IsResponse: Boolean;
  Data: TJSONData;
begin
  Line := Trim(ALine);
  if Line = '' then
    Exit;
  if AKind = prkStderr then
  begin
    FLogger.Info(Format('[%s] child stderr: %s', [FSessionLabel, Line]));
    Exit;
  end;

  Data := nil;
  try
    try
      Data := GetJSON(Line);
    except
      on E: Exception do
      begin
        FLogger.Error(Format('[%s] child stdout is not JSON: %s',
          [FSessionLabel, Line]));
        Exit;
      end;
    end;
    if not (Data.JSONType in [jtObject, jtArray]) then
    begin
      FLogger.Error(Format('[%s] child stdout is not an MCP message: %s',
        [FSessionLabel, Line]));
      Exit;
    end;
  finally
    Data.Free;
  end;

  FLogger.Debug(Format('[%s] child -> HTTP: %s', [FSessionLabel, Line]));
  try
    IdKey := JsonIdKeyFromMessage(Line, IsResponse);
  except
    on E: Exception do
    begin
      FLogger.Error(Format('[%s] invalid child JSON-RPC message: %s',
        [FSessionLabel, E.Message]));
      Exit;
    end;
  end;
  if IsResponse and (IdKey <> '') then
    DeliverResponse(IdKey, Line)
  else
    QueueUnsolicited(Line);
end;

procedure TStdioMcpProcess.HandlePipeEnded(AKind: TPipeReaderKind);
var
  Description: string;
begin
  if AKind = prkStdout then
  begin
    Description := 'MCP-Prozess hat stdout geschlossen';
    if (FProcess <> nil) and not FProcess.Running then
      Description := Format('MCP-Prozess wurde beendet, Exitstatus %d',
        [FProcess.ExitStatus]);
    SetDead(Description);
  end
  else
    FLogger.Debug(Format('[%s] child stderr closed', [FSessionLabel]));
end;

function TStdioMcpProcess.BuildSseAfter(ACursor: QWord; out ABody: string;
  out ALastSequence: QWord): Boolean;
var
  I: Integer;
  Item: TQueuedMcpMessage;
  Builder: TStringBuilder;
begin
  Result := False;
  ABody := '';
  ALastSequence := ACursor;
  Builder := TStringBuilder.Create;
  try
    FQueueLock.Acquire;
    try
      for I := 0 to FHistory.Count - 1 do
      begin
        Item := TQueuedMcpMessage(FHistory[I]);
        if Item.Sequence <= ACursor then
          Continue;
        Builder.Append('id: ');
        Builder.Append(IntToStr(Int64(Item.Sequence)));
        Builder.Append(#10);
        Builder.Append('event: message');
        Builder.Append(#10);
        Builder.Append('data: ');
        Builder.Append(Item.Data);
        Builder.Append(#10#10);
        ALastSequence := Item.Sequence;
        Result := True;
      end;
      if Result then
      begin
        FDeliveryCursor := ALastSequence;
        if FDeliveryCursor >= FNextEventSequence then
          FQueueEvent.ResetEvent;
      end
      else
        FQueueEvent.ResetEvent;
    finally
      FQueueLock.Release;
    end;
    ABody := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TStdioMcpProcess.PollSse(const ALastEventId: string;
  ATimeoutMs: QWord; out ABody: string): Boolean;
var
  Cursor, LastSequence: QWord;
  WaitValue: Cardinal;
  Parsed: QWord;
  Reason: string;
begin
  Result := False;
  ABody := '';
  FSseLock.Acquire;
  try
    if (Trim(ALastEventId) <> '') and TryStrToQWord(Trim(ALastEventId), Parsed) then
      Cursor := Parsed
    else
    begin
      FQueueLock.Acquire;
      try
        Cursor := FDeliveryCursor;
      finally
        FQueueLock.Release;
      end;
    end;

    if BuildSseAfter(Cursor, ABody, LastSequence) then
      Exit(True);

    if ATimeoutMs > High(Cardinal) then
      WaitValue := High(Cardinal)
    else
      WaitValue := Cardinal(ATimeoutMs);
    FQueueEvent.WaitFor(WaitValue);

    if BuildSseAfter(Cursor, ABody, LastSequence) then
      Exit(True);

    if not AliveState(Reason) then
    begin
      ABody := 'event: gateway-error' + #10 +
        'data: {"jsonrpc":"2.0","method":"notifications/message","params":' +
        '{"level":"error","logger":"llc-mcp-gateway","data":' +
        JsonQuote(Reason) + '}}' + #10#10;
      Exit(True);
    end;

    { TFPHTTPServer closes this finite response. The retry field tells a
      compliant Streamable-HTTP client to reconnect and continue polling. }
    ABody := 'retry: 1000' + #10 + ': keepalive' + #10#10;
    Result := True;
  finally
    FSseLock.Release;
  end;
end;

procedure TStdioMcpProcess.Close;
var
  I: Integer;
  EndTick: QWord;
begin
  FStateLock.Acquire;
  try
    if FClosing then
      Exit;
    FClosing := True;
  finally
    FStateLock.Release;
  end;

  SignalPendingFailure('MCP-Session wird geschlossen');
  FQueueEvent.SetEvent;

  if (FProcess <> nil) and FProcess.Running then
  begin
    FLogger.Debug(Format('[%s] terminating child pid=%d',
      [FSessionLabel, FProcess.ProcessID]));
    try
      FProcess.Terminate(0);
    except
      on E: Exception do
        FLogger.Error(Format('[%s] child termination failed: %s',
          [FSessionLabel, E.Message]));
    end;
    EndTick := GetTickCount64 + 1500;
    while FProcess.Running and (GetTickCount64 < EndTick) do
      Sleep(20);
    {$IFDEF UNIX}
    if FProcess.Running then
    begin
      fpKill(FProcess.ProcessID, SIGKILL);
      EndTick := GetTickCount64 + 1000;
      while FProcess.Running and (GetTickCount64 < EndTick) do
        Sleep(20);
    end;
    {$ENDIF}
  end;

  if FStdoutThread <> nil then
  begin
    FStdoutThread.Terminate;
    FStdoutThread.WaitFor;
    FreeAndNil(FStdoutThread);
  end;
  if FStderrThread <> nil then
  begin
    FStderrThread.Terminate;
    FStderrThread.WaitFor;
    FreeAndNil(FStderrThread);
  end;

  FStateLock.Acquire;
  try
    FAlive := False;
    if FExitReason = '' then
      FExitReason := 'MCP-Session geschlossen';
  finally
    FStateLock.Release;
  end;

  FPendingLock.Acquire;
  try
    for I := 0 to FPending.Count - 1 do
      TPendingMcpCall(FPending.Objects[I]).Fail(FExitReason);
  finally
    FPendingLock.Release;
  end;
  FLogger.Info(Format('[%s] child closed', [FSessionLabel]));
end;

end.
