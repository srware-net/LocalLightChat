unit TerminalToolProvider;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, ToolProvider, ServerConfig, ServerLog,
  FsTools, TerminalRunner, TerminalPtyBackend;

type
  TTerminalToolProvider = class(TToolProvider)
  private
    FConfig: TServerConfig;
    FFsTools: TFsTools;
    FRunner: TTerminalRunner;
    function SessionInfoToJson(const AInfo: TTerminalSessionInfo): TJSONObject;
    function ReadResultToJson(const AResult: TTerminalReadResult;
      AIncludeRaw: Boolean; const ACursorMode: string): TJSONObject;
    function ObserveResultToJson(const AResult: TTerminalObserveResult): TJSONObject;
    function ParseCardinal(AArguments: TJSONObject; const AName: string;
      ADefault, AMaximum: Cardinal): Cardinal;
    function ParseSequence(AArguments: TJSONObject;
      const AName: string; ADefault: QWord): QWord;
    function ParseDimension(AArguments: TJSONObject; const AName: string;
      ADefault: Word): Word;
    function ParseSignal(const AValue: string): TTerminalSignal;
  public
    constructor Create(AConfig: TServerConfig; ALogger: TServerLogger);
    destructor Destroy; override;
    procedure AddTools(ATools: TJSONArray); override;
    function HandlesTool(const AName: string): Boolean; override;
    function CallTool(const AName: string; AArguments: TJSONObject;
      const ACorrelationId: string): TJSONObject; override;
  end;

implementation

uses
  McpJson, McpProtocol, TerminalText, TerminalInput;

constructor TTerminalToolProvider.Create(AConfig: TServerConfig;
  ALogger: TServerLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FFsTools := TFsTools.Create(FConfig.WorkspaceRoot, False);
  FRunner := TTerminalRunner.Create(ALogger,
    FConfig.TerminalMaximumSessions,
    FConfig.TerminalMaximumOutputBytes,
    FConfig.TerminalMaximumScrollbackLines,
    FConfig.TerminalTerminationGraceMs,
    FConfig.TerminalLogOutput,
    FConfig.TerminalLogInput,
    FConfig.TerminalMirrorOutputToConsole,
    FConfig.TerminalMirrorInputToConsole,
    FConfig.TerminalConsoleOutputMode);
end;

destructor TTerminalToolProvider.Destroy;
begin
  FRunner.Free;
  FFsTools.Free;
  inherited Destroy;
end;

function TTerminalToolProvider.ParseCardinal(AArguments: TJSONObject;
  const AName: string; ADefault, AMaximum: Cardinal): Cardinal;
var
  Value: Int64;
begin
  if (AArguments = nil) or (AArguments.Find(AName) = nil) then
    Value := ADefault
  else
    Value := JsonInteger(AArguments, AName, ADefault);
  if Value < 0 then
    raise Exception.Create(AName + ' must be >= 0');
  if QWord(Value) > High(Cardinal) then
    raise Exception.Create(AName + ' is too large');
  Result := Cardinal(Value);
  if (AMaximum > 0) and (Result > AMaximum) then
    Result := AMaximum;
end;

function TTerminalToolProvider.ParseSequence(AArguments: TJSONObject;
  const AName: string; ADefault: QWord): QWord;
var
  Value: Int64;
begin
  if (AArguments = nil) or (AArguments.Find(AName) = nil) then
    Exit(ADefault);
  Value := JsonInteger(AArguments, AName, Int64(ADefault));
  if Value < 0 then
    raise Exception.Create(AName + ' must be >= 0');
  Result := QWord(Value);
end;

function TTerminalToolProvider.ParseDimension(AArguments: TJSONObject;
  const AName: string; ADefault: Word): Word;
var
  Value: Int64;
begin
  Value := JsonInteger(AArguments, AName, ADefault);
  if (Value < 1) or (Value > 32767) then
    raise Exception.Create(AName + ' must be between 1 and 32767');
  Result := Word(Value);
end;

function TTerminalToolProvider.ParseSignal(
  const AValue: string): TTerminalSignal;
var
  Value: string;
begin
  Value := LowerCase(Trim(AValue));
  if Value = 'interrupt' then
    Exit(tsInterrupt);
  if Value = 'eof' then
    Exit(tsEof);
  if Value = 'terminate' then
    Exit(tsTerminate);
  if Value = 'kill' then
    Exit(tsKill);
  raise Exception.Create(
    'signal must be interrupt, eof, terminate, or kill');
end;

function TTerminalToolProvider.SessionInfoToJson(
  const AInfo: TTerminalSessionInfo): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('session_id', AInfo.SessionId);
  Result.Add('process_id', AInfo.ProcessId);
  Result.Add('running', AInfo.Running);
  Result.Add('closing', AInfo.Closing);
  Result.Add('closed', AInfo.Closed);
  if AInfo.Running then
    Result.Add('exit_code', TJSONNull.Create)
  else
    Result.Add('exit_code', AInfo.ExitCode);
  Result.Add('columns', AInfo.Columns);
  Result.Add('rows', AInfo.Rows);
  Result.Add('buffer_start_seq', Int64(AInfo.BufferStartSeq));
  Result.Add('output_end_seq', Int64(AInfo.OutputEndSeq));
  Result.Add('read_cursor_seq', Int64(AInfo.ReadCursorSeq));
  Result.Add('output_dropped', AInfo.OutputDropped);
  Result.Add('screen_mode', AInfo.ScreenMode);
  Result.Add('screen_version', Int64(AInfo.ScreenVersion));
  Result.Add('scrollback_start_seq', Int64(AInfo.ScrollbackStartSeq));
  Result.Add('scrollback_next_seq', Int64(AInfo.ScrollbackNextSeq));
  Result.Add('application_cursor_keys', AInfo.ApplicationCursorKeys);
  Result.Add('capture_limit_bytes', Int64(FConfig.TerminalMaximumOutputBytes));
  if AInfo.ErrorMessage <> '' then
    Result.Add('error', AInfo.ErrorMessage);
end;

function TTerminalToolProvider.ReadResultToJson(
  const AResult: TTerminalReadResult; AIncludeRaw: Boolean;
  const ACursorMode: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('session_id', AResult.Info.SessionId);
  Result.Add('process_id', AResult.Info.ProcessId);
  Result.Add('running', AResult.Info.Running);
  Result.Add('closing', AResult.Info.Closing);
  Result.Add('closed', AResult.Info.Closed);
  if AResult.Info.Running then
    Result.Add('exit_code', TJSONNull.Create)
  else
    Result.Add('exit_code', AResult.Info.ExitCode);
  Result.Add('columns', AResult.Info.Columns);
  Result.Add('rows', AResult.Info.Rows);
  Result.Add('buffer_start_seq', Int64(AResult.Info.BufferStartSeq));
  Result.Add('from_seq', Int64(AResult.FromSeq));
  Result.Add('next_seq', Int64(AResult.NextSeq));
  Result.Add('read_cursor_seq', Int64(AResult.Info.ReadCursorSeq));
  Result.Add('output_end_seq', Int64(AResult.OutputEndSeq));
  Result.Add('returned_bytes', Length(AResult.OutputText));
  Result.Add('cursor_mode', ACursorMode);
  { Normal agent reads already carry the terminal text in content[].text.
    Duplicating the same bytes here can double MCP context size, so raw PTY
    output is opt-in only for diagnostics or clients that truly need VT data. }
  if AIncludeRaw then
    Result.Add('output', string(AResult.OutputText));
  Result.Add('raw_included', AIncludeRaw);
  Result.Add('more_available', AResult.MoreAvailable);
  Result.Add('missed_output', AResult.MissedOutput);
  Result.Add('wait_timed_out', AResult.WaitTimedOut);
  Result.Add('output_dropped', AResult.Info.OutputDropped);
  Result.Add('application_cursor_keys', AResult.Info.ApplicationCursorKeys);
  Result.Add('capture_limit_bytes', Int64(FConfig.TerminalMaximumOutputBytes));
  if AResult.Info.ErrorMessage <> '' then
    Result.Add('error', AResult.Info.ErrorMessage);
end;


function TTerminalToolProvider.ObserveResultToJson(
  const AResult: TTerminalObserveResult): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('session_id', AResult.Info.SessionId);
  Result.Add('process_id', AResult.Info.ProcessId);
  Result.Add('running', AResult.Info.Running);
  Result.Add('closing', AResult.Info.Closing);
  Result.Add('closed', AResult.Info.Closed);
  if AResult.Info.Running then
    Result.Add('exit_code', TJSONNull.Create)
  else
    Result.Add('exit_code', AResult.Info.ExitCode);
  Result.Add('screen_mode', AResult.Info.ScreenMode);
  Result.Add('screen_version', Int64(AResult.ScreenVersion));
  Result.Add('changed', AResult.Changed);
  Result.Add('quiet', AResult.Quiet);
  Result.Add('wait_timed_out', AResult.WaitTimedOut);
  Result.Add('raw_bytes_processed', Int64(AResult.RawBytesProcessed));
  Result.Add('raw_bytes_since_observation', Int64(AResult.RawBytesSinceLast));
  Result.Add('rendered_bytes', Int64(AResult.RenderedBytes));
  Result.Add('omitted_bytes', Int64(AResult.OmittedBytes));
  Result.Add('scrollback_from_seq', Int64(AResult.ScrollbackFromSeq));
  Result.Add('scrollback_next_seq', Int64(AResult.ScrollbackNextSeq));
  Result.Add('scrollback_missed', AResult.ScrollbackMissed);
  Result.Add('maximum_observation_bytes',
    Int64(FConfig.TerminalMaximumObservationBytes));
  Result.Add('application_cursor_keys', AResult.Info.ApplicationCursorKeys);
  if AResult.Info.ErrorMessage <> '' then
    Result.Add('error', AResult.Info.ErrorMessage);
end;

procedure TTerminalToolProvider.AddTools(ATools: TJSONArray);
var
  Props: TJSONObject;
begin
  Props := TJSONObject.Create;
  Props.Add('executable', StringProperty(
    'Executable name or full path, for example ssh, ssh.exe, bash, pwsh.exe, or powershell.exe'));
  Props.Add('arguments', ArrayProperty(StringProperty('One process argument')));
  Props.Add('cwd', StringProperty('Working directory inside the workspace'));
  Props.Add('session_id', StringProperty(
    'Optional client-generated terminal session ID; normally omit'));
  Props.Add('columns', IntegerProperty(FConfig.TerminalDefaultColumns,
    1, 32767, 'Initial PTY width in character cells'));
  Props.Add('rows', IntegerProperty(FConfig.TerminalDefaultRows,
    1, 32767, 'Initial PTY height in character cells'));
  ATools.Add(BuildTool('terminal_open',
    'Open a persistent interactive terminal attached to a real PTY on Linux or ConPTY on Windows. Use this for ssh, sudo-capable remote shells, REPLs, and programs that require a terminal. Input remains open until terminal_close or process exit. Use terminal_observe for normal agent monitoring; it renders VT screen state and coalesces repaints instead of making the model drain raw PTY history. Do not reopen the same command for each turn.',
    ObjectSchema(Props, ['executable'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  Props.Add('wait_ms', IntegerProperty(FConfig.TerminalObservationDefaultWaitMs, 0,
    FConfig.TerminalMaximumReadWaitMs,
    'Maximum wait for a useful rendered observation. If output keeps repainting continuously, the current screen is returned when this timeout is reached.'));
  Props.Add('quiet_ms', IntegerProperty(FConfig.TerminalObservationQuietMs, 0,
    FConfig.TerminalMaximumReadWaitMs,
    'Return once terminal output has been quiet for this many milliseconds. This coalesces short bursts and rapid progress redraws.'));
  Props.Add('max_bytes', IntegerProperty(FConfig.TerminalMaximumObservationBytes,
    256, FConfig.TerminalMaximumObservationBytes,
    'Maximum rendered UTF-8 bytes returned to the model. Older rendered content is coalesced/omitted rather than queued for later draining.'));
  ATools.Add(BuildTool('terminal_observe',
    'Primary agent observation tool for interactive terminals. It interprets VT/ANSI cursor movement, erasing, scrolling, and alternate-screen TUIs, then returns what a terminal user can currently perceive rather than raw repaint bytes. It waits for a short quiet period or wait_ms timeout and always coalesces to the newest rendered state, so there is no historical byte backlog to drain. Use this after terminal_open/terminal_write for SSH, sudo, shells, top/htop, less, editors, and REPLs. Do not follow it with repeated terminal_read calls just because raw bytes exist.',
    ObjectSchema(Props, ['session_id'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  Props.Add('after_seq', IntegerRangeProperty(0, High(Int64),
    'Optional replay/debug override. Normally omit this field: the server remembers the last delivered byte position for the session. If supplied, reading starts at this explicit byte sequence offset and subsequent automatic reads continue from there.'));
  Props.Add('wait_ms', IntegerProperty(1000, 0,
    FConfig.TerminalMaximumReadWaitMs,
    'Wait up to this many milliseconds for new terminal output. 0 returns immediately.'));
  Props.Add('max_bytes', IntegerProperty(
    FConfig.TerminalMaximumReadBytes, 1,
    FConfig.TerminalMaximumReadBytes,
    'Maximum terminal output bytes returned by this call. The server configuration sets the hard upper bound.'));
  Props.Add('include_raw', BooleanProperty(False,
    'Include the raw PTY bytes in structuredContent.output as well as the normal visible MCP text. Normally keep false because this duplicates terminal output and increases model context; enable only for VT/ANSI diagnostics.'));
  ATools.Add(BuildTool('terminal_read',
    'Raw transcript/debug reader. This exposes incremental PTY bytes and can contain repeated VT screen repaints. Normal agents should use terminal_observe instead; do not drain terminal_read during ordinary SSH/sudo/TUI workflows. after_seq is an explicit replay/debug override and include_raw is for diagnostics.',
    ObjectSchema(Props, ['session_id'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  Props.Add('data', StringProperty(
    'Text to type into the terminal exactly. Do not send literal backslash-n or backslash-r to press Enter; use press_enter=true instead. Do not encode Ctrl/Alt shortcuts as \xNN or \uNNNN strings; use terminal_key for control keys, arrows, navigation and function keys. Actual CR/LF characters already present in data are still preserved.'));
  Props.Add('press_enter', BooleanProperty(False,
    'Press Enter after data. Prefer this instead of encoding \n or \r in data; the server appends a real terminal Enter byte. To press Enter without typing text, use data="" and press_enter=true.'));
  Props.Add('sensitive', BooleanProperty(False,
    'Set true for passwords, SSH key passphrases, tokens, sudo passwords, or other secrets. Sensitive input is sent normally but hidden from MCP response text, structuredContent, server console mirroring, and terminal input logs.'));
  ATools.Add(BuildTool('terminal_write',
    'Type UTF-8 text into an existing interactive terminal. For commands, SSH passwords, sudo passwords, and normal prompt submission, set press_enter=true instead of embedding \n or \r escapes in data. For Ctrl/Alt shortcuts, Escape, Tab, arrows, Home/End, PageUp/PageDown and function keys use terminal_key; never type strings such as \x0f or \u000f hoping they become control bytes. Non-sensitive input is echoed in the MCP result. Set sensitive=true for passwords, passphrases, tokens, sudo credentials, and other secrets.',
    ObjectSchema(Props, ['session_id', 'data'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  Props.Add('key', StringProperty(
    'One semantic terminal key: enter, escape, tab, backspace, insert, delete, up/down/left/right, home/end, pageup/pagedown, F1..F24, space, or one printable ASCII character. Nano-style ^O and M-U plus Ctrl+O shorthand are also accepted, but explicit modifier booleans are preferred.'));
  Props.Add('ctrl', BooleanProperty(False,
    'Hold the terminal Ctrl modifier while sending key. Example: key="o", ctrl=true sends byte 0x0F for Nano Write Out.'));
  Props.Add('alt', BooleanProperty(False,
    'Hold the terminal Alt/Meta modifier while sending key. Printable Alt keys are encoded with an ESC prefix; special keys use xterm modifier sequences.'));
  Props.Add('shift', BooleanProperty(False,
    'Hold Shift while sending key. Shift+Tab and modified cursor/function keys use standard VT/xterm sequences.'));
  ATools.Add(BuildTool('terminal_key',
    'Send one semantic key or key combination to an existing PTY/ConPTY session. Use this for TUI/editor shortcuts such as Ctrl+O and Ctrl+X, Escape, arrows, Home/End, PageUp/PageDown, Shift+Tab and F1..F24. This tool emits terminal bytes/VT sequences, not desktop key-down/key-up events, so there is no state=press/up parameter. Prefer key="o", ctrl=true over embedding control-byte escape text in terminal_write. Cursor keys automatically follow the application-cursor mode requested by TUIs when possible.',
    ObjectSchema(Props, ['session_id', 'key'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  Props.Add('columns', IntegerRangeProperty(1, 32767,
    'New PTY width in character cells'));
  Props.Add('rows', IntegerRangeProperty(1, 32767,
    'New PTY height in character cells'));
  ATools.Add(BuildTool('terminal_resize',
    'Resize an existing PTY/ConPTY session.',
    ObjectSchema(Props, ['session_id', 'columns', 'rows'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  Props.Add('signal', StringProperty(
    'interrupt sends Ctrl-C, eof sends Ctrl-D, terminate requests termination, kill forces teardown'));
  ATools.Add(BuildTool('terminal_signal',
    'Send a terminal control action. interrupt and eof are delivered through the PTY input channel so terminal-aware programs receive normal Ctrl-C/Ctrl-D semantics.',
    ObjectSchema(Props, ['session_id', 'signal'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  ATools.Add(BuildTool('terminal_status',
    'Return terminal session state and output cursor positions without consuming output.',
    ObjectSchema(Props, ['session_id'])));

  Props := TJSONObject.Create;
  Props.Add('session_id', StringProperty('Terminal session ID'));
  ATools.Add(BuildTool('terminal_close',
    'Close the PTY/ConPTY and terminate attached terminal processes. Buffered output remains queryable until the completed session is pruned to make room for a new session.',
    ObjectSchema(Props, ['session_id'])));
end;

function TTerminalToolProvider.HandlesTool(const AName: string): Boolean;
begin
  Result := (AName = 'terminal_open') or
    (AName = 'terminal_observe') or
    (AName = 'terminal_read') or
    (AName = 'terminal_write') or
    (AName = 'terminal_key') or
    (AName = 'terminal_resize') or
    (AName = 'terminal_signal') or
    (AName = 'terminal_status') or
    (AName = 'terminal_close');
end;

function TTerminalToolProvider.CallTool(const AName: string;
  AArguments: TJSONObject; const ACorrelationId: string): TJSONObject;
var
  Info: TTerminalSessionInfo;
  ReadResult: TTerminalReadResult;
  ObserveResult: TTerminalObserveResult;
  KeyResult: TTerminalKeyWriteResult;
  Structured: TJSONObject;
  Arguments: TJSONArray;
  SessionId, ExecutableName, Cwd, SignalName, KeyName: string;
  Data: UTF8String;
  Columns, Rows: Word;
  AfterSeq: QWord;
  WaitMs, QuietMs, MaxBytes: Cardinal;
  Written: Integer;
  Sensitive, PressEnter, IncludeRaw, HasAfterSeq: Boolean;
  CtrlKey, AltKey, ShiftKey: Boolean;
  DisplayText, CursorMode: string;
  WriteData: RawByteString;
begin
  SessionId := JsonString(AArguments, 'session_id');

  if AName = 'terminal_open' then
  begin
    ExecutableName := JsonString(AArguments, 'executable');
    if Trim(ExecutableName) = '' then
      raise Exception.Create('executable must not be empty');
    Cwd := FFsTools.ResolvePath(JsonString(AArguments, 'cwd', '.'));
    Columns := ParseDimension(AArguments, 'columns',
      FConfig.TerminalDefaultColumns);
    Rows := ParseDimension(AArguments, 'rows', FConfig.TerminalDefaultRows);
    Arguments := JsonArray(AArguments, 'arguments');
    Info := FRunner.Open(ExecutableName, Arguments, Cwd, SessionId,
      ACorrelationId, Columns, Rows);
    Structured := SessionInfoToJson(Info);
    Exit(NewToolTextResult(Format(
      'INTERACTIVE TERMINAL OPENED AS %s (PID %d). Continue with terminal_observe and terminal_write; do not start the command again. terminal_read is raw/debug only.',
      [Info.SessionId, Info.ProcessId]), Structured, False));
  end;

  if Trim(SessionId) = '' then
    raise Exception.Create('session_id must not be empty');

  if AName = 'terminal_observe' then
  begin
    WaitMs := ParseCardinal(AArguments, 'wait_ms',
      FConfig.TerminalObservationDefaultWaitMs,
      FConfig.TerminalMaximumReadWaitMs);
    QuietMs := ParseCardinal(AArguments, 'quiet_ms',
      FConfig.TerminalObservationQuietMs,
      FConfig.TerminalMaximumReadWaitMs);
    MaxBytes := ParseCardinal(AArguments, 'max_bytes',
      FConfig.TerminalMaximumObservationBytes,
      FConfig.TerminalMaximumObservationBytes);
    if MaxBytes < 256 then MaxBytes := 256;

    ObserveResult := FRunner.Observe(SessionId, WaitMs, QuietMs, MaxBytes);
    Structured := ObserveResultToJson(ObserveResult);
    DisplayText := string(ObserveResult.OutputText);
    if DisplayText <> '' then
    begin
      if ObserveResult.AlternateScreen then
        CursorMode := 'alternate-screen'
      else
        CursorMode := 'normal-screen';
      DisplayText := Format(
        'TERMINAL OBSERVATION [%s] (%s, quiet=%s):%s%s',
        [SessionId, CursorMode, LowerCase(BoolToStr(ObserveResult.Quiet, True)),
         LineEnding, DisplayText]);
      Exit(NewToolTextResult(DisplayText, Structured,
        ObserveResult.Info.ErrorMessage <> ''));
    end;

    if ObserveResult.Info.Running then
      Exit(NewToolTextResult(Format(
        'TERMINAL OBSERVATION [%s]: no new visible terminal change; session remains open (quiet=%s).',
        [SessionId, LowerCase(BoolToStr(ObserveResult.Quiet, True))]),
        Structured, False))
    else
      Exit(NewToolTextResult(Format(
        'TERMINAL OBSERVATION [%s]: no further visible output; process is no longer running (exit_code=%d).',
        [SessionId, ObserveResult.Info.ExitCode]), Structured,
        ObserveResult.Info.ErrorMessage <> ''));
  end;

  if AName = 'terminal_read' then
  begin
    HasAfterSeq := (AArguments <> nil) and
      (AArguments.Find('after_seq') <> nil);
    WaitMs := ParseCardinal(AArguments, 'wait_ms', 1000,
      FConfig.TerminalMaximumReadWaitMs);
    MaxBytes := ParseCardinal(AArguments, 'max_bytes',
      FConfig.TerminalMaximumReadBytes,
      FConfig.TerminalMaximumReadBytes);
    if MaxBytes = 0 then
      MaxBytes := FConfig.TerminalMaximumReadBytes;
    IncludeRaw := JsonBoolean(AArguments, 'include_raw', False);

    if HasAfterSeq then
    begin
      AfterSeq := ParseSequence(AArguments, 'after_seq', 0);
      ReadResult := FRunner.Read(SessionId, AfterSeq, WaitMs, MaxBytes);
      CursorMode := 'override';
    end
    else
    begin
      ReadResult := FRunner.ReadNext(SessionId, WaitMs, MaxBytes);
      CursorMode := 'server';
    end;

    Structured := ReadResultToJson(ReadResult, IncludeRaw, CursorMode);
    DisplayText := TerminalOutputForMcpText(
      RawByteString(ReadResult.OutputText));
    if DisplayText <> '' then
    begin
      if ReadResult.Info.Running then
        DisplayText := Format('TERMINAL OUTPUT [%s]:%s%s',
          [SessionId, LineEnding, DisplayText])
      else
        DisplayText := Format(
          'TERMINAL OUTPUT [%s] (process exited):%s%s',
          [SessionId, LineEnding, DisplayText]);
      if ReadResult.MoreAvailable then
        DisplayText := DisplayText + LineEnding +
          '[raw debug transcript has more bytes; normal agents should use terminal_observe instead of draining this backlog]';
      Exit(NewToolTextResult(DisplayText, Structured,
        ReadResult.Info.ErrorMessage <> ''));
    end;

    if ReadResult.Info.Running then
      Exit(NewToolTextResult(Format(
        'TERMINAL [%s]: no new output yet; session remains open.',
        [SessionId]), Structured, False))
    else
      Exit(NewToolTextResult(Format(
        'TERMINAL [%s]: no further output; process is no longer running (exit_code=%d).',
        [SessionId, ReadResult.Info.ExitCode]), Structured,
        ReadResult.Info.ErrorMessage <> ''));
  end;

  if AName = 'terminal_write' then
  begin
    Data := JsonUtf8String(AArguments, 'data');
    PressEnter := JsonBoolean(AArguments, 'press_enter', False);
    WriteData := BuildTerminalInput(Data, PressEnter);
    if Length(WriteData) > Integer(FConfig.TerminalMaximumWriteBytes) then
      raise Exception.CreateFmt('terminal_write data exceeds %d bytes including press_enter',
        [FConfig.TerminalMaximumWriteBytes]);
    Sensitive := JsonBoolean(AArguments, 'sensitive', False);
    Written := FRunner.Write(SessionId, WriteData, Sensitive);
    Structured := TJSONObject.Create;
    Structured.Add('session_id', SessionId);
    Structured.Add('bytes_written', Written);
    Structured.Add('sensitive', Sensitive);
    Structured.Add('press_enter', PressEnter);
    if Sensitive then
      DisplayText := Format(
        'TERMINAL INPUT [%s]: %d sensitive bytes sent (content hidden).',
        [SessionId, Written])
    else
    begin
      Structured.Add('input', string(Copy(WriteData, 1, Written)));
      DisplayText := TerminalInputForMcpText(
        Copy(WriteData, 1, Written));
      if DisplayText = '' then
        DisplayText := '<empty input>';
      DisplayText := Format('TERMINAL INPUT [%s] (%d bytes):%s%s',
        [SessionId, Written, LineEnding, DisplayText]);
    end;
    Exit(NewToolTextResult(DisplayText, Structured, False));
  end;

  if AName = 'terminal_key' then
  begin
    KeyName := JsonString(AArguments, 'key');
    if Trim(KeyName) = '' then
      raise Exception.Create('key must not be empty');
    CtrlKey := JsonBoolean(AArguments, 'ctrl', False);
    AltKey := JsonBoolean(AArguments, 'alt', False);
    ShiftKey := JsonBoolean(AArguments, 'shift', False);
    KeyResult := FRunner.WriteKey(SessionId, KeyName, CtrlKey, AltKey, ShiftKey);

    Structured := TJSONObject.Create;
    Structured.Add('session_id', SessionId);
    Structured.Add('key', KeyResult.Encoding.CanonicalKey);
    Structured.Add('display_key', KeyResult.Encoding.DisplayName);
    Structured.Add('ctrl', KeyResult.Encoding.Ctrl);
    Structured.Add('alt', KeyResult.Encoding.Alt);
    Structured.Add('shift', KeyResult.Encoding.Shift);
    Structured.Add('bytes_written', KeyResult.BytesWritten);
    Structured.Add('application_cursor_keys', KeyResult.ApplicationCursorKeys);
    DisplayText := Format('TERMINAL KEY [%s]: %s (%d bytes sent).',
      [SessionId, KeyResult.Encoding.DisplayName, KeyResult.BytesWritten]);
    Exit(NewToolTextResult(DisplayText, Structured, False));
  end;

  if AName = 'terminal_resize' then
  begin
    Columns := ParseDimension(AArguments, 'columns',
      FConfig.TerminalDefaultColumns);
    Rows := ParseDimension(AArguments, 'rows', FConfig.TerminalDefaultRows);
    Info := FRunner.Resize(SessionId, Columns, Rows);
    Exit(NewToolTextResult('Terminal resized.', SessionInfoToJson(Info), False));
  end;

  if AName = 'terminal_signal' then
  begin
    SignalName := JsonString(AArguments, 'signal');
    Info := FRunner.Signal(SessionId, ParseSignal(SignalName));
    Exit(NewToolTextResult('Terminal control action sent.',
      SessionInfoToJson(Info), False));
  end;

  if AName = 'terminal_status' then
  begin
    Info := FRunner.Status(SessionId);
    Exit(NewToolTextResult('Terminal session state returned.',
      SessionInfoToJson(Info), Info.ErrorMessage <> ''));
  end;

  if AName = 'terminal_close' then
  begin
    Info := FRunner.Close(SessionId);
    Exit(NewToolTextResult('Terminal session closed.',
      SessionInfoToJson(Info), Info.ErrorMessage <> ''));
  end;

  raise Exception.CreateFmt('Unknown terminal tool: %s', [AName]);
end;

end.
