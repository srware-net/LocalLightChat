unit ProcessRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, ServerLog;

type
  TProcessRunResult = record
    JobId: string;
    ProcessId: Integer;
    Started: Boolean;
    Running: Boolean;
    ExitCode: Integer;
    StdOutText: UTF8String;
    StdErrText: UTF8String;
    TimedOut: Boolean;
    IdleTimedOut: Boolean;
    InteractiveInputDetected: Boolean;
    InteractivePrompt: string;
    Cancelled: Boolean;
    Truncated: Boolean;
    ResponseOutputTruncated: Boolean;
    StdOutCapturedBytes: QWord;
    StdErrCapturedBytes: QWord;
    RequestedTimeoutMs: Cardinal;
    RequestedIdleTimeoutMs: Cardinal;
    DurationMs: QWord;
    ErrorMessage: string;
  end;

  TProcessCancelResult = record
    JobId: string;
    Found: Boolean;
    ProcessId: Integer;
    CancellationRequested: Boolean;
    TerminationAttempted: Boolean;
    TerminationSucceeded: Boolean;
  end;

  TInteractiveGuardState = record
    Enabled: Boolean;
    LineBuffer: RawByteString;
    LastPrompt: RawByteString;
    RepeatCount: Cardinal;
    WindowStartedAt: QWord;
    Detected: Boolean;
    DetectedPrompt: RawByteString;
  end;

  TProcessRunner = class;
  TProcessWorker = class;

  TManagedProcessJob = class
  private
    FLock: TRTLCriticalSection;
    FResult: TProcessRunResult;
    FCompleted: Boolean;
    FWorkerFinished: Boolean;
    FCancelRequested: Boolean;
    FCompletedAt: QWord;
    FReferenceCount: Integer;
    FRemoved: Boolean;
  public
    Worker: TProcessWorker;
    CorrelationId: string;
    constructor Create(const AJobId, ACorrelationId: string);
    destructor Destroy; override;
    procedure Publish(const AResult: TProcessRunResult;
      ACompleted: Boolean = False);
    procedure MarkWorkerFinished;
    procedure RequestCancel;
    function CancellationRequested: Boolean;
    function Snapshot(AMaxOutputChars: Cardinal): TProcessRunResult;
    function CanPrune: Boolean;
    procedure AddReference;
    function ReleaseReference: Boolean;
    function MarkRemoved: Boolean;
  end;

  TProcessWorker = class(TThread)
  private
    FOwner: TProcessRunner;
    FJob: TManagedProcessJob;
    FExecutable: string;
    FArguments: TJSONArray;
    FWorkingDirectory: string;
    FStdInText: string;
    FTimeoutMs: Cardinal;
    FIdleTimeoutMs: Cardinal;
    FMaximumOutputBytes: Cardinal;
    FDisplayCommand: string;
    FHideWindow: Boolean;
    FInteractiveGuard: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TProcessRunner; AJob: TManagedProcessJob;
      const AExecutable: string; AArguments: TJSONArray;
      const AWorkingDirectory, AStdInText: string; ATimeoutMs,
      AIdleTimeoutMs, AMaximumOutputBytes: Cardinal;
      const ADisplayCommand: string; AHideWindow,
      AInteractiveGuard: Boolean);
    destructor Destroy; override;
  end;

  TProcessRunner = class
  private
    FLogger: TServerLogger;
    FLogCommands: Boolean;
    FLogOutput: Boolean;
    FMirrorOutputToConsole: Boolean;
    FConsoleOutputMode: string;
    FDetachFromTerminal: Boolean;
    FInteractiveGuardEnabled: Boolean;
    FInteractivePromptRepeatLimit: Cardinal;
    FInteractivePromptWindowMs: Cardinal;
    FInteractivePromptMaxChars: Cardinal;
    FTerminationGraceMs: Cardinal;
    FMaximumTrackedJobs: Cardinal;
    FJobs: TThreadList;
    procedure Log(const ACorrelationId, AMessage: string);
    procedure MirrorOutputChunk(const AJobId, AStreamName: string;
      const AChunk: RawByteString; var ALineBuffer: RawByteString;
      AFlush: Boolean);
    function DrainPipe(APipe: TStream; ADestination: TMemoryStream;
      AMaximumTotalBytes: Cardinal; var ATotalBytes: QWord;
      var ATruncated: Boolean; const ACorrelationId, AJobId,
      AStreamName: string; var AConsoleLineBuffer: RawByteString;
      var AInteractiveState: TInteractiveGuardState): QWord;
    function NormalizeJobId(const AJobId, ACorrelationId: string): string;
    function RegisterJob(const AJobId,
      ACorrelationId: string): TManagedProcessJob;
    function AcquireJob(const AJobId: string): TManagedProcessJob;
    procedure ReleaseJob(AJob: TManagedProcessJob);
    procedure PruneCompletedJobs;
    function TerminateProcessTree(AProcessId: Integer;
      AForce: Boolean): Boolean;
    procedure ConfigureEnvironment(AProcess: TObject);
    function StartInternal(const AExecutable: string;
      AArguments: TJSONArray; const AWorkingDirectory, AStdInText: string;
      ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes, AWaitMs: Cardinal;
      const ACorrelationId, ADisplayCommand, AJobId: string;
      AHideWindow, AInteractiveGuard: Boolean): TProcessRunResult;
    function WaitForJob(AJob: TManagedProcessJob; AWaitMs,
      AMaxOutputChars: Cardinal): TProcessRunResult;
    procedure RunJob(AJob: TManagedProcessJob; const AExecutable: string;
      AArguments: TJSONArray; const AWorkingDirectory, AStdInText: string;
      ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes: Cardinal;
      const ADisplayCommand: string; AHideWindow,
      AInteractiveGuard: Boolean);
    {$IFDEF UNIX}
    procedure UnixAfterFork(Sender: TObject);
    {$ENDIF}
  public
    constructor Create(ALogger: TServerLogger; ALogCommands,
      ALogOutput, AMirrorOutputToConsole, ADetachFromTerminal: Boolean;
      const AConsoleOutputMode: string; ATerminationGraceMs,
      AMaximumTrackedJobs: Cardinal; AInteractiveGuardEnabled: Boolean;
      AInteractivePromptRepeatLimit, AInteractivePromptWindowMs,
      AInteractivePromptMaxChars: Cardinal);
    destructor Destroy; override;
    function Execute(const AExecutable: string; AArguments: TJSONArray;
      const AWorkingDirectory, AStdInText: string; ATimeoutMs,
      AIdleTimeoutMs, AMaximumOutputBytes, AWaitMs: Cardinal;
      const ACorrelationId, ADisplayCommand,
      AJobId: string; AInteractiveGuard: Boolean): TProcessRunResult;
    function ExecuteShell(const ACommand, AShell,
      AWorkingDirectory, AStdInText: string; ATimeoutMs,
      AIdleTimeoutMs, AMaximumOutputBytes, AWaitMs: Cardinal;
      const ACorrelationId, AJobId: string;
      AInteractiveGuard: Boolean): TProcessRunResult;
    function StartProcess(const AExecutable: string;
      AArguments: TJSONArray; const AWorkingDirectory,
      AStdInText: string; ATimeoutMs, AIdleTimeoutMs,
      AMaximumOutputBytes: Cardinal; const ACorrelationId,
      AJobId: string; AHideWindow: Boolean): TProcessRunResult;
    function StartShell(const ACommand, AShell,
      AWorkingDirectory, AStdInText: string; ATimeoutMs,
      AIdleTimeoutMs, AMaximumOutputBytes: Cardinal;
      const ACorrelationId, AJobId: string): TProcessRunResult;
    function Status(const AJobId: string; AMaxOutputChars: Cardinal;
      out AResult: TProcessRunResult): Boolean;
    function Wait(const AJobId: string; AWaitMs,
      AMaxOutputChars: Cardinal; out AResult: TProcessRunResult): Boolean;
    function Cancel(const AJobId: string): TProcessCancelResult;
  end;

implementation

uses
  Process, Pipes{$IFDEF UNIX}, BaseUnix{$ENDIF};

function StreamToUtf8(AStream: TMemoryStream): UTF8String;
begin
  Result := '';
  SetLength(Result, AStream.Size);
  if AStream.Size > 0 then
  begin
    AStream.Position := 0;
    AStream.ReadBuffer(Result[1], AStream.Size);
  end;
end;

function TailUtf8(const AValue: UTF8String; AMaximumChars: Cardinal;
  out AWasTruncated: Boolean): UTF8String;
var
  Keep: SizeInt;
begin
  AWasTruncated := False;
  if (AMaximumChars = 0) or (Length(AValue) <= SizeInt(AMaximumChars)) then
    Exit(AValue);
  Keep := SizeInt(AMaximumChars);
  Result := Copy(AValue, Length(AValue) - Keep + 1, Keep);
  AWasTruncated := True;
end;


function NormalizePromptLine(const ALine: RawByteString): RawByteString;
var
  I: SizeInt;
  C: Byte;
  EscapeState: Integer;
begin
  Result := '';
  EscapeState := 0;
  for I := 1 to Length(ALine) do
  begin
    C := Byte(ALine[I]);
    if EscapeState = 1 then
    begin
      if C = Ord('[') then
        EscapeState := 2
      else
        EscapeState := 0;
      Continue;
    end;
    if EscapeState = 2 then
    begin
      { ANSI CSI sequences end at a final byte in the range @..~. }
      if (C >= Ord('@')) and (C <= Ord('~')) then
        EscapeState := 0;
      Continue;
    end;
    if C = 27 then
    begin
      EscapeState := 1;
      Continue;
    end;
    if (C >= 32) or (C = 9) then
      Result := Result + AnsiChar(C);
  end;
  Result := RawByteString(Trim(string(Result)));
end;

function LooksLikeInteractivePrompt(const ALine: RawByteString;
  AMaximumChars: Cardinal): Boolean;
var
  S, Lower: string;
  LastChar: Char;
begin
  S := string(NormalizePromptLine(ALine));
  if (S = '') or (Length(S) > Integer(AMaximumChars)) then
    Exit(False);
  LastChar := S[Length(S)];
  if LastChar in ['>', '$', '#', '?'] then
    Exit(True);
  Lower := LowerCase(S);
  Result := ((LastChar = ':') and
    ((Pos('password', Lower) > 0) or (Pos('input', Lower) > 0) or
     (Pos('enter', Lower) > 0) or (Pos('choice', Lower) > 0) or
     (Pos('select', Lower) > 0) or (Pos('prompt', Lower) > 0)));
end;

procedure RegisterInteractivePrompt(const ACandidate: RawByteString;
  var AState: TInteractiveGuardState; ARepeatLimit, AWindowMs,
  AMaximumChars: Cardinal);
var
  Normalized: RawByteString;
  NowTick: QWord;
begin
  if AState.Detected then
    Exit;
  Normalized := NormalizePromptLine(ACandidate);
  if not LooksLikeInteractivePrompt(Normalized, AMaximumChars) then
    Exit;

  NowTick := GetTickCount64;
  if (Normalized = AState.LastPrompt) and
    (AState.WindowStartedAt > 0) and
    ((NowTick - AState.WindowStartedAt) <= AWindowMs) then
    Inc(AState.RepeatCount)
  else
  begin
    AState.LastPrompt := Normalized;
    AState.RepeatCount := 1;
    AState.WindowStartedAt := NowTick;
  end;

  if AState.RepeatCount >= ARepeatLimit then
  begin
    AState.Detected := True;
    AState.DetectedPrompt := Normalized;
  end;
end;

function CountRepeatedSimplePrompts(const AText: RawByteString;
  AMaximumChars: Cardinal; out APrompt: RawByteString): Cardinal;
var
  S, Token, FirstToken: RawByteString;
  I: SizeInt;
  C: AnsiChar;
  ResultCount: Cardinal;

  function AcceptToken: Boolean;
  begin
    Result := True;
    if Token = '' then
      Exit;
    if not LooksLikeInteractivePrompt(Token, AMaximumChars) then
      Exit(False);
    if FirstToken = '' then
      FirstToken := Token
    else if Token <> FirstToken then
      Exit(False);
    Inc(ResultCount);
    Token := '';
  end;

begin
  Result := 0;
  ResultCount := 0;
  APrompt := '';
  S := NormalizePromptLine(AText);
  Token := '';
  FirstToken := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C in [' ', #9] then
    begin
      if not AcceptToken then
        Exit(0);
    end
    else
      Token := Token + C;
  end;
  if not AcceptToken then
    Exit(0);
  if ResultCount > 0 then
  begin
    APrompt := FirstToken;
    Result := ResultCount;
  end;
end;

procedure InspectInteractiveOutputChunk(const AChunk: RawByteString;
  var AState: TInteractiveGuardState; ARepeatLimit, AWindowMs,
  AMaximumChars: Cardinal);
var
  LFPos, CRPos, SeparatorPos, ConsumeCount, I, LastSeparator: SizeInt;
  Line, Fragment, SimplePrompt: RawByteString;
  SimplePromptCount: Cardinal;
begin
  if (not AState.Enabled) or AState.Detected or (AChunk = '') then
    Exit;
  AState.LineBuffer := AState.LineBuffer + AChunk;
  repeat
    LFPos := Pos(#10, AState.LineBuffer);
    CRPos := Pos(#13, AState.LineBuffer);
    if LFPos = 0 then
      SeparatorPos := CRPos
    else if CRPos = 0 then
      SeparatorPos := LFPos
    else if LFPos < CRPos then
      SeparatorPos := LFPos
    else
      SeparatorPos := CRPos;
    if SeparatorPos = 0 then
      Break;

    Line := Copy(AState.LineBuffer, 1, SeparatorPos - 1);
    ConsumeCount := 1;
    if (AState.LineBuffer[SeparatorPos] = #13) and
      (SeparatorPos < Length(AState.LineBuffer)) and
      (AState.LineBuffer[SeparatorPos + 1] = #10) then
      ConsumeCount := 2;
    Delete(AState.LineBuffer, 1, SeparatorPos + ConsumeCount - 1);

    if LooksLikeInteractivePrompt(Line, AMaximumChars) then
      RegisterInteractivePrompt(Line, AState, ARepeatLimit, AWindowMs,
        AMaximumChars)
    else
    begin
      AState.LastPrompt := '';
      AState.RepeatCount := 0;
      AState.WindowStartedAt := 0;
    end;
    if AState.Detected then
      Exit;
  until False;

  { Interactive programs commonly print prompts such as "> " without a line
    ending. Inspect the new unterminated fragment on every pipe read instead of
    waiting forever for CR/LF. This also handles several prompt characters that
    were coalesced into one pipe chunk. }
  LastSeparator := 0;
  for I := 1 to Length(AChunk) do
    if AChunk[I] in [#10, #13] then
      LastSeparator := I;
  Fragment := Copy(AChunk, LastSeparator + 1, MaxInt);
  SimplePromptCount := CountRepeatedSimplePrompts(Fragment,
    AMaximumChars, SimplePrompt);
  if SimplePromptCount > 0 then
    for I := 1 to Integer(SimplePromptCount) do
    begin
      RegisterInteractivePrompt(SimplePrompt, AState, ARepeatLimit,
        AWindowMs, AMaximumChars);
      if AState.Detected then
        Exit;
    end
  else if LooksLikeInteractivePrompt(Fragment, AMaximumChars) then
    RegisterInteractivePrompt(Fragment, AState, ARepeatLimit, AWindowMs,
      AMaximumChars);

  { A prompt fragment should be short. Do not retain an unbounded partial line. }
  if Length(AState.LineBuffer) > Integer(AMaximumChars * 4) then
    AState.LineBuffer := Copy(AState.LineBuffer,
      Length(AState.LineBuffer) - Integer(AMaximumChars * 2) + 1,
      Integer(AMaximumChars * 2));
end;

function QuoteForLog(const S: string): string;
begin
  Result := '"' + StringReplace(S, '"', '\"', [rfReplaceAll]) + '"';
end;

function BuildDirectCommandForLog(const AExecutable: string;
  AArguments: TJSONArray): string;
var
  I: Integer;
begin
  Result := QuoteForLog(AExecutable);
  if AArguments <> nil then
    for I := 0 to AArguments.Count - 1 do
      Result := Result + ' ' + QuoteForLog(AArguments.Strings[I]);
end;

function EnvironmentNameMatches(const ALeft, ARight: string): Boolean;
begin
  {$IFDEF Windows}
  Result := SameText(ALeft, ARight);
  {$ELSE}
  Result := ALeft = ARight;
  {$ENDIF}
end;

procedure SetProcessEnvironmentVariable(AProcess: TProcess;
  const AName, AValue: string);
var
  I, P: Integer;
  ExistingName: string;
begin
  for I := AProcess.Environment.Count - 1 downto 0 do
  begin
    P := Pos('=', AProcess.Environment[I]);
    if P > 0 then
      ExistingName := Copy(AProcess.Environment[I], 1, P - 1)
    else
      ExistingName := AProcess.Environment[I];
    if EnvironmentNameMatches(ExistingName, AName) then
      AProcess.Environment.Delete(I);
  end;
  AProcess.Environment.Add(AName + '=' + AValue);
end;

{ TManagedProcessJob }

constructor TManagedProcessJob.Create(const AJobId,
  ACorrelationId: string);
begin
  inherited Create;
  InitCriticalSection(FLock);
  FillChar(FResult, SizeOf(FResult), 0);
  FResult.JobId := AJobId;
  FResult.ProcessId := 0;
  FResult.ExitCode := -1;
  FResult.Running := True;
  CorrelationId := ACorrelationId;
  FCompleted := False;
  FWorkerFinished := False;
  FCancelRequested := False;
  FCompletedAt := 0;
  FReferenceCount := 0;
  FRemoved := False;
  Worker := nil;
end;

destructor TManagedProcessJob.Destroy;
begin
  Worker.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TManagedProcessJob.Publish(const AResult: TProcessRunResult;
  ACompleted: Boolean);
begin
  EnterCriticalSection(FLock);
  try
    FResult := AResult;
    FResult.Running := not ACompleted;
    FCompleted := ACompleted;
    if ACompleted then
      FCompletedAt := GetTickCount64;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TManagedProcessJob.MarkWorkerFinished;
begin
  EnterCriticalSection(FLock);
  try
    FWorkerFinished := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TManagedProcessJob.RequestCancel;
begin
  EnterCriticalSection(FLock);
  try
    FCancelRequested := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TManagedProcessJob.CancellationRequested: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FCancelRequested;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TManagedProcessJob.Snapshot(AMaxOutputChars: Cardinal): TProcessRunResult;
var
  OutTruncated, ErrTruncated: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FResult;
    Result.Running := not FCompleted;
    Result.StdOutText := TailUtf8(FResult.StdOutText,
      AMaxOutputChars, OutTruncated);
    Result.StdErrText := TailUtf8(FResult.StdErrText,
      AMaxOutputChars, ErrTruncated);
    Result.ResponseOutputTruncated := OutTruncated or ErrTruncated;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TManagedProcessJob.CanPrune: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FCompleted and FWorkerFinished;
  finally
    LeaveCriticalSection(FLock);
  end;
end;


procedure TManagedProcessJob.AddReference;
begin
  EnterCriticalSection(FLock);
  try
    Inc(FReferenceCount);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TManagedProcessJob.ReleaseReference: Boolean;
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

function TManagedProcessJob.MarkRemoved: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    FRemoved := True;
    Result := FReferenceCount = 0;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

{ TProcessWorker }

constructor TProcessWorker.Create(AOwner: TProcessRunner;
  AJob: TManagedProcessJob; const AExecutable: string;
  AArguments: TJSONArray; const AWorkingDirectory,
  AStdInText: string; ATimeoutMs, AIdleTimeoutMs,
  AMaximumOutputBytes: Cardinal; const ADisplayCommand: string;
  AHideWindow, AInteractiveGuard: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FJob := AJob;
  FExecutable := AExecutable;
  if AArguments <> nil then
    FArguments := TJSONArray(AArguments.Clone)
  else
    FArguments := TJSONArray.Create;
  FWorkingDirectory := AWorkingDirectory;
  FStdInText := AStdInText;
  FTimeoutMs := ATimeoutMs;
  FIdleTimeoutMs := AIdleTimeoutMs;
  FMaximumOutputBytes := AMaximumOutputBytes;
  FDisplayCommand := ADisplayCommand;
  FHideWindow := AHideWindow;
  FInteractiveGuard := AInteractiveGuard;
end;

destructor TProcessWorker.Destroy;
begin
  FArguments.Free;
  inherited Destroy;
end;

procedure TProcessWorker.Execute;
begin
  try
    FOwner.RunJob(FJob, FExecutable, FArguments,
      FWorkingDirectory, FStdInText, FTimeoutMs,
      FIdleTimeoutMs, FMaximumOutputBytes,
      FDisplayCommand, FHideWindow, FInteractiveGuard);
  finally
    FJob.MarkWorkerFinished;
  end;
end;

{ TProcessRunner }

constructor TProcessRunner.Create(ALogger: TServerLogger; ALogCommands,
  ALogOutput, AMirrorOutputToConsole, ADetachFromTerminal: Boolean;
  const AConsoleOutputMode: string; ATerminationGraceMs,
  AMaximumTrackedJobs: Cardinal; AInteractiveGuardEnabled: Boolean;
  AInteractivePromptRepeatLimit, AInteractivePromptWindowMs,
  AInteractivePromptMaxChars: Cardinal);
begin
  inherited Create;
  FLogger := ALogger;
  FLogCommands := ALogCommands;
  FLogOutput := ALogOutput;
  FMirrorOutputToConsole := AMirrorOutputToConsole;
  FConsoleOutputMode := LowerCase(Trim(AConsoleOutputMode));
  if (FConsoleOutputMode <> 'raw') and
    (FConsoleOutputMode <> 'prefixed') then
    FConsoleOutputMode := 'prefixed';
  FDetachFromTerminal := ADetachFromTerminal;
  FInteractiveGuardEnabled := AInteractiveGuardEnabled;
  if AInteractivePromptRepeatLimit < 3 then
    FInteractivePromptRepeatLimit := 3
  else
    FInteractivePromptRepeatLimit := AInteractivePromptRepeatLimit;
  if AInteractivePromptWindowMs < 100 then
    FInteractivePromptWindowMs := 100
  else
    FInteractivePromptWindowMs := AInteractivePromptWindowMs;
  if AInteractivePromptMaxChars < 4 then
    FInteractivePromptMaxChars := 4
  else
    FInteractivePromptMaxChars := AInteractivePromptMaxChars;
  FTerminationGraceMs := ATerminationGraceMs;
  if AMaximumTrackedJobs < 8 then
    FMaximumTrackedJobs := 8
  else
    FMaximumTrackedJobs := AMaximumTrackedJobs;
  FJobs := TThreadList.Create;
end;

destructor TProcessRunner.Destroy;
var
  JobsCopy: TList;
  List: TList;
  I: Integer;
  Job: TManagedProcessJob;
  SnapshotResult: TProcessRunResult;
begin
  JobsCopy := TList.Create;
  try
    List := FJobs.LockList;
    try
      for I := 0 to List.Count - 1 do
      begin
        Job := TManagedProcessJob(List[I]);
        JobsCopy.Add(Job);
        Job.RequestCancel;
        SnapshotResult := Job.Snapshot(0);
        if SnapshotResult.ProcessId > 0 then
          TerminateProcessTree(SnapshotResult.ProcessId, True);
      end;
    finally
      FJobs.UnlockList;
    end;

    for I := 0 to JobsCopy.Count - 1 do
    begin
      Job := TManagedProcessJob(JobsCopy[I]);
      if Job.Worker <> nil then
        Job.Worker.WaitFor;
    end;

    List := FJobs.LockList;
    try
      List.Clear;
    finally
      FJobs.UnlockList;
    end;
    for I := 0 to JobsCopy.Count - 1 do
      TObject(JobsCopy[I]).Free;
  finally
    JobsCopy.Free;
    FJobs.Free;
  end;
  inherited Destroy;
end;

procedure TProcessRunner.Log(const ACorrelationId, AMessage: string);
begin
  if FLogger = nil then
    Exit;
  if ACorrelationId <> '' then
    FLogger.Write(ACorrelationId + ' ' + AMessage)
  else
    FLogger.Write(AMessage);
end;

procedure TProcessRunner.MirrorOutputChunk(const AJobId,
  AStreamName: string; const AChunk: RawByteString;
  var ALineBuffer: RawByteString; AFlush: Boolean);
var
  LFPos, CRPos, SeparatorPos, ConsumeCount: SizeInt;
  Line, ConsoleBlock, Prefix, NewLineBytes: RawByteString;

  procedure AppendConsoleLine(const ALine: RawByteString);
  begin
    ConsoleBlock := ConsoleBlock + Prefix + ALine + NewLineBytes;
  end;

begin
  if (not FMirrorOutputToConsole) or (FLogger = nil) then
    Exit;

  if FConsoleOutputMode = 'raw' then
  begin
    if AChunk <> '' then
      FLogger.WriteConsoleRaw(AChunk);
    Exit;
  end;

  Prefix := RawByteString('[' + AJobId + ' ' + AStreamName + '] ');
  NewLineBytes := RawByteString(LineEnding);
  ConsoleBlock := '';

  if AChunk <> '' then
    ALineBuffer := ALineBuffer + AChunk;

  repeat
    LFPos := Pos(#10, ALineBuffer);
    CRPos := Pos(#13, ALineBuffer);
    if LFPos = 0 then
      SeparatorPos := CRPos
    else if CRPos = 0 then
      SeparatorPos := LFPos
    else if LFPos < CRPos then
      SeparatorPos := LFPos
    else
      SeparatorPos := CRPos;

    if SeparatorPos = 0 then
      Break;
    { A CRLF pair can be split between two pipe reads. Keep a trailing CR
      until the next chunk so prefixed mode does not emit a spurious blank
      line when the following chunk begins with LF. }
    if (ALineBuffer[SeparatorPos] = #13) and
      (SeparatorPos = Length(ALineBuffer)) and (not AFlush) then
      Break;

    Line := Copy(ALineBuffer, 1, SeparatorPos - 1);
    ConsumeCount := 1;
    if (ALineBuffer[SeparatorPos] = #13) and
      (SeparatorPos < Length(ALineBuffer)) and
      (ALineBuffer[SeparatorPos + 1] = #10) then
      ConsumeCount := 2;
    Delete(ALineBuffer, 1, SeparatorPos + ConsumeCount - 1);
    AppendConsoleLine(Line);
  until False;

  if AFlush and (ALineBuffer <> '') then
  begin
    AppendConsoleLine(ALineBuffer);
    ALineBuffer := '';
  end
  else if Length(ALineBuffer) >= 16384 then
  begin
    AppendConsoleLine(ALineBuffer);
    ALineBuffer := '';
  end;

  { Write and flush once per drained pipe chunk instead of once per line.
    Commands such as dir /s or find / can produce tens of thousands of short
    lines; per-line console locking and flushing can otherwise throttle the
    child process enough to look hung. }
  if ConsoleBlock <> '' then
    FLogger.WriteConsoleRaw(ConsoleBlock);
end;

function TProcessRunner.DrainPipe(APipe: TStream;
  ADestination: TMemoryStream; AMaximumTotalBytes: Cardinal;
  var ATotalBytes: QWord; var ATruncated: Boolean;
  const ACorrelationId, AJobId, AStreamName: string;
  var AConsoleLineBuffer: RawByteString;
  var AInteractiveState: TInteractiveGuardState): QWord;
const
  MaximumDrainBytesPerPass = 256 * 1024;
var
  Buffer: array[0..8191] of Byte;
  Available, ReadCount, KeepCount: LongInt;
  Chunk: RawByteString;
begin
  Result := 0;
  if not (APipe is TInputPipeStream) then
    Exit;
  while TInputPipeStream(APipe).NumBytesAvailable > 0 do
  begin
    Available := TInputPipeStream(APipe).NumBytesAvailable;
    if Available > SizeOf(Buffer) then
      Available := SizeOf(Buffer);
    ReadCount := APipe.Read(Buffer[0], Available);
    if ReadCount <= 0 then
      Exit;
    Inc(Result, ReadCount);

    SetString(Chunk, PAnsiChar(@Buffer[0]), ReadCount);
    InspectInteractiveOutputChunk(Chunk, AInteractiveState,
      FInteractivePromptRepeatLimit, FInteractivePromptWindowMs,
      FInteractivePromptMaxChars);
    if FLogOutput and (FLogger <> nil) then
      FLogger.WriteFileBlock(ACorrelationId + ' process ' +
        AStreamName + ': ', string(Chunk));
    MirrorOutputChunk(AJobId, AStreamName, Chunk,
      AConsoleLineBuffer, False);

    KeepCount := ReadCount;
    if ATotalBytes + QWord(KeepCount) > AMaximumTotalBytes then
    begin
      if ATotalBytes >= AMaximumTotalBytes then
        KeepCount := 0
      else
        KeepCount := LongInt(AMaximumTotalBytes - ATotalBytes);
      ATruncated := True;
    end;

    if KeepCount > 0 then
      ADestination.WriteBuffer(Buffer[0], KeepCount);
    Inc(ATotalBytes, ReadCount);

    { A continuously writing child must not monopolize this worker inside the
      pipe-drain loop. Return regularly so cancellation, lifetime timeout and
      interactive-prompt detection are evaluated even under output floods. }
    if AInteractiveState.Detected or
      (Result >= MaximumDrainBytesPerPass) then
      Exit;
  end;
end;

function TProcessRunner.NormalizeJobId(const AJobId,
  ACorrelationId: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := Trim(AJobId);
  if Result = '' then
    Result := ACorrelationId;
  if Result = '' then
    Result := 'job-' + IntToHex(GetTickCount64, 16);
  if Length(Result) > 128 then
    raise Exception.Create('job_id must not exceed 128 characters');
  for I := 1 to Length(Result) do
  begin
    C := Result[I];
    if not (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ':']) then
      raise Exception.Create('job_id contains an invalid character');
  end;
end;

procedure TProcessRunner.PruneCompletedJobs;
var
  List, Removed: TList;
  I: Integer;
  Job: TManagedProcessJob;
begin
  Removed := TList.Create;
  try
    List := FJobs.LockList;
    try
      I := 0;
      while (List.Count >= Integer(FMaximumTrackedJobs)) and
        (I < List.Count) do
      begin
        Job := TManagedProcessJob(List[I]);
        if Job.CanPrune then
        begin
          List.Delete(I);
          if Job.MarkRemoved then
            Removed.Add(Job);
        end
        else
          Inc(I);
      end;
    finally
      FJobs.UnlockList;
    end;
    for I := 0 to Removed.Count - 1 do
      TObject(Removed[I]).Free;
  finally
    Removed.Free;
  end;
end;

function TProcessRunner.RegisterJob(const AJobId,
  ACorrelationId: string): TManagedProcessJob;
var
  List: TList;
  I: Integer;
  Existing: TManagedProcessJob;
begin
  PruneCompletedJobs;
  Result := TManagedProcessJob.Create(AJobId, ACorrelationId);
  List := FJobs.LockList;
  try
    if List.Count >= Integer(FMaximumTrackedJobs) then
    begin
      Result.Free;
      raise Exception.Create('Maximum number of tracked process jobs reached');
    end;
    for I := 0 to List.Count - 1 do
    begin
      Existing := TManagedProcessJob(List[I]);
      if SameText(Existing.Snapshot(0).JobId, AJobId) then
      begin
        Result.Free;
        raise Exception.Create('A process job already uses job_id ' + AJobId);
      end;
    end;
    List.Add(Result);
  finally
    FJobs.UnlockList;
  end;
end;

function TProcessRunner.AcquireJob(const AJobId: string): TManagedProcessJob;
var
  List: TList;
  I: Integer;
  SnapshotResult: TProcessRunResult;
begin
  Result := nil;
  List := FJobs.LockList;
  try
    for I := 0 to List.Count - 1 do
    begin
      SnapshotResult := TManagedProcessJob(List[I]).Snapshot(0);
      if SameText(SnapshotResult.JobId, Trim(AJobId)) then
      begin
        Result := TManagedProcessJob(List[I]);
        Result.AddReference;
        Break;
      end;
    end;
  finally
    FJobs.UnlockList;
  end;
end;

procedure TProcessRunner.ReleaseJob(AJob: TManagedProcessJob);
begin
  if (AJob <> nil) and AJob.ReleaseReference then
    AJob.Free;
end;

{$IFDEF UNIX}
procedure TProcessRunner.UnixAfterFork(Sender: TObject);
begin
  fpSetSid;
end;
{$ENDIF}

procedure TProcessRunner.ConfigureEnvironment(AProcess: TObject);
var
  P: TProcess;
  I, Count: Integer;
  Entry: string;
begin
  if not (AProcess is TProcess) then
    Exit;
  P := TProcess(AProcess);
  P.Environment.Clear;
  Count := GetEnvironmentVariableCount;
  if Count > 0 then
    for I := 1 to Count do
    begin
      Entry := GetEnvironmentString(I);
      if Entry <> '' then
        P.Environment.Add(Entry);
    end;

  SetProcessEnvironmentVariable(P, 'CI', '1');
  SetProcessEnvironmentVariable(P, 'TERM', 'dumb');
  SetProcessEnvironmentVariable(P, 'PAGER', 'cat');
  SetProcessEnvironmentVariable(P, 'GIT_PAGER', 'cat');
  SetProcessEnvironmentVariable(P, 'SYSTEMD_PAGER', 'cat');
  SetProcessEnvironmentVariable(P, 'GIT_TERMINAL_PROMPT', '0');
  SetProcessEnvironmentVariable(P, 'GCM_INTERACTIVE', 'Never');
  SetProcessEnvironmentVariable(P, 'DEBIAN_FRONTEND', 'noninteractive');
  SetProcessEnvironmentVariable(P, 'APT_LISTCHANGES_FRONTEND', 'none');
  {$IFDEF UNIX}
  SetProcessEnvironmentVariable(P, 'SSH_ASKPASS_REQUIRE', 'never');
  {$ENDIF}
end;

{$IFDEF LINUX}
procedure CollectLinuxDescendants(AProcessId: Integer; AList: TStringList);
var
  Source: TStringList;
  Content, Token, ChildText: string;
  I, ChildPid, Code: Integer;

  procedure AcceptToken;
  begin
    ChildText := Trim(Token);
    Token := '';
    if ChildText = '' then
      Exit;
    Val(ChildText, ChildPid, Code);
    if (Code <> 0) or (ChildPid <= 0) or
      (AList.IndexOf(ChildText) >= 0) then
      Exit;
    AList.Add(ChildText);
    CollectLinuxDescendants(ChildPid, AList);
  end;

begin
  Source := TStringList.Create;
  try
    try
      Source.LoadFromFile(Format('/proc/%d/task/%d/children',
        [AProcessId, AProcessId]));
    except
      Exit;
    end;
    Content := Source.Text;
    Token := '';
    for I := 1 to Length(Content) do
      if Content[I] in [' ', #9, #10, #13] then
        AcceptToken
      else
        Token := Token + Content[I];
    AcceptToken;
  finally
    Source.Free;
  end;
end;
{$ENDIF}

function TProcessRunner.TerminateProcessTree(AProcessId: Integer;
  AForce: Boolean): Boolean;
{$IFDEF Windows}
var
  Killer: TProcess;
{$ELSE}
var
  SignalValue: cint;
  {$IFDEF LINUX}
  Descendants: TStringList;
  I, DescendantPid, Code: Integer;
  {$ENDIF}
{$ENDIF}
begin
  Result := False;
  if AProcessId <= 0 then
    Exit;

  {$IFDEF Windows}
  Killer := TProcess.Create(nil);
  try
    Killer.Executable := 'taskkill.exe';
    Killer.Parameters.Add('/PID');
    Killer.Parameters.Add(IntToStr(AProcessId));
    Killer.Parameters.Add('/T');
    if AForce then
      Killer.Parameters.Add('/F');
    Killer.Options := [poWaitOnExit, poNoConsole];
    try
      Killer.Execute;
      Result := Killer.ExitCode = 0;
    except
      Result := False;
    end;
  finally
    Killer.Free;
  end;
  {$ELSE}
  if AForce then
    SignalValue := SIGKILL
  else
    SignalValue := SIGTERM;

  {$IFDEF LINUX}
  { Read the descendant list before signalling the shell wrapper. If the shell
    exits first, /proc/<pid>/children disappears while grandchildren can still
    keep inherited pipes open. Process-group signalling remains the fast path;
    explicit descendant signalling is the robust fallback. }
  Descendants := TStringList.Create;
  try
    Descendants.Duplicates := dupIgnore;
    Descendants.Sorted := False;
    CollectLinuxDescendants(AProcessId, Descendants);
    Result := fpKill(-AProcessId, SignalValue) = 0;
    for I := Descendants.Count - 1 downto 0 do
    begin
      Val(Descendants[I], DescendantPid, Code);
      if (Code = 0) and (DescendantPid > 0) and
        (fpKill(DescendantPid, SignalValue) = 0) then
        Result := True;
    end;
    if fpKill(AProcessId, SignalValue) = 0 then
      Result := True;
  finally
    Descendants.Free;
  end;
  {$ELSE}
  Result := fpKill(-AProcessId, SignalValue) = 0;
  if not Result then
    Result := fpKill(AProcessId, SignalValue) = 0;
  {$ENDIF}
  {$ENDIF}
end;

procedure TProcessRunner.RunJob(AJob: TManagedProcessJob;
  const AExecutable: string; AArguments: TJSONArray;
  const AWorkingDirectory, AStdInText: string; ATimeoutMs,
  AIdleTimeoutMs, AMaximumOutputBytes: Cardinal;
  const ADisplayCommand: string; AHideWindow,
  AInteractiveGuard: Boolean);
var
  P: TProcess;
  OutStream, ErrStream: TMemoryStream;
  ResultData: TProcessRunResult;
  I: Integer;
  StartedAt, TotalBytes, TerminationStartedAt, LastActivityAt,
    BytesRead, LastPublishAt, TerminationHardStopMs: QWord;
  InputBytes: UTF8String;
  TerminateIssued, ForceTerminateIssued, AbandonPipeWait: Boolean;
  CommandForLog, TimeoutForLog, IdleTimeoutForLog,
    TerminationReason: string;
  StdOutConsoleBuffer, StdErrConsoleBuffer: RawByteString;
  StdOutInteractiveState, StdErrInteractiveState: TInteractiveGuardState;

  procedure PublishProgress;
  begin
    ResultData.StdOutText := StreamToUtf8(OutStream);
    ResultData.StdErrText := StreamToUtf8(ErrStream);
    ResultData.StdOutCapturedBytes := QWord(OutStream.Size);
    ResultData.StdErrCapturedBytes := QWord(ErrStream.Size);
    ResultData.DurationMs := GetTickCount64 - StartedAt;
    AJob.Publish(ResultData, False);
    LastPublishAt := GetTickCount64;
  end;

  procedure BeginTermination(const AReason: string);
  begin
    if TerminateIssued then
      Exit;
    TerminateIssued := True;
    TerminationStartedAt := GetTickCount64;
    TerminationReason := AReason;
    ResultData.DurationMs := TerminationStartedAt - StartedAt;
    AJob.Publish(ResultData, False);
    Log(AJob.CorrelationId, Format(
      'process %s; terminating job_id=%s pid=%d',
      [AReason, ResultData.JobId, P.ProcessID]));
    TerminateProcessTree(P.ProcessID, False);
  end;

begin
  ResultData := AJob.Snapshot(0);
  StdOutConsoleBuffer := '';
  StdErrConsoleBuffer := '';
  StdOutInteractiveState.Enabled := AInteractiveGuard;
  StdOutInteractiveState.LineBuffer := '';
  StdOutInteractiveState.LastPrompt := '';
  StdOutInteractiveState.RepeatCount := 0;
  StdOutInteractiveState.WindowStartedAt := 0;
  StdOutInteractiveState.Detected := False;
  StdOutInteractiveState.DetectedPrompt := '';
  StdErrInteractiveState := StdOutInteractiveState;
  StartedAt := GetTickCount64;
  ResultData.ExitCode := -1;
  ResultData.ErrorMessage := '';
  ResultData.RequestedTimeoutMs := ATimeoutMs;
  ResultData.RequestedIdleTimeoutMs := AIdleTimeoutMs;
  ResultData.Running := True;
  P := TProcess.Create(nil);
  OutStream := TMemoryStream.Create;
  ErrStream := TMemoryStream.Create;
  try
    try
      P.Executable := AExecutable;
      if AArguments <> nil then
        for I := 0 to AArguments.Count - 1 do
          P.Parameters.Add(AArguments.Strings[I]);
      if AWorkingDirectory <> '' then
        P.CurrentDirectory := AWorkingDirectory;
      P.Options := [poUsePipes];
      {$IFDEF Windows}
      P.InheritHandles := True;
      P.Options := P.Options + [poNoConsole, poNewProcessGroup];
      if AHideWindow then
        P.ShowWindow := swoHIDE;
      {$ELSE}
      P.InheritHandles := False;
      if FDetachFromTerminal then
        P.OnForkEvent := @UnixAfterFork;
      {$ENDIF}
      ConfigureEnvironment(P);

      if ADisplayCommand <> '' then
        CommandForLog := ADisplayCommand
      else
        CommandForLog := BuildDirectCommandForLog(AExecutable, AArguments);
      if ATimeoutMs = 0 then
        TimeoutForLog := 'unlimited'
      else
        TimeoutForLog := IntToStr(ATimeoutMs);
      if AIdleTimeoutMs = 0 then
        IdleTimeoutForLog := 'unlimited'
      else
        IdleTimeoutForLog := IntToStr(AIdleTimeoutMs);
      if FLogCommands then
        Log(AJob.CorrelationId, Format(
          'process start job_id=%s cwd=%s timeout_ms=%s idle_timeout_ms=%s command=%s',
          [ResultData.JobId, QuoteForLog(AWorkingDirectory), TimeoutForLog,
           IdleTimeoutForLog, CommandForLog]));

      StartedAt := GetTickCount64;
      LastActivityAt := StartedAt;
      LastPublishAt := 0;
      P.Execute;
      ResultData.ProcessId := P.ProcessID;
      ResultData.Started := True;
      AJob.Publish(ResultData, False);
      Log(AJob.CorrelationId, Format('process job_id=%s pid=%d started',
        [ResultData.JobId, P.ProcessID]));

      if AStdInText <> '' then
      begin
        InputBytes := UTF8Encode(AStdInText);
        if Length(InputBytes) > 0 then
          P.Input.WriteBuffer(InputBytes[1], Length(InputBytes));
        LastActivityAt := GetTickCount64;
        Log(AJob.CorrelationId, Format('process stdin_bytes=%d',
          [Length(InputBytes)]));
      end;
      P.CloseInput;

      TotalBytes := 0;
      TerminateIssued := False;
      ForceTerminateIssued := False;
      AbandonPipeWait := False;
      TerminationStartedAt := 0;
      TerminationReason := '';
      TerminationHardStopMs := QWord(FTerminationGraceMs) + 2000;
      if TerminationHardStopMs < 2000 then
        TerminationHardStopMs := 2000;
      repeat
        BytesRead := DrainPipe(P.Output, OutStream, AMaximumOutputBytes,
          TotalBytes, ResultData.Truncated, AJob.CorrelationId,
          ResultData.JobId, 'stdout', StdOutConsoleBuffer,
          StdOutInteractiveState);
        Inc(BytesRead, DrainPipe(P.Stderr, ErrStream, AMaximumOutputBytes,
          TotalBytes, ResultData.Truncated, AJob.CorrelationId,
          ResultData.JobId, 'stderr', StdErrConsoleBuffer,
          StdErrInteractiveState));
        if BytesRead > 0 then
          LastActivityAt := GetTickCount64;

        { Cancellation, lifetime timeouts and prompt-loop detection apply to
          the complete managed job, not merely to the immediate shell process.
          A shell can exit after receiving SIGTERM while a descendant still
          owns stdout/stderr; gating these checks on P.Running previously left
          such descendants alive and made the configured timeout look ignored. }
        if (not TerminateIssued) and AJob.CancellationRequested then
        begin
          ResultData.Cancelled := True;
          BeginTermination('cancel requested');
        end;

        if (not TerminateIssued) and (ATimeoutMs > 0) and
          ((GetTickCount64 - StartedAt) >= ATimeoutMs) then
        begin
          ResultData.TimedOut := True;
          BeginTermination(Format('total timeout after %d ms',
            [GetTickCount64 - StartedAt]));
        end;

        if (not TerminateIssued) and (AIdleTimeoutMs > 0) and
          ((GetTickCount64 - LastActivityAt) >= AIdleTimeoutMs) then
        begin
          ResultData.IdleTimedOut := True;
          BeginTermination(Format('idle timeout after %d ms without output',
            [GetTickCount64 - LastActivityAt]));
        end;

        if (not TerminateIssued) and
          (StdOutInteractiveState.Detected or
           StdErrInteractiveState.Detected) then
        begin
          ResultData.InteractiveInputDetected := True;
          if StdOutInteractiveState.Detected then
            ResultData.InteractivePrompt :=
              string(StdOutInteractiveState.DetectedPrompt)
          else
            ResultData.InteractivePrompt :=
              string(StdErrInteractiveState.DetectedPrompt);
          BeginTermination('repeated interactive prompt detected after stdin was closed');
        end;

        if TerminateIssued and (not ForceTerminateIssued) and
          ((FTerminationGraceMs = 0) or
           ((GetTickCount64 - TerminationStartedAt) >= FTerminationGraceMs)) then
        begin
          ForceTerminateIssued := True;
          Log(AJob.CorrelationId, Format(
            'process forcing process-tree termination job_id=%s pid=%d reason=%s',
            [ResultData.JobId, P.ProcessID, TerminationReason]));
          TerminateProcessTree(P.ProcessID, True);
        end;

        if TerminateIssued and ForceTerminateIssued and
          ((GetTickCount64 - TerminationStartedAt) >= TerminationHardStopMs) then
        begin
          { Never let an orphaned descendant keep inherited pipe handles open
            forever after timeout/cancellation. Close our side and finalize the
            job even if the operating system could not reap the entire tree. }
          AbandonPipeWait := True;
          Log(AJob.CorrelationId, Format(
            'process abandoning pipe wait job_id=%s pid=%d reason=%s elapsed_ms=%d',
            [ResultData.JobId, P.ProcessID, TerminationReason,
             GetTickCount64 - TerminationStartedAt]));
          Break;
        end;

        if (BytesRead > 0) and
          ((GetTickCount64 - LastPublishAt) >= 250) then
          PublishProgress;

        if (not P.Running) and
          (TInputPipeStream(P.Output).NumBytesAvailable = 0) and
          (TInputPipeStream(P.Stderr).NumBytesAvailable = 0) then
          Break;
        Sleep(10);
      until False;

      if AJob.CancellationRequested then
        ResultData.Cancelled := True;

      if P.Running then
      begin
        TerminateProcessTree(P.ProcessID, True);
        Sleep(50);
      end;
      if not P.Running then
        P.WaitOnExit;
      if not AbandonPipeWait then
      begin
        DrainPipe(P.Output, OutStream, AMaximumOutputBytes,
          TotalBytes, ResultData.Truncated, AJob.CorrelationId,
          ResultData.JobId, 'stdout', StdOutConsoleBuffer,
          StdOutInteractiveState);
        DrainPipe(P.Stderr, ErrStream, AMaximumOutputBytes,
          TotalBytes, ResultData.Truncated, AJob.CorrelationId,
          ResultData.JobId, 'stderr', StdErrConsoleBuffer,
          StdErrInteractiveState);
      end;
      MirrorOutputChunk(ResultData.JobId, 'stdout', '',
        StdOutConsoleBuffer, True);
      MirrorOutputChunk(ResultData.JobId, 'stderr', '',
        StdErrConsoleBuffer, True);

      if P.Running or AbandonPipeWait then
        ResultData.ExitCode := -1
      else
        ResultData.ExitCode := P.ExitCode;
      ResultData.DurationMs := GetTickCount64 - StartedAt;
      ResultData.StdOutText := StreamToUtf8(OutStream);
      ResultData.StdErrText := StreamToUtf8(ErrStream);
      ResultData.StdOutCapturedBytes := QWord(OutStream.Size);
      ResultData.StdErrCapturedBytes := QWord(ErrStream.Size);
      ResultData.Running := False;
      AJob.Publish(ResultData, True);
      Log(AJob.CorrelationId, Format(
        'process exit job_id=%s pid=%d exit_code=%d duration_ms=%d timed_out=%s idle_timed_out=%s interactive_detected=%s cancelled=%s truncated=%s stdout_bytes=%d stderr_bytes=%d',
        [ResultData.JobId, P.ProcessID, ResultData.ExitCode,
         ResultData.DurationMs, BoolToStr(ResultData.TimedOut, True),
         BoolToStr(ResultData.IdleTimedOut, True),
         BoolToStr(ResultData.InteractiveInputDetected, True),
         BoolToStr(ResultData.Cancelled, True),
         BoolToStr(ResultData.Truncated, True),
         Length(ResultData.StdOutText), Length(ResultData.StdErrText)]));
    except
      on E: Exception do
      begin
        ResultData.ErrorMessage := E.ClassName + ': ' + E.Message;
        ResultData.Running := False;
        if ResultData.Started and (P.ProcessID > 0) and P.Running then
          TerminateProcessTree(P.ProcessID, True);
        if ResultData.DurationMs = 0 then
          ResultData.DurationMs := GetTickCount64 - StartedAt;
        MirrorOutputChunk(ResultData.JobId, 'stdout', '',
          StdOutConsoleBuffer, True);
        MirrorOutputChunk(ResultData.JobId, 'stderr', '',
          StdErrConsoleBuffer, True);
        AJob.Publish(ResultData, True);
        Log(AJob.CorrelationId, 'process exception: ' +
          ResultData.ErrorMessage);
      end;
    end;
  finally
    ErrStream.Free;
    OutStream.Free;
    P.Free;
  end;
end;

function TProcessRunner.WaitForJob(AJob: TManagedProcessJob;
  AWaitMs, AMaxOutputChars: Cardinal): TProcessRunResult;
var
  StartedWaitingAt: QWord;
begin
  StartedWaitingAt := GetTickCount64;
  repeat
    { Poll only process metadata while the job runs. Copying the complete,
      continuously growing output every 20 ms would be quadratic for verbose
      compilers, directory scans, and similar commands. }
    Result := AJob.Snapshot(1);
    if not Result.Running then
    begin
      Result := AJob.Snapshot(AMaxOutputChars);
      Exit;
    end;
    if AWaitMs = 0 then
      Exit;
    if (GetTickCount64 - StartedWaitingAt) >= AWaitMs then
      Exit;
    Sleep(20);
  until False;
end;

function TProcessRunner.StartInternal(const AExecutable: string;
  AArguments: TJSONArray; const AWorkingDirectory, AStdInText: string;
  ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes, AWaitMs: Cardinal;
  const ACorrelationId, ADisplayCommand, AJobId: string;
  AHideWindow, AInteractiveGuard: Boolean): TProcessRunResult;
var
  Job: TManagedProcessJob;
  EffectiveJobId: string;
  LaunchWaitStarted: QWord;
begin
  EffectiveJobId := NormalizeJobId(AJobId, ACorrelationId);
  Job := RegisterJob(EffectiveJobId, ACorrelationId);
  try
    try
      Job.Worker := TProcessWorker.Create(Self, Job, AExecutable,
        AArguments, AWorkingDirectory, AStdInText, ATimeoutMs,
        AIdleTimeoutMs, AMaximumOutputBytes, ADisplayCommand,
        AHideWindow, AInteractiveGuard);
      Job.Worker.Start;
    except
      on E: Exception do
      begin
        Result := Job.Snapshot(0);
        Result.ErrorMessage := E.ClassName + ': ' + E.Message;
        Result.Running := False;
        Job.Publish(Result, True);
        Job.MarkWorkerFinished;
        raise;
      end;
    end;

    { Always wait briefly for CreateProcess/fork+exec to either succeed or
      report a launch error. This is not a process lifetime timeout. }
    LaunchWaitStarted := GetTickCount64;
    repeat
      Result := Job.Snapshot(1);
      if Result.Started or (not Result.Running) then
        Break;
      if (GetTickCount64 - LaunchWaitStarted) >= 500 then
        Break;
      Sleep(10);
    until False;

    if not Result.Running then
      Result := Job.Snapshot(0)
    else if AWaitMs > 0 then
      Result := WaitForJob(Job, AWaitMs, 0);
  except
    Job.RequestCancel;
    raise;
  end;
end;

function TProcessRunner.Execute(const AExecutable: string;
  AArguments: TJSONArray; const AWorkingDirectory,
  AStdInText: string; ATimeoutMs, AIdleTimeoutMs,
  AMaximumOutputBytes, AWaitMs: Cardinal;
  const ACorrelationId, ADisplayCommand,
  AJobId: string; AInteractiveGuard: Boolean): TProcessRunResult;
begin
  Result := StartInternal(AExecutable, AArguments, AWorkingDirectory,
    AStdInText, ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes,
    AWaitMs, ACorrelationId, ADisplayCommand, AJobId, False,
    FInteractiveGuardEnabled and AInteractiveGuard);
end;

function TProcessRunner.ExecuteShell(const ACommand, AShell,
  AWorkingDirectory, AStdInText: string; ATimeoutMs,
  AIdleTimeoutMs, AMaximumOutputBytes, AWaitMs: Cardinal;
  const ACorrelationId, AJobId: string;
  AInteractiveGuard: Boolean): TProcessRunResult;
var
  Executable, ShellName: string;
  Args: TJSONArray;
begin
  ShellName := LowerCase(Trim(AShell));
  Args := TJSONArray.Create;
  try
    {$IFDEF Windows}
    if (ShellName = 'powershell') or (ShellName = 'pwsh') then
    begin
      if ShellName = 'pwsh' then
        Executable := 'pwsh.exe'
      else
        Executable := 'powershell.exe';
      Args.Add('-NoProfile');
      Args.Add('-NonInteractive');
      Args.Add('-Command');
      Args.Add(ACommand);
    end
    else
    begin
      Executable := 'cmd.exe';
      Args.Add('/D');
      Args.Add('/S');
      Args.Add('/C');
      Args.Add(ACommand);
    end;
    {$ELSE}
    if ShellName = 'bash' then
      Executable := '/bin/bash'
    else
      Executable := '/bin/sh';
    Args.Add('-c');
    Args.Add(ACommand);
    {$ENDIF}

    Result := StartInternal(Executable, Args, AWorkingDirectory,
      AStdInText, ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes,
      AWaitMs, ACorrelationId, ACommand, AJobId, True,
      FInteractiveGuardEnabled and AInteractiveGuard);
  finally
    Args.Free;
  end;
end;

function TProcessRunner.StartProcess(const AExecutable: string;
  AArguments: TJSONArray; const AWorkingDirectory,
  AStdInText: string; ATimeoutMs, AIdleTimeoutMs,
  AMaximumOutputBytes: Cardinal; const ACorrelationId,
  AJobId: string; AHideWindow: Boolean): TProcessRunResult;
begin
  Result := StartInternal(AExecutable, AArguments, AWorkingDirectory,
    AStdInText, ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes,
    0, ACorrelationId, '', AJobId, AHideWindow, False);
end;

function TProcessRunner.StartShell(const ACommand, AShell,
  AWorkingDirectory, AStdInText: string; ATimeoutMs,
  AIdleTimeoutMs, AMaximumOutputBytes: Cardinal;
  const ACorrelationId, AJobId: string): TProcessRunResult;
begin
  Result := ExecuteShell(ACommand, AShell, AWorkingDirectory,
    AStdInText, ATimeoutMs, AIdleTimeoutMs, AMaximumOutputBytes,
    0, ACorrelationId, AJobId, False);
end;

function TProcessRunner.Status(const AJobId: string;
  AMaxOutputChars: Cardinal; out AResult: TProcessRunResult): Boolean;
var
  Job: TManagedProcessJob;
begin
  Job := AcquireJob(AJobId);
  Result := Job <> nil;
  if Result then
    try
      AResult := Job.Snapshot(AMaxOutputChars);
    finally
      ReleaseJob(Job);
    end;
end;

function TProcessRunner.Wait(const AJobId: string; AWaitMs,
  AMaxOutputChars: Cardinal; out AResult: TProcessRunResult): Boolean;
var
  Job: TManagedProcessJob;
begin
  Job := AcquireJob(AJobId);
  Result := Job <> nil;
  if Result then
    try
      AResult := WaitForJob(Job, AWaitMs, AMaxOutputChars);
    finally
      ReleaseJob(Job);
    end;
end;

function TProcessRunner.Cancel(const AJobId: string): TProcessCancelResult;
var
  Job: TManagedProcessJob;
  SnapshotResult: TProcessRunResult;
begin
  Result.JobId := Trim(AJobId);
  Result.Found := False;
  Result.ProcessId := 0;
  Result.CancellationRequested := False;
  Result.TerminationAttempted := False;
  Result.TerminationSucceeded := False;
  if Result.JobId = '' then
    Exit;

  Job := AcquireJob(Result.JobId);
  if Job = nil then
    Exit;
  try
    Result.Found := True;
    Job.RequestCancel;
    Result.CancellationRequested := True;
    SnapshotResult := Job.Snapshot(0);
    Result.ProcessId := SnapshotResult.ProcessId;
    if SnapshotResult.Running and (SnapshotResult.ProcessId > 0) then
    begin
      Result.TerminationAttempted := True;
      Result.TerminationSucceeded :=
        TerminateProcessTree(SnapshotResult.ProcessId, True);
    end;
  finally
    ReleaseJob(Job);
  end;

  Log('', Format(
    'process cancel job_id=%s pid=%d attempted=%s succeeded=%s',
    [Result.JobId, Result.ProcessId,
     BoolToStr(Result.TerminationAttempted, True),
     BoolToStr(Result.TerminationSucceeded, True)]));
end;

end.
