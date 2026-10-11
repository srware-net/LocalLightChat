unit ServerConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TServerConfig = class
  public
    Address: string;
    Port: Word;
    Endpoint: string;
    BearerToken: string;
    WorkspaceRoot: string;
    FilesystemEnabled: Boolean;
    ProcessesEnabled: Boolean;
    AllowProcessExec: Boolean;
    AllowShellExec: Boolean;
    AllowProcessStart: Boolean;
    AllowShellStart: Boolean;
    AllowDelete: Boolean;
    DesktopEnabled: Boolean;
    DesktopWindowManagementEnabled: Boolean;
    DesktopCaptureEnabled: Boolean;
    DesktopInputEnabled: Boolean;
    DesktopMaximumImageBytes: Cardinal;
    DefaultTimeoutMs: Cardinal;
    MaximumTimeoutMs: Cardinal;
    DefaultProcessWaitMs: Cardinal;
    MaximumProcessWaitMs: Cardinal;
    MaximumTrackedJobs: Cardinal;
    DefaultIdleTimeoutMs: Cardinal;
    MaximumIdleTimeoutMs: Cardinal;
    TerminationGraceMs: Cardinal;
    DetachFromTerminal: Boolean;
    MaximumOutputBytes: Cardinal;
    MaximumRequestBytes: Cardinal;
    CorsEnabled: Boolean;
    AllowedOrigins: TStringList;
    LogFile: string;
    LogProcessCommands: Boolean;
    LogProcessOutput: Boolean;
    MirrorProcessOutputToConsole: Boolean;
    ProcessConsoleOutputMode: string;
    DetectInteractivePromptLoops: Boolean;
    InteractivePromptRepeatLimit: Cardinal;
    InteractivePromptWindowMs: Cardinal;
    InteractivePromptMaxChars: Cardinal;
    TerminalEnabled: Boolean;
    TerminalMaximumSessions: Cardinal;
    TerminalMaximumOutputBytes: Cardinal;
    TerminalMaximumReadBytes: Cardinal;
    TerminalMaximumObservationBytes: Cardinal;
    TerminalObservationQuietMs: Cardinal;
    TerminalObservationDefaultWaitMs: Cardinal;
    TerminalMaximumScrollbackLines: Cardinal;
    TerminalMaximumWriteBytes: Cardinal;
    TerminalDefaultColumns: Word;
    TerminalDefaultRows: Word;
    TerminalMaximumReadWaitMs: Cardinal;
    TerminalTerminationGraceMs: Cardinal;
    TerminalLogOutput: Boolean;
    TerminalLogInput: Boolean;
    TerminalMirrorOutputToConsole: Boolean;
    TerminalMirrorInputToConsole: Boolean;
    TerminalConsoleOutputMode: string;
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string);
  end;

implementation

uses
  fpjson, jsonparser, McpJson;

constructor TServerConfig.Create;
begin
  inherited Create;
  Address := '127.0.0.1';
  Port := 8765;
  Endpoint := '/mcp';
  BearerToken := 'change-me';
  WorkspaceRoot := ExpandFileName('workspace');
  FilesystemEnabled := True;
  ProcessesEnabled := True;
  AllowProcessExec := True;
  AllowShellExec := True;
  AllowProcessStart := True;
  AllowShellStart := True;
  AllowDelete := False;
  DesktopEnabled := False;
  DesktopWindowManagementEnabled := True;
  DesktopCaptureEnabled := True;
  DesktopInputEnabled := True;
  DesktopMaximumImageBytes := 16 * 1024 * 1024;
  DefaultTimeoutMs := 0;
  MaximumTimeoutMs := 0;
  DefaultProcessWaitMs := 3000;
  MaximumProcessWaitMs := 60000;
  MaximumTrackedJobs := 512;
  DefaultIdleTimeoutMs := 0;
  MaximumIdleTimeoutMs := 0;
  TerminationGraceMs := 2000;
  DetachFromTerminal := True;
  MaximumOutputBytes := 4 * 1024 * 1024;
  MaximumRequestBytes := 1024 * 1024;
  CorsEnabled := False;
  AllowedOrigins := TStringList.Create;
  AllowedOrigins.CaseSensitive := False;
  AllowedOrigins.Duplicates := dupIgnore;
  LogFile := 'mcp-server.log';
  LogProcessCommands := True;
  LogProcessOutput := True;
  MirrorProcessOutputToConsole := True;
  ProcessConsoleOutputMode := 'prefixed';
  DetectInteractivePromptLoops := True;
  InteractivePromptRepeatLimit := 12;
  InteractivePromptWindowMs := 2000;
  InteractivePromptMaxChars := 80;
  TerminalEnabled := False;
  TerminalMaximumSessions := 16;
  TerminalMaximumOutputBytes := 4 * 1024 * 1024;
  TerminalMaximumReadBytes := 6144;
  TerminalMaximumObservationBytes := 6144;
  TerminalObservationQuietMs := 500;
  TerminalObservationDefaultWaitMs := 3000;
  TerminalMaximumScrollbackLines := 2000;
  TerminalMaximumWriteBytes := 65536;
  TerminalDefaultColumns := 120;
  TerminalDefaultRows := 40;
  TerminalMaximumReadWaitMs := 60000;
  TerminalTerminationGraceMs := 2000;
  TerminalLogOutput := True;
  TerminalLogInput := False;
  TerminalMirrorOutputToConsole := True;
  TerminalMirrorInputToConsole := True;
  TerminalConsoleOutputMode := 'prefixed';
end;

destructor TServerConfig.Destroy;
begin
  AllowedOrigins.Free;
  inherited Destroy;
end;

function IsAbsoluteFileName(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and
    ((AFileName[1] = DirectorySeparator) or (AFileName[1] = '/') or
     (AFileName[1] = '\') or (ExtractFileDrive(AFileName) <> ''));
end;

function ResolveRelativeTo(const ABaseDirectory, AFileName: string): string;
begin
  if IsAbsoluteFileName(AFileName) then
    Result := ExpandFileName(AFileName)
  else
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ABaseDirectory) + AFileName);
end;

procedure TServerConfig.LoadFromFile(const AFileName: string);
var
  Source: TStringList;
  Root: TJSONData;
  Obj, Section: TJSONObject;
  Origins: TJSONArray;
  I: Integer;
  TimeoutValue: Int64;
  ConfigDirectory, ConfiguredPath, OriginValue: string;
begin
  if not FileExists(AFileName) then
    Exit;

  ConfigDirectory := ExtractFileDir(ExpandFileName(AFileName));
  Source := TStringList.Create;
  Root := nil;
  try
    Source.LoadFromFile(AFileName);
    Root := GetJSON(Source.Text);
    if Root.JSONType <> jtObject then
      raise Exception.Create('Configuration root must be a JSON object');
    Obj := TJSONObject(Root);

    Section := JsonObject(Obj, 'server');
    if Section <> nil then
    begin
      Address := JsonString(Section, 'address', Address);
      Port := Word(JsonInteger(Section, 'port', Port));
      Endpoint := JsonString(Section, 'endpoint', Endpoint);
      MaximumRequestBytes := Cardinal(JsonInteger(Section,
        'maximum_request_bytes', MaximumRequestBytes));
    end;

    Section := JsonObject(Obj, 'authentication');
    if Section <> nil then
      BearerToken := JsonString(Section, 'bearer_token', BearerToken);

    Section := JsonObject(Obj, 'cors');
    if Section <> nil then
    begin
      CorsEnabled := JsonBoolean(Section, 'enabled', CorsEnabled);
      Origins := JsonArray(Section, 'allowed_origins');
      if Origins <> nil then
      begin
        AllowedOrigins.Clear;
        for I := 0 to Origins.Count - 1 do
          if Origins.Items[I].JSONType = jtString then
          begin
            OriginValue := Trim(Origins.Items[I].AsString);
            while (Length(OriginValue) > 0) and
              (OriginValue[Length(OriginValue)] = '/') do
              Delete(OriginValue, Length(OriginValue), 1);
            if OriginValue <> '' then
              AllowedOrigins.Add(OriginValue);
          end;
      end;
    end;

    Section := JsonObject(Obj, 'filesystem');
    if Section <> nil then
    begin
      FilesystemEnabled := JsonBoolean(Section, 'enabled', FilesystemEnabled);
      ConfiguredPath := JsonString(Section, 'workspace_root', WorkspaceRoot);
      WorkspaceRoot := ResolveRelativeTo(ConfigDirectory, ConfiguredPath);
      AllowDelete := JsonBoolean(Section, 'allow_delete', AllowDelete);
    end;

    Section := JsonObject(Obj, 'processes');
    if Section <> nil then
    begin
      ProcessesEnabled := JsonBoolean(Section, 'enabled', ProcessesEnabled);
      AllowProcessExec := JsonBoolean(Section, 'allow_process_exec',
        AllowProcessExec);
      AllowShellExec := JsonBoolean(Section, 'allow_shell_exec', AllowShellExec);
      AllowProcessStart := JsonBoolean(Section, 'allow_process_start',
        AllowProcessStart);
      AllowShellStart := JsonBoolean(Section, 'allow_shell_start',
        AllowShellStart);
      TimeoutValue := JsonInteger(Section,
        'default_timeout_ms', DefaultTimeoutMs);
      if TimeoutValue < 0 then
        raise Exception.Create('processes.default_timeout_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.default_timeout_ms is too large');
      DefaultTimeoutMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_timeout_ms', MaximumTimeoutMs);
      if TimeoutValue < 0 then
        raise Exception.Create('processes.maximum_timeout_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.maximum_timeout_ms is too large');
      MaximumTimeoutMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'default_wait_ms', DefaultProcessWaitMs);
      if TimeoutValue < 0 then
        raise Exception.Create('processes.default_wait_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.default_wait_ms is too large');
      DefaultProcessWaitMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_wait_ms', MaximumProcessWaitMs);
      if TimeoutValue < 1 then
        raise Exception.Create('processes.maximum_wait_ms must be >= 1');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.maximum_wait_ms is too large');
      MaximumProcessWaitMs := Cardinal(TimeoutValue);
      if DefaultProcessWaitMs > MaximumProcessWaitMs then
        DefaultProcessWaitMs := MaximumProcessWaitMs;

      TimeoutValue := JsonInteger(Section,
        'maximum_tracked_jobs', MaximumTrackedJobs);
      if TimeoutValue < 8 then
        raise Exception.Create('processes.maximum_tracked_jobs must be >= 8');
      if TimeoutValue > High(Integer) then
        raise Exception.Create('processes.maximum_tracked_jobs is too large');
      MaximumTrackedJobs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'default_idle_timeout_ms', DefaultIdleTimeoutMs);
      if TimeoutValue < 0 then
        raise Exception.Create('processes.default_idle_timeout_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.default_idle_timeout_ms is too large');
      DefaultIdleTimeoutMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_idle_timeout_ms', MaximumIdleTimeoutMs);
      if TimeoutValue < 0 then
        raise Exception.Create('processes.maximum_idle_timeout_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.maximum_idle_timeout_ms is too large');
      MaximumIdleTimeoutMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'termination_grace_ms', TerminationGraceMs);
      if TimeoutValue < 0 then
        raise Exception.Create('processes.termination_grace_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.termination_grace_ms is too large');
      TerminationGraceMs := Cardinal(TimeoutValue);

      DetachFromTerminal := JsonBoolean(Section,
        'detach_from_terminal', DetachFromTerminal);

      TimeoutValue := JsonInteger(Section,
        'maximum_output_bytes', MaximumOutputBytes);
      if TimeoutValue < 1 then
        raise Exception.Create('processes.maximum_output_bytes must be >= 1');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('processes.maximum_output_bytes is too large');
      MaximumOutputBytes := Cardinal(TimeoutValue);

      MirrorProcessOutputToConsole := JsonBoolean(Section,
        'mirror_output_to_console', MirrorProcessOutputToConsole);
      ProcessConsoleOutputMode := LowerCase(Trim(JsonString(Section,
        'console_output_mode', ProcessConsoleOutputMode)));
      if (ProcessConsoleOutputMode <> 'raw') and
        (ProcessConsoleOutputMode <> 'prefixed') then
        raise Exception.Create(
          'processes.console_output_mode must be raw or prefixed');

      DetectInteractivePromptLoops := JsonBoolean(Section,
        'detect_interactive_prompt_loops', DetectInteractivePromptLoops);

      TimeoutValue := JsonInteger(Section,
        'interactive_prompt_repeat_limit', InteractivePromptRepeatLimit);
      if TimeoutValue < 3 then
        raise Exception.Create(
          'processes.interactive_prompt_repeat_limit must be >= 3');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create(
          'processes.interactive_prompt_repeat_limit is too large');
      InteractivePromptRepeatLimit := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'interactive_prompt_window_ms', InteractivePromptWindowMs);
      if TimeoutValue < 100 then
        raise Exception.Create(
          'processes.interactive_prompt_window_ms must be >= 100');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create(
          'processes.interactive_prompt_window_ms is too large');
      InteractivePromptWindowMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'interactive_prompt_max_chars', InteractivePromptMaxChars);
      if TimeoutValue < 4 then
        raise Exception.Create(
          'processes.interactive_prompt_max_chars must be >= 4');
      if TimeoutValue > 1024 then
        raise Exception.Create(
          'processes.interactive_prompt_max_chars must be <= 1024');
      InteractivePromptMaxChars := Cardinal(TimeoutValue);
    end;

    Section := JsonObject(Obj, 'terminal');
    if Section <> nil then
    begin
      TerminalEnabled := JsonBoolean(Section, 'enabled', TerminalEnabled);

      TimeoutValue := JsonInteger(Section,
        'maximum_sessions', TerminalMaximumSessions);
      if TimeoutValue < 1 then
        raise Exception.Create('terminal.maximum_sessions must be >= 1');
      if TimeoutValue > High(Integer) then
        raise Exception.Create('terminal.maximum_sessions is too large');
      TerminalMaximumSessions := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_output_bytes', TerminalMaximumOutputBytes);
      if TimeoutValue < 4096 then
        raise Exception.Create('terminal.maximum_output_bytes must be >= 4096');
      if TimeoutValue > High(Integer) then
        raise Exception.Create('terminal.maximum_output_bytes is too large');
      TerminalMaximumOutputBytes := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_read_bytes', TerminalMaximumReadBytes);
      if TimeoutValue < 1 then
        raise Exception.Create('terminal.maximum_read_bytes must be >= 1');
      if TimeoutValue > High(Integer) then
        raise Exception.Create('terminal.maximum_read_bytes is too large');
      TerminalMaximumReadBytes := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_observation_bytes', TerminalMaximumObservationBytes);
      if TimeoutValue < 256 then
        raise Exception.Create('terminal.maximum_observation_bytes must be >= 256');
      if TimeoutValue > High(Integer) then
        raise Exception.Create('terminal.maximum_observation_bytes is too large');
      TerminalMaximumObservationBytes := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'observation_quiet_ms', TerminalObservationQuietMs);
      if TimeoutValue < 0 then
        raise Exception.Create('terminal.observation_quiet_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('terminal.observation_quiet_ms is too large');
      TerminalObservationQuietMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'observation_default_wait_ms', TerminalObservationDefaultWaitMs);
      if TimeoutValue < 0 then
        raise Exception.Create('terminal.observation_default_wait_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('terminal.observation_default_wait_ms is too large');
      TerminalObservationDefaultWaitMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_scrollback_lines', TerminalMaximumScrollbackLines);
      if TimeoutValue < 0 then
        raise Exception.Create('terminal.maximum_scrollback_lines must be >= 0');
      if TimeoutValue > 1000000 then
        raise Exception.Create('terminal.maximum_scrollback_lines must be <= 1000000');
      TerminalMaximumScrollbackLines := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_write_bytes', TerminalMaximumWriteBytes);
      if TimeoutValue < 1 then
        raise Exception.Create('terminal.maximum_write_bytes must be >= 1');
      if TimeoutValue > High(Integer) then
        raise Exception.Create('terminal.maximum_write_bytes is too large');
      TerminalMaximumWriteBytes := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'default_columns', TerminalDefaultColumns);
      if (TimeoutValue < 1) or (TimeoutValue > 32767) then
        raise Exception.Create('terminal.default_columns must be 1..32767');
      TerminalDefaultColumns := Word(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'default_rows', TerminalDefaultRows);
      if (TimeoutValue < 1) or (TimeoutValue > 32767) then
        raise Exception.Create('terminal.default_rows must be 1..32767');
      TerminalDefaultRows := Word(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'maximum_read_wait_ms', TerminalMaximumReadWaitMs);
      if TimeoutValue < 1 then
        raise Exception.Create('terminal.maximum_read_wait_ms must be >= 1');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('terminal.maximum_read_wait_ms is too large');
      TerminalMaximumReadWaitMs := Cardinal(TimeoutValue);

      TimeoutValue := JsonInteger(Section,
        'termination_grace_ms', TerminalTerminationGraceMs);
      if TimeoutValue < 0 then
        raise Exception.Create('terminal.termination_grace_ms must be >= 0');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('terminal.termination_grace_ms is too large');
      TerminalTerminationGraceMs := Cardinal(TimeoutValue);

      TerminalLogOutput := JsonBoolean(Section, 'log_output',
        TerminalLogOutput);
      TerminalLogInput := JsonBoolean(Section, 'log_input',
        TerminalLogInput);
      TerminalMirrorOutputToConsole := JsonBoolean(Section,
        'mirror_output_to_console', TerminalMirrorOutputToConsole);
      TerminalMirrorInputToConsole := JsonBoolean(Section,
        'mirror_input_to_console', TerminalMirrorInputToConsole);
      TerminalConsoleOutputMode := LowerCase(Trim(JsonString(Section,
        'console_output_mode', TerminalConsoleOutputMode)));
      if (TerminalConsoleOutputMode <> 'raw') and
        (TerminalConsoleOutputMode <> 'prefixed') then
        raise Exception.Create(
          'terminal.console_output_mode must be raw or prefixed');
    end;

    Section := JsonObject(Obj, 'desktop');
    if Section <> nil then
    begin
      DesktopEnabled := JsonBoolean(Section, 'enabled', DesktopEnabled);
      TimeoutValue := JsonInteger(Section, 'maximum_image_bytes',
        DesktopMaximumImageBytes);
      if TimeoutValue < 32768 then
        raise Exception.Create('desktop.maximum_image_bytes must be >= 32768');
      if QWord(TimeoutValue) > High(Cardinal) then
        raise Exception.Create('desktop.maximum_image_bytes is too large');
      DesktopMaximumImageBytes := Cardinal(TimeoutValue);

      Section := JsonObject(Section, 'features');
      if Section <> nil then
      begin
        DesktopWindowManagementEnabled := JsonBoolean(Section, 'window_management',
          DesktopWindowManagementEnabled);
        DesktopCaptureEnabled := JsonBoolean(Section, 'screen_capture',
          DesktopCaptureEnabled);
        DesktopInputEnabled := JsonBoolean(Section, 'input',
          DesktopInputEnabled);
      end;
    end;

    Section := JsonObject(Obj, 'logging');
    if Section <> nil then
    begin
      ConfiguredPath := JsonString(Section, 'file', LogFile);
      if ConfiguredPath <> '' then
        LogFile := ResolveRelativeTo(ConfigDirectory, ConfiguredPath)
      else
        LogFile := '';
      LogProcessCommands := JsonBoolean(Section, 'log_process_commands',
        LogProcessCommands);
      LogProcessOutput := JsonBoolean(Section, 'log_process_output',
        LogProcessOutput);
    end;
  finally
    Root.Free;
    Source.Free;
  end;

  if Endpoint = '' then
    Endpoint := '/mcp';
  if Endpoint[1] <> '/' then
    Endpoint := '/' + Endpoint;
  ForceDirectories(WorkspaceRoot);
end;

end.
