unit ProcessToolProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, ToolProvider, ServerConfig, ServerLog, FsTools,
  ProcessRunner;

type
  TProcessToolProvider = class(TToolProvider)
  private
    FConfig: TServerConfig;
    FFsTools: TFsTools;
    FProcessRunner: TProcessRunner;
    function ProcessResultToJson(const AResult: TProcessRunResult;
      AIncludeOutput: Boolean): TJSONObject;
    function TimeoutProperty(ADefault, AMaximum: Cardinal;
      const ADescription: string): TJSONObject;
    function WaitProperty(ADefault, AMaximum: Cardinal): TJSONObject;
    function OutputCharsProperty: TJSONObject;
    function ParseCardinal(AArguments: TJSONObject; const AName: string;
      ADefault, AMaximum: Cardinal): Cardinal;
    function AnyProcessToolEnabled: Boolean;
    function ResultText(const AResult: TProcessRunResult): string;
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
  McpJson, McpProtocol;

constructor TProcessToolProvider.Create(AConfig: TServerConfig;
  ALogger: TServerLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FFsTools := TFsTools.Create(FConfig.WorkspaceRoot, False);
  FProcessRunner := TProcessRunner.Create(ALogger,
    FConfig.LogProcessCommands, FConfig.LogProcessOutput,
    FConfig.MirrorProcessOutputToConsole, FConfig.DetachFromTerminal,
    FConfig.ProcessConsoleOutputMode, FConfig.TerminationGraceMs,
    FConfig.MaximumTrackedJobs, FConfig.DetectInteractivePromptLoops,
    FConfig.InteractivePromptRepeatLimit,
    FConfig.InteractivePromptWindowMs,
    FConfig.InteractivePromptMaxChars);
end;

destructor TProcessToolProvider.Destroy;
begin
  FProcessRunner.Free;
  FFsTools.Free;
  inherited Destroy;
end;

function TProcessToolProvider.AnyProcessToolEnabled: Boolean;
begin
  Result := FConfig.AllowProcessExec or FConfig.AllowShellExec or
    FConfig.AllowProcessStart or FConfig.AllowShellStart;
end;

function TProcessToolProvider.TimeoutProperty(ADefault,
  AMaximum: Cardinal; const ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'integer');
  Result.Add('default', Int64(ADefault));
  Result.Add('minimum', 0);
  if AMaximum > 0 then
    Result.Add('maximum', Int64(AMaximum));
  Result.Add('description', ADescription);
end;

function TProcessToolProvider.WaitProperty(ADefault,
  AMaximum: Cardinal): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'integer');
  Result.Add('default', Int64(ADefault));
  Result.Add('minimum', 0);
  Result.Add('maximum', Int64(AMaximum));
  Result.Add('description',
    'How long this HTTP tool call may wait for completion. This is not a process timeout. If the process is still running, it continues as a managed background job and the tool returns its job_id.');
end;

function TProcessToolProvider.OutputCharsProperty: TJSONObject;
begin
  Result := IntegerProperty(0, 0, 100000,
    'Maximum stdout and stderr characters returned by this response. 0 returns the complete output still captured by the server. A positive value explicitly requests only the newest tail.');
end;

function TProcessToolProvider.ParseCardinal(AArguments: TJSONObject;
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

procedure TProcessToolProvider.AddTools(ATools: TJSONArray);
var
  Props: TJSONObject;
begin
  if FConfig.AllowProcessExec then
  begin
    Props := TJSONObject.Create;
    Props.Add('executable', StringProperty('Executable name or full path'));
    Props.Add('arguments', ArrayProperty(StringProperty('One process argument')));
    Props.Add('cwd', StringProperty('Working directory inside the workspace'));
    Props.Add('stdin', StringProperty('Optional standard input supplied once; stdin is then closed'));
    Props.Add('job_id', StringProperty('Optional client-generated job ID; normally omit'));
    Props.Add('wait_ms', WaitProperty(FConfig.DefaultProcessWaitMs,
      FConfig.MaximumProcessWaitMs));
    Props.Add('timeout_ms', TimeoutProperty(FConfig.DefaultTimeoutMs,
      FConfig.MaximumTimeoutMs,
      'Maximum process lifetime in milliseconds. 0 means unlimited. This is separate from wait_ms.'));
    Props.Add('idle_timeout_ms', TimeoutProperty(FConfig.DefaultIdleTimeoutMs,
      FConfig.MaximumIdleTimeoutMs,
      'Maximum milliseconds without stdout or stderr. 0 disables the idle timeout.'));
    Props.Add('interactive_guard', BooleanProperty(FConfig.DetectInteractivePromptLoops,
      'Stop this finite command when a short interactive prompt is emitted repeatedly after stdin has been closed. Disable only for a known noninteractive command that intentionally prints repeated prompt-like lines.'));
    ATools.Add(BuildTool('process_exec',
      'Run a direct executable expected to finish and not request further interactive input. stdin is closed after optional startup input. Never use this for GUI applications, servers, watchers, services, daemons, or REPL sessions; use process_start instead. The HTTP call waits only wait_ms. A longer process continues under the returned job_id; do not start it again, use process_wait or process_status.',
      ObjectSchema(Props, ['executable'])));
  end;

  if FConfig.AllowShellExec then
  begin
    Props := TJSONObject.Create;
    Props.Add('command', StringProperty('Complete shell command'));
    Props.Add('shell', StringProperty('auto, cmd, powershell, pwsh, sh, or bash'));
    Props.Add('cwd', StringProperty('Working directory inside the workspace'));
    Props.Add('stdin', StringProperty('Optional standard input supplied once; stdin is then closed'));
    Props.Add('job_id', StringProperty('Optional client-generated job ID; normally omit'));
    Props.Add('wait_ms', WaitProperty(FConfig.DefaultProcessWaitMs,
      FConfig.MaximumProcessWaitMs));
    Props.Add('timeout_ms', TimeoutProperty(FConfig.DefaultTimeoutMs,
      FConfig.MaximumTimeoutMs,
      'Maximum process lifetime in milliseconds. 0 means unlimited. This is separate from wait_ms.'));
    Props.Add('idle_timeout_ms', TimeoutProperty(FConfig.DefaultIdleTimeoutMs,
      FConfig.MaximumIdleTimeoutMs,
      'Maximum milliseconds without stdout or stderr. 0 disables the idle timeout.'));
    Props.Add('interactive_guard', BooleanProperty(FConfig.DetectInteractivePromptLoops,
      'Stop this finite command when a short interactive prompt is emitted repeatedly after stdin has been closed. Disable only for a known noninteractive command that intentionally prints repeated prompt-like lines.'));
    ATools.Add(BuildTool('shell_exec',
      'Run a noninteractive shell command expected to finish. stdin is closed after optional startup input. Commands that can enter a REPL or chat prompt must be given batch or single-turn flags. Never use this for a persistent web server, watcher, service, daemon, or interactive shell; use shell_start instead. The HTTP call waits only wait_ms. A longer command continues under the returned job_id; do not run it again, use process_wait or process_status.',
      ObjectSchema(Props, ['command'])));
  end;

  if FConfig.AllowProcessStart then
  begin
    Props := TJSONObject.Create;
    Props.Add('executable', StringProperty('Executable name or full path'));
    Props.Add('arguments', ArrayProperty(StringProperty('One process argument')));
    Props.Add('cwd', StringProperty('Working directory inside the workspace'));
    Props.Add('stdin', StringProperty('Optional startup input supplied once; stdin is then closed'));
    Props.Add('job_id', StringProperty('Optional client-generated job ID; normally omit'));
    Props.Add('hidden', BooleanProperty(False,
      'Windows only: request a hidden window. Keep false for GUI applications such as Notepad.'));
    Props.Add('timeout_ms', TimeoutProperty(0,
      FConfig.MaximumTimeoutMs,
      'Optional maximum process lifetime. 0 means unlimited.'));
    Props.Add('idle_timeout_ms', TimeoutProperty(0,
      FConfig.MaximumIdleTimeoutMs,
      'Optional idle timeout. 0 means unlimited and is recommended for GUI applications and persistent servers.'));
    ATools.Add(BuildTool('process_start',
      'Start a direct executable and return immediately. Use this for GUI applications and long-running direct programs. The process is managed by job_id; use process_status, process_wait, or process_cancel. Do not use shell background syntax, nohup, or ampersand here.',
      ObjectSchema(Props, ['executable'])));
  end;

  if FConfig.AllowShellStart then
  begin
    Props := TJSONObject.Create;
    Props.Add('command', StringProperty('Complete shell command to start'));
    Props.Add('shell', StringProperty('auto, cmd, powershell, pwsh, sh, or bash'));
    Props.Add('cwd', StringProperty('Working directory inside the workspace'));
    Props.Add('stdin', StringProperty('Optional startup input supplied once; stdin is then closed'));
    Props.Add('job_id', StringProperty('Optional client-generated job ID; normally omit'));
    Props.Add('timeout_ms', TimeoutProperty(0,
      FConfig.MaximumTimeoutMs,
      'Optional maximum process lifetime. 0 means unlimited.'));
    Props.Add('idle_timeout_ms', TimeoutProperty(0,
      FConfig.MaximumIdleTimeoutMs,
      'Optional idle timeout. 0 means unlimited and is recommended for persistent servers and watchers.'));
    ATools.Add(BuildTool('shell_start',
      'Start a persistent shell command and return immediately. Use this for web servers, watchers, services, and daemons. Do not append nohup, ampersand, start, or other shell-detach syntax; this tool already manages the process and captures its output.',
      ObjectSchema(Props, ['command'])));
  end;

  if AnyProcessToolEnabled then
  begin
    Props := TJSONObject.Create;
    Props.Add('job_id', StringProperty('Job ID returned by a process tool'));
    Props.Add('include_output', BooleanProperty(True,
      'Include stdout and stderr. With max_output_chars=0 the complete server-captured output is returned.'));
    Props.Add('max_output_chars', OutputCharsProperty);
    ATools.Add(BuildTool('process_status',
      'Read the current state of a managed process job without waiting. Do not restart a running command.',
      ObjectSchema(Props, ['job_id'])));

    Props := TJSONObject.Create;
    Props.Add('job_id', StringProperty('Job ID returned by a process tool'));
    Props.Add('wait_ms', WaitProperty(10000,
      FConfig.MaximumProcessWaitMs));
    Props.Add('include_output', BooleanProperty(True,
      'Return stdout and stderr when the wait completes. While the job is still running, process_wait returns state only.'));
    Props.Add('max_output_chars', OutputCharsProperty);
    ATools.Add(BuildTool('process_wait',
      'Wait briefly for an existing managed job. If it is still running after wait_ms, it continues unchanged. Reuse the same job_id instead of starting the command again.',
      ObjectSchema(Props, ['job_id'])));

    Props := TJSONObject.Create;
    Props.Add('job_id', StringProperty('Job ID returned by a process tool'));
    ATools.Add(BuildTool('process_cancel',
      'Cancel a running managed process and its child process tree by job ID.',
      ObjectSchema(Props, ['job_id'])));
  end;
end;

function TProcessToolProvider.HandlesTool(const AName: string): Boolean;
begin
  Result := ((AName = 'process_exec') and FConfig.AllowProcessExec) or
    ((AName = 'shell_exec') and FConfig.AllowShellExec) or
    ((AName = 'process_start') and FConfig.AllowProcessStart) or
    ((AName = 'shell_start') and FConfig.AllowShellStart) or
    (((AName = 'process_status') or (AName = 'process_wait') or
      (AName = 'process_cancel')) and AnyProcessToolEnabled);
end;

function TProcessToolProvider.ProcessResultToJson(
  const AResult: TProcessRunResult; AIncludeOutput: Boolean): TJSONObject;
var
  StatusName: string;
  Succeeded: Boolean;
begin
  if AResult.Running then
    StatusName := 'running'
  else if AResult.ErrorMessage <> '' then
    StatusName := 'failed'
  else if AResult.Cancelled then
    StatusName := 'cancelled'
  else if AResult.IdleTimedOut then
    StatusName := 'idle_timeout'
  else if AResult.InteractiveInputDetected then
    StatusName := 'interactive_input'
  else if AResult.TimedOut then
    StatusName := 'timeout'
  else if AResult.ExitCode <> 0 then
    StatusName := 'failed'
  else
    StatusName := 'completed';

  Succeeded := (StatusName = 'running') or (StatusName = 'completed');
  Result := TJSONObject.Create;
  Result.Add('job_id', AResult.JobId);
  Result.Add('process_id', AResult.ProcessId);
  Result.Add('status', StatusName);
  Result.Add('success', Succeeded);
  Result.Add('started', AResult.Started);
  Result.Add('running', AResult.Running);
  Result.Add('continuation_required', AResult.Running);
  if AResult.Running then
    Result.Add('exit_code', TJSONNull.Create)
  else
    Result.Add('exit_code', AResult.ExitCode);
  if AIncludeOutput then
  begin
    Result.Add('stdout', string(AResult.StdOutText));
    Result.Add('stderr', string(AResult.StdErrText));
    Result.Add('response_output_truncated',
      AResult.ResponseOutputTruncated);
    Result.Add('complete_captured_output_returned',
      not AResult.ResponseOutputTruncated);
  end;
  Result.Add('timed_out', AResult.TimedOut);
  Result.Add('idle_timed_out', AResult.IdleTimedOut);
  Result.Add('interactive_input_detected',
    AResult.InteractiveInputDetected);
  if AResult.InteractivePrompt <> '' then
    Result.Add('interactive_prompt', AResult.InteractivePrompt);
  Result.Add('cancelled', AResult.Cancelled);
  Result.Add('capture_truncated', AResult.Truncated);
  Result.Add('captured_stdout_bytes', Int64(AResult.StdOutCapturedBytes));
  Result.Add('captured_stderr_bytes', Int64(AResult.StdErrCapturedBytes));
  Result.Add('captured_output_bytes',
    Int64(AResult.StdOutCapturedBytes + AResult.StdErrCapturedBytes));
  Result.Add('capture_limit_bytes', Int64(FConfig.MaximumOutputBytes));
  Result.Add('requested_timeout_ms', Int64(AResult.RequestedTimeoutMs));
  Result.Add('requested_idle_timeout_ms', Int64(AResult.RequestedIdleTimeoutMs));
  Result.Add('duration_ms', Int64(AResult.DurationMs));
  if AResult.ErrorMessage <> '' then
    Result.Add('error', AResult.ErrorMessage);
end;

function TProcessToolProvider.ResultText(
  const AResult: TProcessRunResult): string;
begin
  if AResult.Running then
    Exit(Format('PROCESS IS RUNNING AS MANAGED JOB %s (PID %d). The HTTP request has ended but the process continues. Do not start the command again. Use process_wait or process_status with this job_id.',
      [AResult.JobId, AResult.ProcessId]));
  if AResult.Cancelled then
    Exit('PROCESS CANCELLED BY THE USER. The command did not complete. Partial side effects may remain.');
  if AResult.IdleTimedOut then
    Exit('PROCESS STOPPED BY IDLE TIMEOUT. The command did not complete.');
  if AResult.InteractiveInputDetected then
    Exit('PROCESS STOPPED: A REPEATED INTERACTIVE PROMPT WAS DETECTED AFTER STDIN HAD BEEN CLOSED. The command was invoked as a finite exec but entered a REPL or conversation loop. Re-run it with its batch, noninteractive, single-turn, or no-conversation option; do not repeat the identical command.');
  if AResult.TimedOut then
    Exit('PROCESS STOPPED BY LIFETIME TIMEOUT. The command did not complete.');
  if AResult.ErrorMessage <> '' then
    Exit('PROCESS EXECUTION FAILED: ' + AResult.ErrorMessage);
  if AResult.ExitCode <> 0 then
    Exit(Format('PROCESS FAILED WITH EXIT CODE %d.', [AResult.ExitCode]));
  Result := 'PROCESS COMPLETED SUCCESSFULLY. Output is available in structuredContent.';
  if AResult.Truncated then
    Result := Result + ' The server capture limit was reached; later bytes were not retained. Increase processes.maximum_output_bytes if the complete output is required.';
end;

function TProcessToolProvider.CallTool(const AName: string;
  AArguments: TJSONObject; const ACorrelationId: string): TJSONObject;
var
  RunResult: TProcessRunResult;
  CancelResult: TProcessCancelResult;
  Arguments: TJSONArray;
  Structured: TJSONObject;
  Cwd, ExecutableName, CommandText, JobId: string;
  LifetimeTimeout, IdleTimeout, WaitMs, MaxOutputChars: Cardinal;
  IncludeOutput, Found, IsToolError, InteractiveGuard: Boolean;
begin
  if AName = 'process_cancel' then
  begin
    JobId := JsonString(AArguments, 'job_id');
    if Trim(JobId) = '' then
      raise Exception.Create('job_id must not be empty');
    CancelResult := FProcessRunner.Cancel(JobId);
    Structured := TJSONObject.Create;
    Structured.Add('job_id', CancelResult.JobId);
    Structured.Add('found', CancelResult.Found);
    Structured.Add('process_id', CancelResult.ProcessId);
    Structured.Add('cancellation_requested', CancelResult.CancellationRequested);
    Structured.Add('termination_attempted', CancelResult.TerminationAttempted);
    Structured.Add('termination_succeeded', CancelResult.TerminationSucceeded);
    if not CancelResult.Found then
      Exit(NewToolTextResult('PROCESS JOB NOT FOUND.', Structured, True));
    Exit(NewToolTextResult('Process cancellation request completed.',
      Structured, False));
  end;

  if AName = 'process_status' then
  begin
    JobId := JsonString(AArguments, 'job_id');
    if Trim(JobId) = '' then
      raise Exception.Create('job_id must not be empty');
    IncludeOutput := JsonBoolean(AArguments, 'include_output', True);
    MaxOutputChars := ParseCardinal(AArguments, 'max_output_chars',
      0, 100000);
    Found := FProcessRunner.Status(JobId, MaxOutputChars, RunResult);
    if not Found then
      raise Exception.Create('Unknown process job_id: ' + JobId);
    Structured := ProcessResultToJson(RunResult, IncludeOutput);
    IsToolError := (not RunResult.Running) and
      ((RunResult.ErrorMessage <> '') or RunResult.Cancelled or
       RunResult.TimedOut or RunResult.IdleTimedOut or
       RunResult.InteractiveInputDetected or
       (RunResult.ExitCode <> 0));
    Exit(NewToolTextResult(ResultText(RunResult), Structured, IsToolError));
  end;

  if AName = 'process_wait' then
  begin
    JobId := JsonString(AArguments, 'job_id');
    if Trim(JobId) = '' then
      raise Exception.Create('job_id must not be empty');
    WaitMs := ParseCardinal(AArguments, 'wait_ms', 10000,
      FConfig.MaximumProcessWaitMs);
    IncludeOutput := JsonBoolean(AArguments, 'include_output', True);
    MaxOutputChars := ParseCardinal(AArguments, 'max_output_chars',
      0, 100000);
    Found := FProcessRunner.Wait(JobId, WaitMs, MaxOutputChars, RunResult);
    if not Found then
      raise Exception.Create('Unknown process job_id: ' + JobId);
    { Polling a finite job must not resend growing output on every wait. The
      final wait response contains the complete captured output in one pass. }
    Structured := ProcessResultToJson(RunResult,
      IncludeOutput and (not RunResult.Running));
    IsToolError := (not RunResult.Running) and
      ((RunResult.ErrorMessage <> '') or RunResult.Cancelled or
       RunResult.TimedOut or RunResult.IdleTimedOut or
       RunResult.InteractiveInputDetected or
       (RunResult.ExitCode <> 0));
    Exit(NewToolTextResult(ResultText(RunResult), Structured, IsToolError));
  end;

  Cwd := FFsTools.ResolvePath(JsonString(AArguments, 'cwd', '.'));
  JobId := JsonString(AArguments, 'job_id');

  if (AName = 'process_start') or (AName = 'shell_start') then
  begin
    LifetimeTimeout := ParseCardinal(AArguments, 'timeout_ms', 0,
      FConfig.MaximumTimeoutMs);
    IdleTimeout := ParseCardinal(AArguments, 'idle_timeout_ms', 0,
      FConfig.MaximumIdleTimeoutMs);
  end
  else
  begin
    LifetimeTimeout := ParseCardinal(AArguments, 'timeout_ms',
      FConfig.DefaultTimeoutMs, FConfig.MaximumTimeoutMs);
    IdleTimeout := ParseCardinal(AArguments, 'idle_timeout_ms',
      FConfig.DefaultIdleTimeoutMs, FConfig.MaximumIdleTimeoutMs);
  end;

  InteractiveGuard := JsonBoolean(AArguments, 'interactive_guard',
    FConfig.DetectInteractivePromptLoops);

  if AName = 'process_exec' then
  begin
    ExecutableName := JsonString(AArguments, 'executable');
    if Trim(ExecutableName) = '' then
      raise Exception.Create('executable must not be empty');
    Arguments := JsonArray(AArguments, 'arguments');
    WaitMs := ParseCardinal(AArguments, 'wait_ms',
      FConfig.DefaultProcessWaitMs, FConfig.MaximumProcessWaitMs);
    RunResult := FProcessRunner.Execute(ExecutableName, Arguments,
      Cwd, JsonString(AArguments, 'stdin'), LifetimeTimeout,
      IdleTimeout, FConfig.MaximumOutputBytes, WaitMs,
      ACorrelationId, '', JobId, InteractiveGuard);
  end
  else if AName = 'shell_exec' then
  begin
    CommandText := JsonString(AArguments, 'command');
    if Trim(CommandText) = '' then
      raise Exception.Create('command must not be empty');
    WaitMs := ParseCardinal(AArguments, 'wait_ms',
      FConfig.DefaultProcessWaitMs, FConfig.MaximumProcessWaitMs);
    RunResult := FProcessRunner.ExecuteShell(CommandText,
      JsonString(AArguments, 'shell', 'auto'), Cwd,
      JsonString(AArguments, 'stdin'), LifetimeTimeout,
      IdleTimeout, FConfig.MaximumOutputBytes, WaitMs,
      ACorrelationId, JobId, InteractiveGuard);
  end
  else if AName = 'process_start' then
  begin
    ExecutableName := JsonString(AArguments, 'executable');
    if Trim(ExecutableName) = '' then
      raise Exception.Create('executable must not be empty');
    Arguments := JsonArray(AArguments, 'arguments');
    RunResult := FProcessRunner.StartProcess(ExecutableName,
      Arguments, Cwd, JsonString(AArguments, 'stdin'),
      LifetimeTimeout, IdleTimeout, FConfig.MaximumOutputBytes,
      ACorrelationId, JobId,
      JsonBoolean(AArguments, 'hidden', False));
  end
  else if AName = 'shell_start' then
  begin
    CommandText := JsonString(AArguments, 'command');
    if Trim(CommandText) = '' then
      raise Exception.Create('command must not be empty');
    RunResult := FProcessRunner.StartShell(CommandText,
      JsonString(AArguments, 'shell', 'auto'), Cwd,
      JsonString(AArguments, 'stdin'), LifetimeTimeout,
      IdleTimeout, FConfig.MaximumOutputBytes,
      ACorrelationId, JobId);
  end
  else
    raise Exception.CreateFmt('Unknown process tool: %s', [AName]);

  IncludeOutput := ((AName = 'process_exec') or
    (AName = 'shell_exec')) and (not RunResult.Running);
  Structured := ProcessResultToJson(RunResult, IncludeOutput);
  IsToolError := (not RunResult.Running) and
    ((RunResult.ErrorMessage <> '') or RunResult.Cancelled or
     RunResult.TimedOut or RunResult.IdleTimedOut or
     RunResult.InteractiveInputDetected or
     (RunResult.ExitCode <> 0));
  Result := NewToolTextResult(ResultText(RunResult), Structured,
    IsToolError);
end;

end.
