unit TerminalRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, ServerLog, TerminalPtyBackend,
  TerminalTranscript, TerminalScreen, TerminalVTParser, TerminalObservation,
  TerminalKeyEncoder;

type
  TTerminalSessionInfo = record
    SessionId: string;
    ProcessId: Integer;
    Running: Boolean;
    Closing: Boolean;
    Closed: Boolean;
    ExitCode: Integer;
    Columns: Word;
    Rows: Word;
    BufferStartSeq: QWord;
    OutputEndSeq: QWord;
    ReadCursorSeq: QWord;
    OutputDropped: Boolean;
    ErrorMessage: string;
    ScreenMode: string;
    ScreenVersion: QWord;
    ScrollbackStartSeq: QWord;
    ScrollbackNextSeq: QWord;
    ApplicationCursorKeys: Boolean;
  end;

  TTerminalKeyWriteResult = record
    BytesWritten: Integer;
    Encoding: TTerminalKeyEncoding;
    ApplicationCursorKeys: Boolean;
  end;

  TTerminalReadResult = record
    Info: TTerminalSessionInfo;
    FromSeq: QWord;
    NextSeq: QWord;
    OutputEndSeq: QWord;
    OutputText: UTF8String;
    MoreAvailable: Boolean;
    MissedOutput: Boolean;
    WaitTimedOut: Boolean;
  end;

  TTerminalObserveResult = record
    Info: TTerminalSessionInfo;
    OutputText: UTF8String;
    Changed: Boolean;
    Quiet: Boolean;
    WaitTimedOut: Boolean;
    AlternateScreen: Boolean;
    RawBytesProcessed: QWord;
    RawBytesSinceLast: QWord;
    ScrollbackFromSeq: QWord;
    ScrollbackNextSeq: QWord;
    ScrollbackMissed: Boolean;
    RenderedBytes: Cardinal;
    OmittedBytes: Cardinal;
    ScreenVersion: QWord;
  end;

  TTerminalSession = class;

  TTerminalWorker = class(TThread)
  private
    FSession: TTerminalSession;
  protected
    procedure Execute; override;
  public
    constructor Create(ASession: TTerminalSession);
    function StopRequested: Boolean;
  end;

  TTerminalSession = class
  private
    FLock: TRTLCriticalSection;
    FControlLock: TRTLCriticalSection;
    FReadLock: TRTLCriticalSection;
    FObserveLock: TRTLCriticalSection;
    FSessionId: string;
    FBackend: TTerminalPtyBackend;
    FTranscript: TTerminalTranscript;
    FScreen: TTerminalScreen;
    FVTParser: TTerminalVTParser;
    FObservation: TTerminalObservationState;
    FWorker: TTerminalWorker;
    FWorkerStarted: Boolean;
    FRunning: Boolean;
    FClosing: Boolean;
    FClosed: Boolean;
    FBackendClosed: Boolean;
    FExitCode: Integer;
    FColumns: Word;
    FRows: Word;
    FMaximumOutputBytes: Cardinal;
    FOutputBuffer: RawByteString;
    FBufferStartSeq: QWord;
    FOutputEndSeq: QWord;
    FReadCursorSeq: QWord;
    FOutputDropped: Boolean;
    FErrorMessage: string;
    FLastOutputTick: QWord;
    FWorkerFinished: Boolean;
    FReferenceCount: Integer;
    FRemoved: Boolean;
    procedure AppendOutputLocked(const AChunk: RawByteString);
    function SnapshotLocked: TTerminalSessionInfo;
    procedure WorkerExecute;
    function ReadFrom(AAfterSeq: QWord; AWaitMs,
      AMaximumBytes: Cardinal): TTerminalReadResult;
    function WriteInternal(const AData: RawByteString; ASensitive: Boolean;
      const AKeyDescription: string): Integer;
  public
    constructor Create(const ASessionId: string;
      ABackend: TTerminalPtyBackend; ATranscript: TTerminalTranscript;
      AColumns, ARows: Word; AMaximumOutputBytes,
      AMaximumScrollbackLines: Cardinal);
    destructor Destroy; override;
    function Snapshot: TTerminalSessionInfo;
    function Read(AAfterSeq: QWord; AWaitMs,
      AMaximumBytes: Cardinal): TTerminalReadResult;
    function ReadNext(AWaitMs, AMaximumBytes: Cardinal): TTerminalReadResult;
    function Observe(AWaitMs, AQuietMs, AMaximumBytes: Cardinal): TTerminalObserveResult;
    function Write(const AData: RawByteString;
      ASensitive: Boolean): Integer;
    function WriteKey(const AKey: string; ACtrl, AAlt, AShift: Boolean):
      TTerminalKeyWriteResult;
    procedure Resize(AColumns, ARows: Word);
    procedure Signal(ASignal: TTerminalSignal);
    procedure Close;
    function CanPrune: Boolean;
    procedure AddReference;
    function ReleaseReference: Boolean;
    function MarkRemoved: Boolean;
    property SessionId: string read FSessionId;
  end;

  TTerminalRunner = class
  private
    FLogger: TServerLogger;
    FMaximumSessions: Cardinal;
    FMaximumOutputBytes: Cardinal;
    FMaximumScrollbackLines: Cardinal;
    FTerminationGraceMs: Cardinal;
    FLogOutput: Boolean;
    FLogInput: Boolean;
    FMirrorOutputToConsole: Boolean;
    FMirrorInputToConsole: Boolean;
    FConsoleOutputMode: string;
    FSessions: TThreadList;
    function NormalizeSessionId(const ASessionId,
      ACorrelationId: string): string;
    function CreateBackend: TTerminalPtyBackend;
    procedure PruneCompletedSessions;
    function AcquireSession(const ASessionId: string): TTerminalSession;
    procedure ReleaseSession(ASession: TTerminalSession);
  public
    constructor Create(ALogger: TServerLogger; AMaximumSessions,
      AMaximumOutputBytes, AMaximumScrollbackLines, ATerminationGraceMs: Cardinal;
      ALogOutput, ALogInput, AMirrorOutputToConsole,
      AMirrorInputToConsole: Boolean; const AConsoleOutputMode: string);
    destructor Destroy; override;
    function Open(const AExecutable: string; AArguments: TJSONArray;
      const AWorkingDirectory, ASessionId, ACorrelationId: string;
      AColumns, ARows: Word): TTerminalSessionInfo;
    function Read(const ASessionId: string; AAfterSeq: QWord;
      AWaitMs, AMaximumBytes: Cardinal): TTerminalReadResult;
    function ReadNext(const ASessionId: string; AWaitMs,
      AMaximumBytes: Cardinal): TTerminalReadResult;
    function Observe(const ASessionId: string; AWaitMs, AQuietMs,
      AMaximumBytes: Cardinal): TTerminalObserveResult;
    function Write(const ASessionId: string;
      const AData: RawByteString; ASensitive: Boolean): Integer;
    function WriteKey(const ASessionId, AKey: string; ACtrl, AAlt,
      AShift: Boolean): TTerminalKeyWriteResult;
    function Resize(const ASessionId: string; AColumns,
      ARows: Word): TTerminalSessionInfo;
    function Signal(const ASessionId: string;
      ASignal: TTerminalSignal): TTerminalSessionInfo;
    function Close(const ASessionId: string): TTerminalSessionInfo;
    function Status(const ASessionId: string): TTerminalSessionInfo;
  end;

implementation

{$IFDEF WINDOWS}
uses
  TerminalPtyWindows;
{$ENDIF}
{$IFDEF LINUX}
uses
  TerminalPtyUnix;
{$ENDIF}

{ TTerminalWorker }

constructor TTerminalWorker.Create(ASession: TTerminalSession);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSession := ASession;
end;

procedure TTerminalWorker.Execute;
begin
  FSession.WorkerExecute;
end;

function TTerminalWorker.StopRequested: Boolean;
begin
  Result := Terminated;
end;

{ TTerminalSession }

constructor TTerminalSession.Create(const ASessionId: string;
  ABackend: TTerminalPtyBackend; ATranscript: TTerminalTranscript;
  AColumns, ARows: Word; AMaximumOutputBytes,
  AMaximumScrollbackLines: Cardinal);
begin
  inherited Create;
  { Constructor takes ownership of ABackend immediately. This makes failure
    cleanup unambiguous even if later initialization raises. }
  FBackend := ABackend;
  FTranscript := ATranscript;
  InitCriticalSection(FLock);
  InitCriticalSection(FControlLock);
  InitCriticalSection(FReadLock);
  InitCriticalSection(FObserveLock);
  FSessionId := ASessionId;
  FColumns := AColumns;
  FRows := ARows;
  FMaximumOutputBytes := AMaximumOutputBytes;
  FScreen := TTerminalScreen.Create(AColumns, ARows, AMaximumScrollbackLines);
  FVTParser := TTerminalVTParser.Create(FScreen);
  FObservation := TTerminalObservationState.Create;
  FLastOutputTick := GetTickCount64;
  FRunning := True;
  FClosing := False;
  FClosed := False;
  FBackendClosed := False;
  FExitCode := 0;
  FOutputBuffer := '';
  FBufferStartSeq := 0;
  FOutputEndSeq := 0;
  FReadCursorSeq := 0;
  FOutputDropped := False;
  FErrorMessage := '';
  FWorkerFinished := False;
  FReferenceCount := 0;
  FRemoved := False;
  FWorkerStarted := False;
  FWorker := TTerminalWorker.Create(Self);
  FWorker.Start;
  FWorkerStarted := True;
end;

destructor TTerminalSession.Destroy;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    Close;
    if FWorkerStarted then
      FWorker.WaitFor;
    FWorker.Free;
  end;
  FObservation.Free;
  FVTParser.Free;
  FScreen.Free;
  FBackend.Free;
  FTranscript.Free;
  DoneCriticalSection(FObserveLock);
  DoneCriticalSection(FReadLock);
  DoneCriticalSection(FControlLock);
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TTerminalSession.AppendOutputLocked(const AChunk: RawByteString);
var
  NewLength, DropCount: SizeInt;
begin
  if AChunk = '' then
    Exit;

  Inc(FOutputEndSeq, QWord(Length(AChunk)));
  FOutputBuffer := FOutputBuffer + AChunk;
  NewLength := Length(FOutputBuffer);
  if NewLength > SizeInt(FMaximumOutputBytes) then
  begin
    DropCount := NewLength - SizeInt(FMaximumOutputBytes);
    Delete(FOutputBuffer, 1, DropCount);
    Inc(FBufferStartSeq, QWord(DropCount));
    FOutputDropped := True;
  end;
end;

function TTerminalSession.SnapshotLocked: TTerminalSessionInfo;
begin
  Result.SessionId := FSessionId;
  Result.ProcessId := FBackend.ProcessId;
  Result.Running := FRunning;
  Result.Closing := FClosing;
  Result.Closed := FClosed;
  Result.ExitCode := FExitCode;
  Result.Columns := FColumns;
  Result.Rows := FRows;
  Result.BufferStartSeq := FBufferStartSeq;
  Result.OutputEndSeq := FOutputEndSeq;
  Result.ReadCursorSeq := FReadCursorSeq;
  Result.OutputDropped := FOutputDropped;
  Result.ErrorMessage := FErrorMessage;
  if FScreen <> nil then
  begin
    if FScreen.AlternateActive then
      Result.ScreenMode := 'alternate'
    else
      Result.ScreenMode := 'normal';
    Result.ScreenVersion := FScreen.Version;
    Result.ScrollbackStartSeq := FScreen.ScrollbackStartSeq;
    Result.ScrollbackNextSeq := FScreen.ScrollbackNextSeq;
    Result.ApplicationCursorKeys := FScreen.ApplicationCursorKeys;
  end
  else
  begin
    Result.ScreenMode := 'unknown';
    Result.ScreenVersion := 0;
    Result.ScrollbackStartSeq := 0;
    Result.ScrollbackNextSeq := 0;
    Result.ApplicationCursorKeys := False;
  end;
end;

function TTerminalSession.Snapshot: TTerminalSessionInfo;
begin
  EnterCriticalSection(FLock);
  try
    Result := SnapshotLocked;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TTerminalSession.WorkerExecute;
var
  Chunk: RawByteString;
  ReadCount: Integer;
  IsRunning, NeedCleanup, ClosingElsewhere: Boolean;

  procedure AppendChunk(const AChunk: RawByteString);
  begin
    if AChunk = '' then
      Exit;
    EnterCriticalSection(FLock);
    try
      AppendOutputLocked(AChunk);
      if FVTParser <> nil then
        FVTParser.Feed(AChunk);
      FLastOutputTick := GetTickCount64;
    finally
      LeaveCriticalSection(FLock);
    end;
    if FTranscript <> nil then
      FTranscript.OutputChunk(AChunk);
  end;

  procedure FinishBackendCleanup;
  var
    CleanupError: string;
  begin
    CleanupError := '';
    try
      FBackend.Close;
    except
      on E: Exception do
        CleanupError := E.Message;
    end;

    EnterCriticalSection(FLock);
    try
      FBackendClosed := True;
      FClosing := False;
      FClosed := True;
      FRunning := False;
      if FBackend.Exited then
        FExitCode := FBackend.ExitCode;
      if (CleanupError <> '') and (FErrorMessage = '') then
        FErrorMessage := CleanupError;
    finally
      LeaveCriticalSection(FLock);
    end;
  end;

begin
  try
    while not FWorker.StopRequested do
    begin
      EnterCriticalSection(FLock);
      try
        if FClosed then
          Break;
      finally
        LeaveCriticalSection(FLock);
      end;

      try
        ReadCount := FBackend.ReadAvailable(Chunk, 8192);
        if ReadCount > 0 then
          AppendChunk(Chunk);

        IsRunning := FBackend.PollRunning;
        if not IsRunning then
        begin
          { Drain everything already readable before closing the native PTY. }
          repeat
            ReadCount := FBackend.ReadAvailable(Chunk, 8192);
            if ReadCount > 0 then
              AppendChunk(Chunk);
          until ReadCount <= 0;

          NeedCleanup := False;
          ClosingElsewhere := False;
          EnterCriticalSection(FLock);
          try
            FRunning := False;
            FExitCode := FBackend.ExitCode;
            FClosed := True;
            if FClosing then
              ClosingElsewhere := True
            else if not FBackendClosed then
            begin
              FClosing := True;
              NeedCleanup := True;
            end;
          finally
            LeaveCriticalSection(FLock);
          end;

          if NeedCleanup then
          begin
            { Serialize teardown against write/resize/signal, but never serialize
              ordinary output reads against terminal_write. }
            EnterCriticalSection(FControlLock);
            try
              FinishBackendCleanup;
            finally
              LeaveCriticalSection(FControlLock);
            end;
          end;
          { If another thread owns close, it will wait for this worker to leave
            before releasing the backend handles. }
          if NeedCleanup or ClosingElsewhere then
            Break;
          Break;
        end;
      except
        on E: Exception do
        begin
          NeedCleanup := False;
          ClosingElsewhere := False;
          EnterCriticalSection(FLock);
          try
            FRunning := False;
            FClosed := True;
            if FClosing then
              ClosingElsewhere := True
            else if not FBackendClosed then
            begin
              FClosing := True;
              NeedCleanup := True;
              FErrorMessage := E.Message;
              if FExitCode = 0 then
                FExitCode := 1;
            end;
          finally
            LeaveCriticalSection(FLock);
          end;

          if NeedCleanup then
          begin
            EnterCriticalSection(FControlLock);
            try
              try
                FinishBackendCleanup;
              except
                { Keep the original terminal I/O error. }
              end;
            finally
              LeaveCriticalSection(FControlLock);
            end;
          end;
          Break;
        end;
      end;

      if ReadCount <= 0 then
        Sleep(10);
    end;
  finally
    EnterCriticalSection(FLock);
    try
      FWorkerFinished := True;
      if FBackend.Exited then
      begin
        FRunning := False;
        FExitCode := FBackend.ExitCode;
      end;
    finally
      LeaveCriticalSection(FLock);
    end;
  end;
end;

function TTerminalSession.ReadFrom(AAfterSeq: QWord; AWaitMs,
  AMaximumBytes: Cardinal): TTerminalReadResult;
var
  StartedAt: QWord;
  EffectiveSeq, Available, ReturnCount, Offset: QWord;
  ShouldReturn: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  StartedAt := GetTickCount64;

  repeat
    ShouldReturn := False;
    EnterCriticalSection(FLock);
    try
      ShouldReturn := (AAfterSeq <> FOutputEndSeq) or
        (not FRunning) or FClosed or (FErrorMessage <> '') or
        (AWaitMs = 0) or (GetTickCount64 - StartedAt >= AWaitMs);
      if ShouldReturn then
      begin
        Result.Info := SnapshotLocked;
        Result.MissedOutput := AAfterSeq < FBufferStartSeq;
        if Result.MissedOutput then
          EffectiveSeq := FBufferStartSeq
        else if AAfterSeq > FOutputEndSeq then
          EffectiveSeq := FOutputEndSeq
        else
          EffectiveSeq := AAfterSeq;

        Available := FOutputEndSeq - EffectiveSeq;
        ReturnCount := Available;
        if (AMaximumBytes > 0) and (ReturnCount > AMaximumBytes) then
          ReturnCount := AMaximumBytes;

        Result.FromSeq := EffectiveSeq;
        Result.NextSeq := EffectiveSeq + ReturnCount;
        Result.OutputEndSeq := FOutputEndSeq;
        Result.MoreAvailable := Result.NextSeq < FOutputEndSeq;
        Result.WaitTimedOut := (Available = 0) and FRunning and
          (AWaitMs > 0) and (GetTickCount64 - StartedAt >= AWaitMs);

        if ReturnCount > 0 then
        begin
          Offset := EffectiveSeq - FBufferStartSeq + 1;
          Result.OutputText := UTF8String(Copy(FOutputBuffer,
            SizeInt(Offset), SizeInt(ReturnCount)));
        end
        else
          Result.OutputText := '';
      end;
    finally
      LeaveCriticalSection(FLock);
    end;

    if ShouldReturn then
      Exit;
    Sleep(10);
  until False;
end;

function TTerminalSession.Read(AAfterSeq: QWord; AWaitMs,
  AMaximumBytes: Cardinal): TTerminalReadResult;
begin
  { Explicit after_seq is a replay/debug override, but it also becomes the
    session's new delivery cursor so subsequent ordinary reads continue from
    exactly where this call stopped. Serialize deliveries so concurrent MCP
    reads cannot return the same terminal bytes twice. }
  EnterCriticalSection(FReadLock);
  try
    Result := ReadFrom(AAfterSeq, AWaitMs, AMaximumBytes);
    EnterCriticalSection(FLock);
    try
      FReadCursorSeq := Result.NextSeq;
      Result.Info.ReadCursorSeq := FReadCursorSeq;
    finally
      LeaveCriticalSection(FLock);
    end;
  finally
    LeaveCriticalSection(FReadLock);
  end;
end;

function TTerminalSession.ReadNext(AWaitMs,
  AMaximumBytes: Cardinal): TTerminalReadResult;
var
  Cursor: QWord;
begin
  { Normal MCP reads are stateful: the server remembers the last delivered
    byte sequence. This keeps mechanical cursor bookkeeping out of the LLM
    context and also makes omitted after_seq safe. }
  EnterCriticalSection(FReadLock);
  try
    EnterCriticalSection(FLock);
    try
      Cursor := FReadCursorSeq;
    finally
      LeaveCriticalSection(FLock);
    end;

    Result := ReadFrom(Cursor, AWaitMs, AMaximumBytes);

    EnterCriticalSection(FLock);
    try
      FReadCursorSeq := Result.NextSeq;
      Result.Info.ReadCursorSeq := FReadCursorSeq;
    finally
      LeaveCriticalSection(FLock);
    end;
  finally
    LeaveCriticalSection(FReadLock);
  end;
end;

function TTerminalSession.Observe(AWaitMs, AQuietMs,
  AMaximumBytes: Cardinal): TTerminalObserveResult;
var
  StartedAt, NowTick: QWord;
  Changed, QuietNow, TimedOut, ShouldReturn: Boolean;
  Capture: TTerminalObservationCapture;
begin
  FillChar(Result, SizeOf(Result), 0);
  EnterCriticalSection(FObserveLock);
  try
    StartedAt := GetTickCount64;
    repeat
      ShouldReturn := False;
      EnterCriticalSection(FLock);
      try
        NowTick := GetTickCount64;
        Changed := (FObservation <> nil) and
          FObservation.HasVisibleChanges(FScreen);
        QuietNow := (AQuietMs = 0) or
          (NowTick - FLastOutputTick >= AQuietMs);
        TimedOut := (AWaitMs = 0) or (NowTick - StartedAt >= AWaitMs);
        ShouldReturn := (Changed and QuietNow) or (not FRunning) or FClosed or
          (FErrorMessage <> '') or TimedOut;

        if ShouldReturn then
        begin
          Capture := FObservation.Capture(FScreen, FOutputEndSeq,
            AMaximumBytes);
          Result.Info := SnapshotLocked;
          Result.OutputText := Capture.Text;
          Result.Changed := Capture.Changed;
          Result.Quiet := QuietNow;
          Result.WaitTimedOut := TimedOut and FRunning and not FClosed;
          Result.AlternateScreen := Capture.AlternateScreen;
          Result.RawBytesProcessed := Capture.RawBytesProcessed;
          Result.RawBytesSinceLast := Capture.RawBytesSinceLast;
          Result.ScrollbackFromSeq := Capture.ScrollbackFromSeq;
          Result.ScrollbackNextSeq := Capture.ScrollbackNextSeq;
          Result.ScrollbackMissed := Capture.ScrollbackMissed;
          Result.RenderedBytes := Capture.RenderedBytes;
          Result.OmittedBytes := Capture.OmittedBytes;
          Result.ScreenVersion := Capture.ScreenVersion;
        end;
      finally
        LeaveCriticalSection(FLock);
      end;

      if ShouldReturn then Exit;
      Sleep(10);
    until False;
  finally
    LeaveCriticalSection(FObserveLock);
  end;
end;

function TTerminalSession.WriteInternal(const AData: RawByteString;
  ASensitive: Boolean; const AKeyDescription: string): Integer;
var
  WrittenData: RawByteString;
begin
  { Control I/O has its own lock. The output worker intentionally does not use
    this lock, so it can keep draining a synchronous ConPTY while WriteFile is
    blocked waiting for output-side progress. }
  EnterCriticalSection(FControlLock);
  try
    EnterCriticalSection(FLock);
    try
      if FClosed or FClosing then
        raise Exception.Create('Terminal session is closing or closed');
      if not FRunning then
        raise Exception.Create('Terminal session is not running');
    finally
      LeaveCriticalSection(FLock);
    end;
    Result := FBackend.WriteData(AData);
  finally
    LeaveCriticalSection(FControlLock);
  end;

  if Result > 0 then
  begin
    WrittenData := Copy(AData, 1, Result);
    if FTranscript <> nil then
    begin
      if AKeyDescription <> '' then
        FTranscript.InputKey(AKeyDescription, Result)
      else
        FTranscript.InputChunk(WrittenData, ASensitive);
    end;
  end;
end;

function TTerminalSession.Write(const AData: RawByteString;
  ASensitive: Boolean): Integer;
begin
  Result := WriteInternal(AData, ASensitive, '');
end;

function TTerminalSession.WriteKey(const AKey: string; ACtrl, AAlt,
  AShift: Boolean): TTerminalKeyWriteResult;
var
  ApplicationCursorKeys: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    if FScreen <> nil then
      ApplicationCursorKeys := FScreen.ApplicationCursorKeys
    else
      ApplicationCursorKeys := False;
  finally
    LeaveCriticalSection(FLock);
  end;

  Result.Encoding := EncodeTerminalKey(AKey, ACtrl, AAlt, AShift,
    ApplicationCursorKeys);
  Result.ApplicationCursorKeys := ApplicationCursorKeys;
  Result.BytesWritten := WriteInternal(Result.Encoding.Bytes, False,
    Result.Encoding.DisplayName);
end;

procedure TTerminalSession.Resize(AColumns, ARows: Word);
begin
  EnterCriticalSection(FControlLock);
  try
    EnterCriticalSection(FLock);
    try
      if FClosed or FClosing then
        raise Exception.Create('Terminal session is closing or closed');
      if not FRunning then
        raise Exception.Create('Terminal session is not running');
    finally
      LeaveCriticalSection(FLock);
    end;

    FBackend.Resize(AColumns, ARows);
    EnterCriticalSection(FLock);
    try
      FColumns := AColumns;
      FRows := ARows;
      if FScreen <> nil then
        FScreen.Resize(AColumns, ARows);
    finally
      LeaveCriticalSection(FLock);
    end;
  finally
    LeaveCriticalSection(FControlLock);
  end;
end;

procedure TTerminalSession.Signal(ASignal: TTerminalSignal);
begin
  EnterCriticalSection(FControlLock);
  try
    EnterCriticalSection(FLock);
    try
      if FClosed or FClosing then
        raise Exception.Create('Terminal session is closing or closed');
      if not FRunning then
        raise Exception.Create('Terminal session is not running');
    finally
      LeaveCriticalSection(FLock);
    end;
    FBackend.SendSignal(ASignal);
  finally
    LeaveCriticalSection(FControlLock);
  end;

  { kill is defined as forced teardown, not merely delivery of a signal. }
  if ASignal = tsKill then
    Close;
end;

procedure TTerminalSession.Close;
var
  OwnClose, Done: Boolean;
begin
  repeat
    OwnClose := False;
    Done := False;

    { A concurrent control operation is allowed to finish while the output
      worker keeps draining. Once this lock is held, no new write/resize/signal
      can race native teardown. }
    EnterCriticalSection(FControlLock);
    EnterCriticalSection(FLock);
    try
      if FBackendClosed then
      begin
        FClosed := True;
        FRunning := False;
        Done := True;
      end
      else if FClosing then
      begin
        { The worker claimed cleanup after natural exit. Do not steal it while
          holding the control lock; release and let it finish. }
      end
      else
      begin
        FClosing := True;
        FClosed := True;
        OwnClose := True;
      end;
    finally
      LeaveCriticalSection(FLock);
    end;

    if Done then
    begin
      LeaveCriticalSection(FControlLock);
      Exit;
    end;

    if not OwnClose then
    begin
      LeaveCriticalSection(FControlLock);
      Sleep(5);
      Continue;
    end;

    try
      { FClosed makes the output worker leave. It does not need FControlLock,
        so waiting here cannot deadlock with terminal output draining. }
      if (FWorker <> nil) and FWorkerStarted then
        FWorker.WaitFor;

      try
        FBackend.Close;
      except
        on E: Exception do
        begin
          EnterCriticalSection(FLock);
          try
            if FErrorMessage = '' then
              FErrorMessage := E.Message;
          finally
            LeaveCriticalSection(FLock);
          end;
        end;
      end;
      EnterCriticalSection(FLock);
      try
        FBackendClosed := True;
        FClosing := False;
        FClosed := True;
        FRunning := False;
        if FBackend.Exited then
          FExitCode := FBackend.ExitCode;
      finally
        LeaveCriticalSection(FLock);
      end;
    finally
      LeaveCriticalSection(FControlLock);
    end;
    Exit;
  until False;
end;

function TTerminalSession.CanPrune: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := (FClosed or not FRunning) and FWorkerFinished;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TTerminalSession.AddReference;
begin
  EnterCriticalSection(FLock);
  try
    Inc(FReferenceCount);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TTerminalSession.ReleaseReference: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    if FReferenceCount > 0 then
      Dec(FReferenceCount);
    Result := FRemoved and (FReferenceCount = 0);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TTerminalSession.MarkRemoved: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    FRemoved := True;
    Result := FReferenceCount = 0;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{ TTerminalRunner }

constructor TTerminalRunner.Create(ALogger: TServerLogger;
  AMaximumSessions, AMaximumOutputBytes, AMaximumScrollbackLines,
  ATerminationGraceMs: Cardinal; ALogOutput, ALogInput,
  AMirrorOutputToConsole, AMirrorInputToConsole: Boolean;
  const AConsoleOutputMode: string);
begin
  inherited Create;
  FLogger := ALogger;
  if AMaximumSessions < 1 then
    FMaximumSessions := 1
  else
    FMaximumSessions := AMaximumSessions;
  if AMaximumOutputBytes < 4096 then
    FMaximumOutputBytes := 4096
  else
    FMaximumOutputBytes := AMaximumOutputBytes;
  FMaximumScrollbackLines := AMaximumScrollbackLines;
  FTerminationGraceMs := ATerminationGraceMs;
  FLogOutput := ALogOutput;
  FLogInput := ALogInput;
  FMirrorOutputToConsole := AMirrorOutputToConsole;
  FMirrorInputToConsole := AMirrorInputToConsole;
  FConsoleOutputMode := LowerCase(Trim(AConsoleOutputMode));
  if (FConsoleOutputMode <> 'raw') and
    (FConsoleOutputMode <> 'prefixed') then
    FConsoleOutputMode := 'prefixed';
  FSessions := TThreadList.Create;
end;

destructor TTerminalRunner.Destroy;
var
  List: TList;
  I: Integer;
  Session: TTerminalSession;
begin
  List := FSessions.LockList;
  try
    for I := 0 to List.Count - 1 do
    begin
      Session := TTerminalSession(List[I]);
      Session.Close;
    end;
    for I := 0 to List.Count - 1 do
      TTerminalSession(List[I]).Free;
    List.Clear;
  finally
    FSessions.UnlockList;
  end;
  FSessions.Free;
  inherited Destroy;
end;

function TTerminalRunner.NormalizeSessionId(const ASessionId,
  ACorrelationId: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := Trim(ASessionId);
  if Result = '' then
  begin
    if Trim(ACorrelationId) <> '' then
      Result := ACorrelationId + '-term'
    else
      Result := 'term-' + IntToHex(GetTickCount64, 16);
  end;
  if Length(Result) > 128 then
    raise Exception.Create('session_id must not exceed 128 characters');
  for I := 1 to Length(Result) do
  begin
    C := Result[I];
    if not (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ':']) then
      raise Exception.Create('session_id contains an invalid character');
  end;
end;

function TTerminalRunner.CreateBackend: TTerminalPtyBackend;
begin
  {$IFDEF WINDOWS}
  Result := TWindowsTerminalPtyBackend.Create(FTerminationGraceMs);
  {$ELSE}
    {$IFDEF LINUX}
    Result := TUnixTerminalPtyBackend.Create(FTerminationGraceMs);
    {$ELSE}
    raise Exception.Create('Interactive PTY terminals are currently supported only on Windows and Linux');
    {$ENDIF}
  {$ENDIF}
end;

procedure TTerminalRunner.PruneCompletedSessions;
var
  List, Removed: TList;
  I: Integer;
  Session: TTerminalSession;
begin
  Removed := TList.Create;
  try
    List := FSessions.LockList;
    try
      I := 0;
      while (List.Count >= Integer(FMaximumSessions)) and
        (I < List.Count) do
      begin
        Session := TTerminalSession(List[I]);
        if Session.CanPrune then
        begin
          List.Delete(I);
          if Session.MarkRemoved then
            Removed.Add(Session);
        end
        else
          Inc(I);
      end;
    finally
      FSessions.UnlockList;
    end;

    for I := 0 to Removed.Count - 1 do
      TObject(Removed[I]).Free;
  finally
    Removed.Free;
  end;
end;

function TTerminalRunner.AcquireSession(
  const ASessionId: string): TTerminalSession;
var
  List: TList;
  I: Integer;
  Session: TTerminalSession;
begin
  Result := nil;
  List := FSessions.LockList;
  try
    for I := 0 to List.Count - 1 do
    begin
      Session := TTerminalSession(List[I]);
      if SameText(Session.SessionId, Trim(ASessionId)) then
      begin
        Session.AddReference;
        Result := Session;
        Break;
      end;
    end;
  finally
    FSessions.UnlockList;
  end;
end;

procedure TTerminalRunner.ReleaseSession(ASession: TTerminalSession);
begin
  if (ASession <> nil) and ASession.ReleaseReference then
    ASession.Free;
end;

function TTerminalRunner.Open(const AExecutable: string;
  AArguments: TJSONArray; const AWorkingDirectory, ASessionId,
  ACorrelationId: string; AColumns, ARows: Word): TTerminalSessionInfo;
var
  NormalizedId: string;
  List: TList;
  I: Integer;
  Existing: TTerminalSession;
  Args: TStringList;
  Backend: TTerminalPtyBackend;
  Transcript: TTerminalTranscript;
  Session: TTerminalSession;
begin
  PruneCompletedSessions;
  NormalizedId := NormalizeSessionId(ASessionId, ACorrelationId);

  List := FSessions.LockList;
  try
    if List.Count >= Integer(FMaximumSessions) then
      raise Exception.Create('Maximum number of interactive terminal sessions reached');
    for I := 0 to List.Count - 1 do
    begin
      Existing := TTerminalSession(List[I]);
      if SameText(Existing.SessionId, NormalizedId) then
        raise Exception.Create('A terminal session already uses session_id ' +
          NormalizedId);
    end;
  finally
    FSessions.UnlockList;
  end;

  Args := TStringList.Create;
  Backend := nil;
  Transcript := nil;
  Session := nil;
  try
    if AArguments <> nil then
      for I := 0 to AArguments.Count - 1 do
      begin
        if AArguments.Items[I].JSONType <> jtString then
          raise Exception.Create('terminal_open arguments must contain only strings');
        Args.Add(AArguments.Items[I].AsString);
      end;

    Backend := CreateBackend;
    Backend.Start(AExecutable, Args, AWorkingDirectory, AColumns, ARows);
    Transcript := TTerminalTranscript.Create(FLogger, NormalizedId,
      ACorrelationId, FLogOutput, FLogInput, FMirrorOutputToConsole,
      FMirrorInputToConsole, FConsoleOutputMode);
    try
      Session := TTerminalSession.Create(NormalizedId, Backend, Transcript,
        AColumns, ARows, FMaximumOutputBytes, FMaximumScrollbackLines);
    except
      { TTerminalSession.Create takes ownership before any fallible setup. }
      Backend := nil;
      Transcript := nil;
      raise;
    end;
    Backend := nil;
    Transcript := nil;

    List := FSessions.LockList;
    try
      if List.Count >= Integer(FMaximumSessions) then
        raise Exception.Create('Maximum number of interactive terminal sessions reached');
      for I := 0 to List.Count - 1 do
        if SameText(TTerminalSession(List[I]).SessionId, NormalizedId) then
          raise Exception.Create('A terminal session already uses session_id ' +
            NormalizedId);
      List.Add(Session);
    finally
      FSessions.UnlockList;
    end;

    if FLogger <> nil then
      FLogger.Write(Format('%s terminal %s opened PID %d: %s',
        [ACorrelationId, NormalizedId, Session.Snapshot.ProcessId,
         AExecutable]));
    Result := Session.Snapshot;
    Session := nil;
  finally
    if Session <> nil then
      Session.Free;
    Transcript.Free;
    Backend.Free;
    Args.Free;
  end;
end;

function TTerminalRunner.Read(const ASessionId: string;
  AAfterSeq: QWord; AWaitMs, AMaximumBytes: Cardinal): TTerminalReadResult;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Result := Session.Read(AAfterSeq, AWaitMs, AMaximumBytes);
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.ReadNext(const ASessionId: string;
  AWaitMs, AMaximumBytes: Cardinal): TTerminalReadResult;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Result := Session.ReadNext(AWaitMs, AMaximumBytes);
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.Observe(const ASessionId: string;
  AWaitMs, AQuietMs, AMaximumBytes: Cardinal): TTerminalObserveResult;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Result := Session.Observe(AWaitMs, AQuietMs, AMaximumBytes);
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.Write(const ASessionId: string;
  const AData: RawByteString; ASensitive: Boolean): Integer;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Result := Session.Write(AData, ASensitive);
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.WriteKey(const ASessionId, AKey: string; ACtrl,
  AAlt, AShift: Boolean): TTerminalKeyWriteResult;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Result := Session.WriteKey(AKey, ACtrl, AAlt, AShift);
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.Resize(const ASessionId: string;
  AColumns, ARows: Word): TTerminalSessionInfo;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Session.Resize(AColumns, ARows);
    Result := Session.Snapshot;
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.Signal(const ASessionId: string;
  ASignal: TTerminalSignal): TTerminalSessionInfo;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Session.Signal(ASignal);
    Result := Session.Snapshot;
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.Close(
  const ASessionId: string): TTerminalSessionInfo;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Session.Close;
    Result := Session.Snapshot;
    if FLogger <> nil then
      FLogger.Write(Format('terminal %s closed', [ASessionId]));
  finally
    ReleaseSession(Session);
  end;
end;

function TTerminalRunner.Status(
  const ASessionId: string): TTerminalSessionInfo;
var
  Session: TTerminalSession;
begin
  Session := AcquireSession(ASessionId);
  if Session = nil then
    raise Exception.Create('Unknown terminal session_id: ' + ASessionId);
  try
    Result := Session.Snapshot;
  finally
    ReleaseSession(Session);
  end;
end;

end.
