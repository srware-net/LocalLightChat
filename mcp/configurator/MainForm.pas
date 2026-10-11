unit MainForm;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, fpjson, jsonparser;

type
  TConfigForm = class(TForm)
  private
    FConfigFileName: string;
    FDirty: Boolean;
    FLoading: Boolean;
    FPageControl: TPageControl;
    FStatusBar: TStatusBar;
    FPathLabel: TLabel;
    FOpenDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;

    EAddress: TEdit;
    EPort: TEdit;
    EEndpoint: TEdit;
    EMaximumRequestBytes: TEdit;
    EBearerToken: TEdit;
    CCorsEnabled: TCheckBox;
    MAllowedOrigins: TMemo;
    CFilesystemEnabled: TCheckBox;
    EWorkspaceRoot: TEdit;
    CAllowDelete: TCheckBox;

    CProcessesEnabled: TCheckBox;
    CAllowProcessExec: TCheckBox;
    CAllowShellExec: TCheckBox;
    CAllowProcessStart: TCheckBox;
    CAllowShellStart: TCheckBox;
    EDefaultTimeoutMs: TEdit;
    EMaximumTimeoutMs: TEdit;
    EDefaultWaitMs: TEdit;
    EMaximumWaitMs: TEdit;
    EMaximumTrackedJobs: TEdit;
    EDefaultIdleTimeoutMs: TEdit;
    EMaximumIdleTimeoutMs: TEdit;
    ETerminationGraceMs: TEdit;
    CDetachFromTerminal: TCheckBox;
    EMaximumOutputBytes: TEdit;
    EMaxOutputChars: TEdit;
    CMirrorOutputToConsole: TCheckBox;
    CBConsoleOutputMode: TComboBox;
    CDetectInteractivePromptLoops: TCheckBox;
    EInteractivePromptRepeatLimit: TEdit;
    EInteractivePromptWindowMs: TEdit;
    EInteractivePromptMaxChars: TEdit;

    CTerminalEnabled: TCheckBox;
    ETerminalMaximumSessions: TEdit;
    ETerminalMaximumOutputBytes: TEdit;
    ETerminalMaximumReadBytes: TEdit;
    ETerminalMaximumWriteBytes: TEdit;
    ETerminalDefaultColumns: TEdit;
    ETerminalDefaultRows: TEdit;
    ETerminalMaximumReadWaitMs: TEdit;
    ETerminalTerminationGraceMs: TEdit;

    CDesktopEnabled: TCheckBox;
    EDesktopMaximumImageBytes: TEdit;
    CDesktopWindowManagement: TCheckBox;
    CDesktopCapture: TCheckBox;
    CDesktopInput: TCheckBox;

    ELogFile: TEdit;
    CLogProcessCommands: TCheckBox;
    CLogProcessOutput: TCheckBox;

    procedure BuildUi;
    function AddTab(const ACaption: string): TScrollBox;
    procedure AddEdit(AParent: TWinControl; var ATop: Integer;
      const ACaption, AHint: string; out AEdit: TEdit;
      APassword: Boolean = False);
    procedure AddCheck(AParent: TWinControl; var ATop: Integer;
      const ACaption, AHint: string; out ACheck: TCheckBox);
    procedure AddCombo(AParent: TWinControl; var ATop: Integer;
      const ACaption, AHint: string; out ACombo: TComboBox;
      const AItems: array of string);
    procedure AddMemo(AParent: TWinControl; var ATop: Integer;
      const ACaption, AHint: string; out AMemo: TMemo);
    procedure SetControlHint(AControl: TControl; const AHint: string);
    procedure ResetDefaults;
    function FindInitialConfigFile: string;
    procedure LoadConfig(const AFileName: string);
    procedure SaveConfig(const AFileName: string);
    function ValidateControls(out AError: string): Boolean;
    function CardinalFromEdit(AEdit: TEdit; const AField: string;
      AMinimum, AMaximum: Int64): Cardinal;
    procedure UpdateCaption;
    procedure ControlChanged(Sender: TObject);
    procedure ApplicationHint(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure DefaultsClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function SaveCurrent: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  ConfigForm: TConfigForm;

implementation

uses
  McpJson;

const
  LABEL_LEFT = 18;
  LABEL_WIDTH = 300;
  CONTROL_LEFT = 335;
  CONTROL_WIDTH = 600;
  ROW_HEIGHT = 44;
  MAX_CARDINAL_VALUE = 4294967295;

constructor TConfigForm.Create(AOwner: TComponent);
var
  InitialFile: string;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MCP Server Configurator';
  Position := poScreenCenter;
  Width := 1020;
  Height := 780;
  Constraints.MinWidth := 980;
  Constraints.MinHeight := 620;
  ShowHint := True;
  OnCloseQuery := @FormCloseQuery;

  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.Filter := 'MCP configuration (*.json)|*.json|All files|*.*';
  FOpenDialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];

  FSaveDialog := TSaveDialog.Create(Self);
  FSaveDialog.Filter := FOpenDialog.Filter;
  FSaveDialog.DefaultExt := 'json';
  FSaveDialog.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];

  BuildUi;
  Application.OnHint := @ApplicationHint;

  FLoading := True;
  try
    ResetDefaults;
  finally
    FLoading := False;
  end;
  FDirty := False;

  InitialFile := FindInitialConfigFile;
  if InitialFile <> '' then
  begin
    try
      LoadConfig(InitialFile);
    except
      on E: Exception do
        MessageDlg('Could not load configuration', E.Message,
          mtError, [mbOK], 0);
    end;
  end;
  UpdateCaption;
end;

destructor TConfigForm.Destroy;
begin
  Application.OnHint := nil;
  inherited Destroy;
end;

procedure TConfigForm.SetControlHint(AControl: TControl; const AHint: string);
begin
  AControl.Hint := AHint;
  AControl.ShowHint := True;
end;

function TConfigForm.AddTab(const ACaption: string): TScrollBox;
var
  Tab: TTabSheet;
begin
  Tab := TTabSheet.Create(FPageControl);
  Tab.PageControl := FPageControl;
  Tab.Caption := ACaption;

  Result := TScrollBox.Create(Tab);
  Result.Parent := Tab;
  Result.Align := alClient;
  Result.BorderStyle := bsNone;
  Result.AutoScroll := True;
  Result.HorzScrollBar.Visible := False;
  Result.VertScrollBar.Tracking := True;
end;

procedure TConfigForm.AddEdit(AParent: TWinControl; var ATop: Integer;
  const ACaption, AHint: string; out AEdit: TEdit; APassword: Boolean);
var
  L: TLabel;
begin
  L := TLabel.Create(AParent);
  L.Parent := AParent;
  L.Caption := ACaption;
  L.SetBounds(LABEL_LEFT, ATop, LABEL_WIDTH, 38);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Layout := tlCenter;
  SetControlHint(L, AHint);

  AEdit := TEdit.Create(AParent);
  AEdit.Parent := AParent;
  AEdit.SetBounds(CONTROL_LEFT, ATop + 6, CONTROL_WIDTH, 27);
  AEdit.Anchors := [akLeft, akTop];
  if APassword then
    AEdit.PasswordChar := '*';
  AEdit.OnChange := @ControlChanged;
  SetControlHint(AEdit, AHint);
  Inc(ATop, ROW_HEIGHT);
end;

procedure TConfigForm.AddCheck(AParent: TWinControl; var ATop: Integer;
  const ACaption, AHint: string; out ACheck: TCheckBox);
begin
  ACheck := TCheckBox.Create(AParent);
  ACheck.Parent := AParent;
  ACheck.Caption := ACaption;
  ACheck.SetBounds(CONTROL_LEFT, ATop + 5, CONTROL_WIDTH, 30);
  ACheck.Anchors := [akLeft, akTop];
  ACheck.OnChange := @ControlChanged;
  SetControlHint(ACheck, AHint);
  Inc(ATop, ROW_HEIGHT);
end;

procedure TConfigForm.AddCombo(AParent: TWinControl; var ATop: Integer;
  const ACaption, AHint: string; out ACombo: TComboBox;
  const AItems: array of string);
var
  L: TLabel;
  I: Integer;
begin
  L := TLabel.Create(AParent);
  L.Parent := AParent;
  L.Caption := ACaption;
  L.SetBounds(LABEL_LEFT, ATop, LABEL_WIDTH, 38);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Layout := tlCenter;
  SetControlHint(L, AHint);

  ACombo := TComboBox.Create(AParent);
  ACombo.Parent := AParent;
  ACombo.SetBounds(CONTROL_LEFT, ATop + 6, 260, 27);
  ACombo.Anchors := [akLeft, akTop];
  ACombo.Style := csDropDownList;
  for I := Low(AItems) to High(AItems) do
    ACombo.Items.Add(AItems[I]);
  ACombo.OnChange := @ControlChanged;
  SetControlHint(ACombo, AHint);
  Inc(ATop, ROW_HEIGHT);
end;

procedure TConfigForm.AddMemo(AParent: TWinControl; var ATop: Integer;
  const ACaption, AHint: string; out AMemo: TMemo);
var
  L: TLabel;
begin
  L := TLabel.Create(AParent);
  L.Parent := AParent;
  L.Caption := ACaption;
  L.SetBounds(LABEL_LEFT, ATop, LABEL_WIDTH, 38);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Layout := tlCenter;
  SetControlHint(L, AHint);

  AMemo := TMemo.Create(AParent);
  AMemo.Parent := AParent;
  AMemo.SetBounds(CONTROL_LEFT, ATop + 6, CONTROL_WIDTH, 112);
  AMemo.Anchors := [akLeft, akTop];
  AMemo.ScrollBars := ssVertical;
  AMemo.OnChange := @ControlChanged;
  SetControlHint(AMemo, AHint);
  Inc(ATop, 124);
end;

procedure TConfigForm.BuildUi;
var
  Toolbar: TPanel;
  B: TButton;
  Page: TScrollBox;
  Y: Integer;
begin
  Toolbar := TPanel.Create(Self);
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Height := 48;
  Toolbar.BevelOuter := bvNone;

  B := TButton.Create(Toolbar);
  B.Parent := Toolbar;
  B.Caption := 'Open';
  B.SetBounds(10, 10, 82, 29);
  B.OnClick := @OpenClick;
  SetControlHint(B, 'Load an existing mcp-server.json file.');

  B := TButton.Create(Toolbar);
  B.Parent := Toolbar;
  B.Caption := 'Save';
  B.SetBounds(98, 10, 82, 29);
  B.OnClick := @SaveClick;
  SetControlHint(B, 'Write the current configuration to the open file.');

  B := TButton.Create(Toolbar);
  B.Parent := Toolbar;
  B.Caption := 'Save As';
  B.SetBounds(186, 10, 90, 29);
  B.OnClick := @SaveAsClick;
  SetControlHint(B, 'Save the current configuration under a new file name.');

  B := TButton.Create(Toolbar);
  B.Parent := Toolbar;
  B.Caption := 'Validate';
  B.SetBounds(282, 10, 90, 29);
  B.OnClick := @ValidateClick;
  SetControlHint(B, 'Validate all values without changing the file.');

  B := TButton.Create(Toolbar);
  B.Parent := Toolbar;
  B.Caption := 'Defaults';
  B.SetBounds(378, 10, 90, 29);
  B.OnClick := @DefaultsClick;
  SetControlHint(B, 'Reset all fields to the defaults defined by the server code.');

  FPathLabel := TLabel.Create(Toolbar);
  FPathLabel.Parent := Toolbar;
  FPathLabel.SetBounds(485, 16, 515, 20);
  FPathLabel.Anchors := [akLeft, akTop, akRight];
  FPathLabel.AutoSize := False;
  FPathLabel.Alignment := taRightJustify;

  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.SimplePanel := True;
  FStatusBar.SimpleText := 'Ready';

  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := Self;
  FPageControl.Align := alClient;

  Page := AddTab('Server');
  Y := 18;
  AddEdit(Page, Y, 'Bind address (address)',
    'IP address used by the HTTP server. 127.0.0.1 accepts local connections only; 0.0.0.0 listens on all IPv4 interfaces.', EAddress);
  AddEdit(Page, Y, 'TCP port (port)',
    'TCP port of the MCP HTTP server. Valid values are 1 through 65535.', EPort);
  AddEdit(Page, Y, 'HTTP endpoint (endpoint)',
    'URL path that accepts MCP requests, for example /mcp. A missing leading slash is added when the file is saved.', EEndpoint);
  AddEdit(Page, Y, 'Maximum request size (maximum_request_bytes)',
    'Maximum HTTP request body size in bytes. Larger requests are rejected with HTTP 413.', EMaximumRequestBytes);

  Page := AddTab('Security & CORS');
  Y := 18;
  AddEdit(Page, Y, 'Bearer token (bearer_token)',
    'Token expected in the Authorization: Bearer <token> HTTP header. An empty value disables token authentication.', EBearerToken, True);
  AddCheck(Page, Y, 'Allow browser access through CORS (cors.enabled)',
    'Enables CORS for browser clients. Non-browser clients without an Origin header are unaffected.', CCorsEnabled);
  AddMemo(Page, Y, 'Allowed origins (allowed_origins)',
    'Enter one origin per line, including scheme, host, and optional port, for example http://192.168.1.10:8001. Trailing slashes are removed.', MAllowedOrigins);

  Page := AddTab('Filesystem');
  Y := 18;
  AddCheck(Page, Y, 'Enable filesystem tools (filesystem.enabled)',
    'Registers MCP tools for reading, writing, searching, copying, and moving files inside the workspace.', CFilesystemEnabled);
  AddEdit(Page, Y, 'Workspace directory (workspace_root)',
    'Root directory for all file and process paths. Relative paths are resolved by the server relative to the JSON file.', EWorkspaceRoot);
  AddCheck(Page, Y, 'Allow deletion (allow_delete)',
    'Enables the MCP tool for deleting files and directories. When disabled, the tool is not exposed.', CAllowDelete);

  Page := AddTab('Process Permissions');
  Y := 18;
  AddCheck(Page, Y, 'Enable process tools (processes.enabled)',
    'Enables the entire process provider. The individual tool switches below apply in addition to this setting.', CProcessesEnabled);
  AddCheck(Page, Y, 'Execute programs directly (allow_process_exec)',
    'Enables process_exec for non-interactive programs that normally finish within the configured wait time.', CAllowProcessExec);
  AddCheck(Page, Y, 'Execute shell commands (allow_shell_exec)',
    'Enables shell_exec for non-interactive commands through cmd, PowerShell, sh, or bash.', CAllowShellExec);
  AddCheck(Page, Y, 'Start programs directly (allow_process_start)',
    'Enables process_start for GUI applications and long-running programs that continue as managed jobs.', CAllowProcessStart);
  AddCheck(Page, Y, 'Start shell processes (allow_shell_start)',
    'Enables shell_start for servers, watchers, services, and other long-running shell commands.', CAllowShellStart);
  AddCheck(Page, Y, 'Detach from the calling terminal (detach_from_terminal)',
    'Starts child processes in a separate process group or without attachment to the calling terminal where supported.', CDetachFromTerminal);
  AddCheck(Page, Y, 'Mirror process output to the server console (mirror_output_to_console)',
    'Writes captured stdout and stderr data live to the MCP server console as well.', CMirrorOutputToConsole);
  AddCombo(Page, Y, 'Console output mode (console_output_mode)',
    'prefixed adds job and stream prefixes to each line; raw writes received bytes with as little modification as possible.', CBConsoleOutputMode,
    ['prefixed', 'raw']);

  Page := AddTab('Process Limits');
  Y := 18;
  AddEdit(Page, Y, 'Default runtime limit (default_timeout_ms)',
    'Default maximum runtime for process_exec and shell_exec in milliseconds. 0 means unlimited.', EDefaultTimeoutMs);
  AddEdit(Page, Y, 'Maximum runtime limit (maximum_timeout_ms)',
    'Upper limit for runtime values requested by clients. 0 means no additional upper limit.', EMaximumTimeoutMs);
  AddEdit(Page, Y, 'Default wait time (default_wait_ms)',
    'How long process_exec and shell_exec wait for completion by default. An active process continues as a managed job afterwards.', EDefaultWaitMs);
  AddEdit(Page, Y, 'Maximum wait time (maximum_wait_ms)',
    'Upper limit for wait_ms in process tools. The value must be at least 1.', EMaximumWaitMs);
  AddEdit(Page, Y, 'Maximum tracked jobs (maximum_tracked_jobs)',
    'Maximum number of active or recently completed managed process jobs. Old completed jobs are removed when necessary. Minimum: 8.', EMaximumTrackedJobs);
  AddEdit(Page, Y, 'Default idle timeout (default_idle_timeout_ms)',
    'Default time without stdout or stderr before an exec process is terminated. 0 disables idle monitoring.', EDefaultIdleTimeoutMs);
  AddEdit(Page, Y, 'Maximum idle timeout (maximum_idle_timeout_ms)',
    'Upper limit for idle timeout values requested by clients. 0 means no additional upper limit.', EMaximumIdleTimeoutMs);
  AddEdit(Page, Y, 'Termination grace period (termination_grace_ms)',
    'Time in milliseconds between a graceful termination request and forced process termination.', ETerminationGraceMs);
  AddEdit(Page, Y, 'Maximum captured output (maximum_output_bytes)',
    'Maximum number of stdout and stderr bytes stored per process job. Later data is discarded once the limit is reached.', EMaximumOutputBytes);
  AddEdit(Page, Y, 'Default returned characters (max_output_chars)',
    'Default max_output_chars value for process_status and process_wait. 0 returns all output still captured by the server; maximum: 100000.', EMaxOutputChars);
  AddCheck(Page, Y, 'Detect interactive prompt loops (detect_interactive_prompt_loops)',
    'Terminates finite exec jobs when short prompt-like lines repeat after stdin has been closed.', CDetectInteractivePromptLoops);
  AddEdit(Page, Y, 'Prompt repetition limit (interactive_prompt_repeat_limit)',
    'Number of repeated identical prompt lines that triggers the protection. Minimum: 3.', EInteractivePromptRepeatLimit);
  AddEdit(Page, Y, 'Prompt detection window (interactive_prompt_window_ms)',
    'Time window in milliseconds in which the repetitions must occur. Minimum: 100.', EInteractivePromptWindowMs);
  AddEdit(Page, Y, 'Maximum prompt length (interactive_prompt_max_chars)',
    'Only lines up to this number of characters are considered possible interactive prompts. Valid range: 4 through 1024.', EInteractivePromptMaxChars);

  Page := AddTab('Interactive Terminal');
  Y := 18;
  AddCheck(Page, Y, 'Enable interactive PTY/ConPTY tools (terminal.enabled)',
    'Registers terminal_open/read/write/resize/signal/status/close. This is a separate capability from the finite process tools and is intended for SSH, sudo, shells, and REPLs.', CTerminalEnabled);
  AddEdit(Page, Y, 'Maximum terminal sessions (maximum_sessions)',
    'Maximum number of active or retained interactive terminal sessions. Completed sessions are pruned when capacity is needed.', ETerminalMaximumSessions);
  AddEdit(Page, Y, 'Terminal output ring buffer (maximum_output_bytes)',
    'Maximum retained terminal output bytes per session. Oldest bytes are dropped when the ring buffer is full.', ETerminalMaximumOutputBytes);
  AddEdit(Page, Y, 'Maximum read bytes (maximum_read_bytes)',
    'Maximum terminal output bytes one terminal_read call may return.', ETerminalMaximumReadBytes);
  AddEdit(Page, Y, 'Maximum write bytes (maximum_write_bytes)',
    'Maximum UTF-8 input bytes one terminal_write call may send.', ETerminalMaximumWriteBytes);
  AddEdit(Page, Y, 'Default columns (default_columns)',
    'Initial PTY/ConPTY width in character cells. Valid range: 1 through 32767.', ETerminalDefaultColumns);
  AddEdit(Page, Y, 'Default rows (default_rows)',
    'Initial PTY/ConPTY height in character cells. Valid range: 1 through 32767.', ETerminalDefaultRows);
  AddEdit(Page, Y, 'Maximum read wait (maximum_read_wait_ms)',
    'Maximum long-poll wait accepted by terminal_read. Minimum: 1 millisecond.', ETerminalMaximumReadWaitMs);
  AddEdit(Page, Y, 'Termination grace period (termination_grace_ms)',
    'Grace period used while closing a terminal before forced process termination.', ETerminalTerminationGraceMs);

  Page := AddTab('Desktop primitives');
  Y := 18;
  AddCheck(Page, Y, 'Enable desktop primitives (desktop.enabled)',
    'Enables the desktop provider. The current implementation exposes desktop tools only on Windows. This is deliberately not a general GUI-automation subsystem.', CDesktopEnabled);
  AddCheck(Page, Y, 'Window list and management (window_management)',
    'Registers desktop_windows and desktop_window for top-level window discovery and basic activate/restore/minimize/maximize/close operations.', CDesktopWindowManagement);
  AddCheck(Page, Y, 'Visual observation (screen_capture)',
    'Registers desktop_observe. It returns a screenshot as model context and declares an image-input requirement in MCP tool metadata; text-only model hosts should hide the tool.', CDesktopCapture);
  AddEdit(Page, Y, 'Observe image hard limit (maximum_image_bytes)',
    'Hard server-side byte limit for desktop_observe images. Client max_bytes requests are capped at this value. Minimum: 32768.', EDesktopMaximumImageBytes);
  AddCheck(Page, Y, 'Raw keyboard input (input)',
    'Registers desktop_type_text and desktop_key. Input is sent to the current keyboard focus; the server does not identify a target control and exposes no mouse/click API.', CDesktopInput);

  Page := AddTab('Logging');
  Y := 18;
  AddEdit(Page, Y, 'Log file (logging.file)',
    'Path to the server log file. Relative paths are resolved relative to the JSON file. An empty value disables file logging.', ELogFile);
  AddCheck(Page, Y, 'Log process commands (log_process_commands)',
    'Writes started programs and shell commands to the server log. Sensitive command arguments may become visible.', CLogProcessCommands);
  AddCheck(Page, Y, 'Log process output (log_process_output)',
    'Writes stdout and stderr from started processes to the server log. This can grow the log substantially and may expose sensitive data.', CLogProcessOutput);
end;

procedure TConfigForm.ResetDefaults;
begin
  EAddress.Text := '127.0.0.1';
  EPort.Text := '8765';
  EEndpoint.Text := '/mcp';
  EMaximumRequestBytes.Text := '1048576';
  EBearerToken.Text := 'change-me';
  CCorsEnabled.Checked := False;
  MAllowedOrigins.Clear;
  CFilesystemEnabled.Checked := True;
  EWorkspaceRoot.Text := 'workspace';
  CAllowDelete.Checked := False;

  CProcessesEnabled.Checked := True;
  CAllowProcessExec.Checked := True;
  CAllowShellExec.Checked := True;
  CAllowProcessStart.Checked := True;
  CAllowShellStart.Checked := True;
  EDefaultTimeoutMs.Text := '0';
  EMaximumTimeoutMs.Text := '0';
  EDefaultWaitMs.Text := '3000';
  EMaximumWaitMs.Text := '60000';
  EMaximumTrackedJobs.Text := '512';
  EDefaultIdleTimeoutMs.Text := '0';
  EMaximumIdleTimeoutMs.Text := '0';
  ETerminationGraceMs.Text := '2000';
  CDetachFromTerminal.Checked := True;
  EMaximumOutputBytes.Text := '4194304';
  EMaxOutputChars.Text := '0';
  CMirrorOutputToConsole.Checked := True;
  CBConsoleOutputMode.ItemIndex := CBConsoleOutputMode.Items.IndexOf('prefixed');
  CDetectInteractivePromptLoops.Checked := True;
  EInteractivePromptRepeatLimit.Text := '12';
  EInteractivePromptWindowMs.Text := '2000';
  EInteractivePromptMaxChars.Text := '80';

  CTerminalEnabled.Checked := False;
  ETerminalMaximumSessions.Text := '16';
  ETerminalMaximumOutputBytes.Text := '4194304';
  ETerminalMaximumReadBytes.Text := '65536';
  ETerminalMaximumWriteBytes.Text := '65536';
  ETerminalDefaultColumns.Text := '120';
  ETerminalDefaultRows.Text := '40';
  ETerminalMaximumReadWaitMs.Text := '60000';
  ETerminalTerminationGraceMs.Text := '2000';

  CDesktopEnabled.Checked := False;
  EDesktopMaximumImageBytes.Text := '16777216';
  CDesktopWindowManagement.Checked := True;
  CDesktopCapture.Checked := True;
  CDesktopInput.Checked := True;

  ELogFile.Text := 'mcp-server.log';
  CLogProcessCommands.Checked := True;
  CLogProcessOutput.Checked := True;
end;

function TConfigForm.FindInitialConfigFile: string;
var
  Base: string;
  Candidates: array[0..4] of string;
  I: Integer;
begin
  Result := '';
  if ParamCount > 0 then
  begin
    Result := ExpandFileName(ParamStr(1));
    Exit;
  end;

  Base := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Candidates[0] := Base + 'mcp-server.json';
  Candidates[1] := ExpandFileName(Base + '..' + DirectorySeparator +
    'server' + DirectorySeparator + 'mcp-server.json');
  Candidates[2] := ExpandFileName(Base + '..' + DirectorySeparator + '..' +
    DirectorySeparator + 'server' + DirectorySeparator + 'mcp-server.json');
  Candidates[3] := ExpandFileName('server' + DirectorySeparator + 'mcp-server.json');
  Candidates[4] := ExpandFileName('mcp-server.json');
  for I := Low(Candidates) to High(Candidates) do
    if FileExists(Candidates[I]) then
      Exit(Candidates[I]);
end;

procedure TConfigForm.LoadConfig(const AFileName: string);
var
  Source: TStringList;
  RootData: TJSONData;
  Root, Section, Features: TJSONObject;
  Origins: TJSONArray;
  I: Integer;
begin
  if not FileExists(AFileName) then
    raise Exception.Create('File not found: ' + AFileName);

  Source := TStringList.Create;
  RootData := nil;
  FLoading := True;
  try
    Source.LoadFromFile(AFileName);
    RootData := GetJSON(Source.Text);
    if RootData.JSONType <> jtObject then
      raise Exception.Create('The configuration root must be a JSON object.');
    Root := TJSONObject(RootData);

    ResetDefaults;

    Section := JsonObject(Root, 'server');
    if Section <> nil then
    begin
      EAddress.Text := JsonString(Section, 'address', EAddress.Text);
      EPort.Text := IntToStr(JsonInteger(Section, 'port', StrToInt(EPort.Text)));
      EEndpoint.Text := JsonString(Section, 'endpoint', EEndpoint.Text);
      EMaximumRequestBytes.Text := IntToStr(JsonInteger(Section,
        'maximum_request_bytes', StrToInt64(EMaximumRequestBytes.Text)));
    end;

    Section := JsonObject(Root, 'authentication');
    if Section <> nil then
    begin
      EBearerToken.Text := JsonString(Section, 'bearer_token', EBearerToken.Text);
    end;

    Section := JsonObject(Root, 'cors');
    if Section <> nil then
    begin
      CCorsEnabled.Checked := JsonBoolean(Section, 'enabled', CCorsEnabled.Checked);
      Origins := JsonArray(Section, 'allowed_origins');
      if Origins <> nil then
      begin
        MAllowedOrigins.Clear;
        for I := 0 to Origins.Count - 1 do
          if Origins.Items[I].JSONType = jtString then
            MAllowedOrigins.Lines.Add(Origins.Items[I].AsString);
      end;
    end;

    Section := JsonObject(Root, 'filesystem');
    if Section <> nil then
    begin
      CFilesystemEnabled.Checked := JsonBoolean(Section, 'enabled', CFilesystemEnabled.Checked);
      EWorkspaceRoot.Text := JsonString(Section, 'workspace_root', EWorkspaceRoot.Text);
      CAllowDelete.Checked := JsonBoolean(Section, 'allow_delete', CAllowDelete.Checked);
    end;

    Section := JsonObject(Root, 'processes');
    if Section <> nil then
    begin
      CProcessesEnabled.Checked := JsonBoolean(Section, 'enabled', CProcessesEnabled.Checked);
      CAllowProcessExec.Checked := JsonBoolean(Section, 'allow_process_exec', CAllowProcessExec.Checked);
      CAllowShellExec.Checked := JsonBoolean(Section, 'allow_shell_exec', CAllowShellExec.Checked);
      CAllowProcessStart.Checked := JsonBoolean(Section, 'allow_process_start', CAllowProcessStart.Checked);
      CAllowShellStart.Checked := JsonBoolean(Section, 'allow_shell_start', CAllowShellStart.Checked);
      EDefaultTimeoutMs.Text := IntToStr(JsonInteger(Section, 'default_timeout_ms', StrToInt64(EDefaultTimeoutMs.Text)));
      EMaximumTimeoutMs.Text := IntToStr(JsonInteger(Section, 'maximum_timeout_ms', StrToInt64(EMaximumTimeoutMs.Text)));
      EDefaultWaitMs.Text := IntToStr(JsonInteger(Section, 'default_wait_ms', StrToInt64(EDefaultWaitMs.Text)));
      EMaximumWaitMs.Text := IntToStr(JsonInteger(Section, 'maximum_wait_ms', StrToInt64(EMaximumWaitMs.Text)));
      EMaximumTrackedJobs.Text := IntToStr(JsonInteger(Section, 'maximum_tracked_jobs', StrToInt64(EMaximumTrackedJobs.Text)));
      EDefaultIdleTimeoutMs.Text := IntToStr(JsonInteger(Section, 'default_idle_timeout_ms', StrToInt64(EDefaultIdleTimeoutMs.Text)));
      EMaximumIdleTimeoutMs.Text := IntToStr(JsonInteger(Section, 'maximum_idle_timeout_ms', StrToInt64(EMaximumIdleTimeoutMs.Text)));
      ETerminationGraceMs.Text := IntToStr(JsonInteger(Section, 'termination_grace_ms', StrToInt64(ETerminationGraceMs.Text)));
      CDetachFromTerminal.Checked := JsonBoolean(Section, 'detach_from_terminal', CDetachFromTerminal.Checked);
      EMaximumOutputBytes.Text := IntToStr(JsonInteger(Section, 'maximum_output_bytes', StrToInt64(EMaximumOutputBytes.Text)));
      EMaxOutputChars.Text := IntToStr(JsonInteger(Section, 'max_output_chars', StrToInt64(EMaxOutputChars.Text)));
      CMirrorOutputToConsole.Checked := JsonBoolean(Section, 'mirror_output_to_console', CMirrorOutputToConsole.Checked);
      CBConsoleOutputMode.ItemIndex := CBConsoleOutputMode.Items.IndexOf(
        LowerCase(JsonString(Section, 'console_output_mode', 'prefixed')));
      if CBConsoleOutputMode.ItemIndex < 0 then
        CBConsoleOutputMode.ItemIndex := 0;
      CDetectInteractivePromptLoops.Checked := JsonBoolean(Section,
        'detect_interactive_prompt_loops', CDetectInteractivePromptLoops.Checked);
      EInteractivePromptRepeatLimit.Text := IntToStr(JsonInteger(Section,
        'interactive_prompt_repeat_limit', StrToInt64(EInteractivePromptRepeatLimit.Text)));
      EInteractivePromptWindowMs.Text := IntToStr(JsonInteger(Section,
        'interactive_prompt_window_ms', StrToInt64(EInteractivePromptWindowMs.Text)));
      EInteractivePromptMaxChars.Text := IntToStr(JsonInteger(Section,
        'interactive_prompt_max_chars', StrToInt64(EInteractivePromptMaxChars.Text)));
    end;

    Section := JsonObject(Root, 'terminal');
    if Section <> nil then
    begin
      CTerminalEnabled.Checked := JsonBoolean(Section, 'enabled', CTerminalEnabled.Checked);
      ETerminalMaximumSessions.Text := IntToStr(JsonInteger(Section,
        'maximum_sessions', StrToInt64(ETerminalMaximumSessions.Text)));
      ETerminalMaximumOutputBytes.Text := IntToStr(JsonInteger(Section,
        'maximum_output_bytes', StrToInt64(ETerminalMaximumOutputBytes.Text)));
      ETerminalMaximumReadBytes.Text := IntToStr(JsonInteger(Section,
        'maximum_read_bytes', StrToInt64(ETerminalMaximumReadBytes.Text)));
      ETerminalMaximumWriteBytes.Text := IntToStr(JsonInteger(Section,
        'maximum_write_bytes', StrToInt64(ETerminalMaximumWriteBytes.Text)));
      ETerminalDefaultColumns.Text := IntToStr(JsonInteger(Section,
        'default_columns', StrToInt64(ETerminalDefaultColumns.Text)));
      ETerminalDefaultRows.Text := IntToStr(JsonInteger(Section,
        'default_rows', StrToInt64(ETerminalDefaultRows.Text)));
      ETerminalMaximumReadWaitMs.Text := IntToStr(JsonInteger(Section,
        'maximum_read_wait_ms', StrToInt64(ETerminalMaximumReadWaitMs.Text)));
      ETerminalTerminationGraceMs.Text := IntToStr(JsonInteger(Section,
        'termination_grace_ms', StrToInt64(ETerminalTerminationGraceMs.Text)));
    end;

    Section := JsonObject(Root, 'desktop');
    if Section <> nil then
    begin
      CDesktopEnabled.Checked := JsonBoolean(Section, 'enabled', CDesktopEnabled.Checked);
      EDesktopMaximumImageBytes.Text := IntToStr(JsonInteger(Section,
        'maximum_image_bytes', StrToInt64(EDesktopMaximumImageBytes.Text)));
      Features := JsonObject(Section, 'features');
      if Features <> nil then
      begin
        CDesktopWindowManagement.Checked := JsonBoolean(Features,
          'window_management', CDesktopWindowManagement.Checked);
        CDesktopCapture.Checked := JsonBoolean(Features,
          'screen_capture', CDesktopCapture.Checked);
        CDesktopInput.Checked := JsonBoolean(Features, 'input', CDesktopInput.Checked);
      end;
    end;

    Section := JsonObject(Root, 'logging');
    if Section <> nil then
    begin
      ELogFile.Text := JsonString(Section, 'file', ELogFile.Text);
      CLogProcessCommands.Checked := JsonBoolean(Section,
        'log_process_commands', CLogProcessCommands.Checked);
      CLogProcessOutput.Checked := JsonBoolean(Section,
        'log_process_output', CLogProcessOutput.Checked);
    end;

    FConfigFileName := ExpandFileName(AFileName);
    FDirty := False;
    UpdateCaption;
    FStatusBar.SimpleText := 'Loaded: ' + FConfigFileName;
  finally
    FLoading := False;
    RootData.Free;
    Source.Free;
  end;

end;

function TConfigForm.CardinalFromEdit(AEdit: TEdit; const AField: string;
  AMinimum, AMaximum: Int64): Cardinal;
var
  Value: Int64;
begin
  if not TryStrToInt64(Trim(AEdit.Text), Value) then
    raise Exception.Create(AField + ' must be an integer.');
  if Value < AMinimum then
    raise Exception.CreateFmt('%s must be at least %d.', [AField, AMinimum]);
  if Value > AMaximum then
    raise Exception.CreateFmt('%s must not exceed %d.', [AField, AMaximum]);
  Result := Cardinal(Value);
end;

function TConfigForm.ValidateControls(out AError: string): Boolean;
var
  PortValue: Cardinal;
  DefaultTimeout, MaximumTimeout: Cardinal;
  DefaultWait, MaximumWait: Cardinal;
  DefaultIdle, MaximumIdle: Cardinal;
begin
  Result := False;
  AError := '';
  try
    if Trim(EAddress.Text) = '' then
      raise Exception.Create('server.address must not be empty.');
    PortValue := CardinalFromEdit(EPort, 'server.port', 1, 65535);
    if PortValue = 0 then
      raise Exception.Create('server.port must not be 0.');
    if Trim(EEndpoint.Text) = '' then
      raise Exception.Create('server.endpoint must not be empty.');
    CardinalFromEdit(EMaximumRequestBytes, 'server.maximum_request_bytes',
      1, MAX_CARDINAL_VALUE);

    if Trim(EWorkspaceRoot.Text) = '' then
      raise Exception.Create('filesystem.workspace_root must not be empty.');

    DefaultTimeout := CardinalFromEdit(EDefaultTimeoutMs,
      'processes.default_timeout_ms', 0, MAX_CARDINAL_VALUE);
    MaximumTimeout := CardinalFromEdit(EMaximumTimeoutMs,
      'processes.maximum_timeout_ms', 0, MAX_CARDINAL_VALUE);
    if (MaximumTimeout > 0) and (DefaultTimeout > MaximumTimeout) then
      raise Exception.Create('processes.default_timeout_ms must not exceed maximum_timeout_ms.');

    DefaultWait := CardinalFromEdit(EDefaultWaitMs,
      'processes.default_wait_ms', 0, MAX_CARDINAL_VALUE);
    MaximumWait := CardinalFromEdit(EMaximumWaitMs,
      'processes.maximum_wait_ms', 1, MAX_CARDINAL_VALUE);
    if DefaultWait > MaximumWait then
      raise Exception.Create('processes.default_wait_ms must not exceed maximum_wait_ms.');

    CardinalFromEdit(EMaximumTrackedJobs, 'processes.maximum_tracked_jobs',
      8, High(Integer));
    DefaultIdle := CardinalFromEdit(EDefaultIdleTimeoutMs,
      'processes.default_idle_timeout_ms', 0, MAX_CARDINAL_VALUE);
    MaximumIdle := CardinalFromEdit(EMaximumIdleTimeoutMs,
      'processes.maximum_idle_timeout_ms', 0, MAX_CARDINAL_VALUE);
    if (MaximumIdle > 0) and (DefaultIdle > MaximumIdle) then
      raise Exception.Create('processes.default_idle_timeout_ms must not exceed maximum_idle_timeout_ms.');
    CardinalFromEdit(ETerminationGraceMs, 'processes.termination_grace_ms',
      0, MAX_CARDINAL_VALUE);
    CardinalFromEdit(EMaximumOutputBytes, 'processes.maximum_output_bytes',
      1, MAX_CARDINAL_VALUE);
    CardinalFromEdit(EMaxOutputChars, 'processes.max_output_chars', 0, 100000);
    if (CBConsoleOutputMode.Text <> 'raw') and
       (CBConsoleOutputMode.Text <> 'prefixed') then
      raise Exception.Create('processes.console_output_mode must be raw or prefixed.');
    CardinalFromEdit(EInteractivePromptRepeatLimit,
      'processes.interactive_prompt_repeat_limit', 3, MAX_CARDINAL_VALUE);
    CardinalFromEdit(EInteractivePromptWindowMs,
      'processes.interactive_prompt_window_ms', 100, MAX_CARDINAL_VALUE);
    CardinalFromEdit(EInteractivePromptMaxChars,
      'processes.interactive_prompt_max_chars', 4, 1024);

    CardinalFromEdit(ETerminalMaximumSessions,
      'terminal.maximum_sessions', 1, High(Integer));
    CardinalFromEdit(ETerminalMaximumOutputBytes,
      'terminal.maximum_output_bytes', 4096, High(Integer));
    CardinalFromEdit(ETerminalMaximumReadBytes,
      'terminal.maximum_read_bytes', 1, High(Integer));
    CardinalFromEdit(ETerminalMaximumWriteBytes,
      'terminal.maximum_write_bytes', 1, High(Integer));
    CardinalFromEdit(ETerminalDefaultColumns,
      'terminal.default_columns', 1, 32767);
    CardinalFromEdit(ETerminalDefaultRows,
      'terminal.default_rows', 1, 32767);
    CardinalFromEdit(ETerminalMaximumReadWaitMs,
      'terminal.maximum_read_wait_ms', 1, MAX_CARDINAL_VALUE);
    CardinalFromEdit(ETerminalTerminationGraceMs,
      'terminal.termination_grace_ms', 0, MAX_CARDINAL_VALUE);

    CardinalFromEdit(EDesktopMaximumImageBytes,
      'desktop.maximum_image_bytes', 32768, MAX_CARDINAL_VALUE);

    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

procedure TConfigForm.SaveConfig(const AFileName: string);
var
  Root, Section, Features: TJSONObject;
  Origins: TJSONArray;
  Source: TStringList;
  I: Integer;
  S, ErrorText, EndpointValue: string;
begin
  if not ValidateControls(ErrorText) then
    raise Exception.Create(ErrorText);

  Root := TJSONObject.Create;
  Source := TStringList.Create;
  try
    Section := TJSONObject.Create;
    Root.Add('server', Section);
    Section.Add('address', Trim(EAddress.Text));
    Section.Add('port', Int64(CardinalFromEdit(EPort, 'server.port', 1, 65535)));
    EndpointValue := Trim(EEndpoint.Text);
    if EndpointValue[1] <> '/' then
      EndpointValue := '/' + EndpointValue;
    Section.Add('endpoint', EndpointValue);
    Section.Add('maximum_request_bytes', Int64(CardinalFromEdit(
      EMaximumRequestBytes, 'server.maximum_request_bytes', 1, MAX_CARDINAL_VALUE)));

    Section := TJSONObject.Create;
    Root.Add('authentication', Section);
    Section.Add('bearer_token', EBearerToken.Text);

    Section := TJSONObject.Create;
    Root.Add('cors', Section);
    Section.Add('enabled', CCorsEnabled.Checked);
    Origins := TJSONArray.Create;
    Section.Add('allowed_origins', Origins);
    for I := 0 to MAllowedOrigins.Lines.Count - 1 do
    begin
      S := Trim(MAllowedOrigins.Lines[I]);
      while (Length(S) > 0) and (S[Length(S)] = '/') do
        Delete(S, Length(S), 1);
      if S <> '' then
        Origins.Add(S);
    end;

    Section := TJSONObject.Create;
    Root.Add('filesystem', Section);
    Section.Add('enabled', CFilesystemEnabled.Checked);
    Section.Add('workspace_root', Trim(EWorkspaceRoot.Text));
    Section.Add('allow_delete', CAllowDelete.Checked);

    Section := TJSONObject.Create;
    Root.Add('processes', Section);
    Section.Add('enabled', CProcessesEnabled.Checked);
    Section.Add('allow_process_exec', CAllowProcessExec.Checked);
    Section.Add('allow_shell_exec', CAllowShellExec.Checked);
    Section.Add('allow_process_start', CAllowProcessStart.Checked);
    Section.Add('allow_shell_start', CAllowShellStart.Checked);
    Section.Add('default_timeout_ms', Int64(CardinalFromEdit(EDefaultTimeoutMs,
      'processes.default_timeout_ms', 0, MAX_CARDINAL_VALUE)));
    Section.Add('maximum_timeout_ms', Int64(CardinalFromEdit(EMaximumTimeoutMs,
      'processes.maximum_timeout_ms', 0, MAX_CARDINAL_VALUE)));
    Section.Add('default_wait_ms', Int64(CardinalFromEdit(EDefaultWaitMs,
      'processes.default_wait_ms', 0, MAX_CARDINAL_VALUE)));
    Section.Add('maximum_wait_ms', Int64(CardinalFromEdit(EMaximumWaitMs,
      'processes.maximum_wait_ms', 1, MAX_CARDINAL_VALUE)));
    Section.Add('maximum_tracked_jobs', Int64(CardinalFromEdit(EMaximumTrackedJobs,
      'processes.maximum_tracked_jobs', 8, High(Integer))));
    Section.Add('default_idle_timeout_ms', Int64(CardinalFromEdit(
      EDefaultIdleTimeoutMs, 'processes.default_idle_timeout_ms', 0, MAX_CARDINAL_VALUE)));
    Section.Add('maximum_idle_timeout_ms', Int64(CardinalFromEdit(
      EMaximumIdleTimeoutMs, 'processes.maximum_idle_timeout_ms', 0, MAX_CARDINAL_VALUE)));
    Section.Add('termination_grace_ms', Int64(CardinalFromEdit(ETerminationGraceMs,
      'processes.termination_grace_ms', 0, MAX_CARDINAL_VALUE)));
    Section.Add('detach_from_terminal', CDetachFromTerminal.Checked);
    Section.Add('maximum_output_bytes', Int64(CardinalFromEdit(EMaximumOutputBytes,
      'processes.maximum_output_bytes', 1, MAX_CARDINAL_VALUE)));
    Section.Add('max_output_chars', Int64(CardinalFromEdit(EMaxOutputChars,
      'processes.max_output_chars', 0, 100000)));
    Section.Add('mirror_output_to_console', CMirrorOutputToConsole.Checked);
    Section.Add('console_output_mode', CBConsoleOutputMode.Text);
    Section.Add('detect_interactive_prompt_loops', CDetectInteractivePromptLoops.Checked);
    Section.Add('interactive_prompt_repeat_limit', Int64(CardinalFromEdit(
      EInteractivePromptRepeatLimit, 'processes.interactive_prompt_repeat_limit', 3, MAX_CARDINAL_VALUE)));
    Section.Add('interactive_prompt_window_ms', Int64(CardinalFromEdit(
      EInteractivePromptWindowMs, 'processes.interactive_prompt_window_ms', 100, MAX_CARDINAL_VALUE)));
    Section.Add('interactive_prompt_max_chars', Int64(CardinalFromEdit(
      EInteractivePromptMaxChars, 'processes.interactive_prompt_max_chars', 4, 1024)));

    Section := TJSONObject.Create;
    Root.Add('terminal', Section);
    Section.Add('enabled', CTerminalEnabled.Checked);
    Section.Add('maximum_sessions', Int64(CardinalFromEdit(
      ETerminalMaximumSessions, 'terminal.maximum_sessions', 1, High(Integer))));
    Section.Add('maximum_output_bytes', Int64(CardinalFromEdit(
      ETerminalMaximumOutputBytes, 'terminal.maximum_output_bytes', 4096, High(Integer))));
    Section.Add('maximum_read_bytes', Int64(CardinalFromEdit(
      ETerminalMaximumReadBytes, 'terminal.maximum_read_bytes', 1, High(Integer))));
    Section.Add('maximum_write_bytes', Int64(CardinalFromEdit(
      ETerminalMaximumWriteBytes, 'terminal.maximum_write_bytes', 1, High(Integer))));
    Section.Add('default_columns', Int64(CardinalFromEdit(
      ETerminalDefaultColumns, 'terminal.default_columns', 1, 32767)));
    Section.Add('default_rows', Int64(CardinalFromEdit(
      ETerminalDefaultRows, 'terminal.default_rows', 1, 32767)));
    Section.Add('maximum_read_wait_ms', Int64(CardinalFromEdit(
      ETerminalMaximumReadWaitMs, 'terminal.maximum_read_wait_ms', 1, MAX_CARDINAL_VALUE)));
    Section.Add('termination_grace_ms', Int64(CardinalFromEdit(
      ETerminalTerminationGraceMs, 'terminal.termination_grace_ms', 0, MAX_CARDINAL_VALUE)));

    Section := TJSONObject.Create;
    Root.Add('desktop', Section);
    Section.Add('enabled', CDesktopEnabled.Checked);
    Section.Add('maximum_image_bytes', Int64(CardinalFromEdit(
      EDesktopMaximumImageBytes, 'desktop.maximum_image_bytes', 32768, MAX_CARDINAL_VALUE)));
    Features := TJSONObject.Create;
    Section.Add('features', Features);
    Features.Add('window_management', CDesktopWindowManagement.Checked);
    Features.Add('screen_capture', CDesktopCapture.Checked);
    Features.Add('input', CDesktopInput.Checked);

    Section := TJSONObject.Create;
    Root.Add('logging', Section);
    Section.Add('file', Trim(ELogFile.Text));
    Section.Add('log_process_commands', CLogProcessCommands.Checked);
    Section.Add('log_process_output', CLogProcessOutput.Checked);

    Source.Text := Root.FormatJSON([], 2);
    ForceDirectories(ExtractFileDir(ExpandFileName(AFileName)));
    Source.SaveToFile(AFileName);
    FConfigFileName := ExpandFileName(AFileName);
    FDirty := False;
    EEndpoint.Text := EndpointValue;
    UpdateCaption;
    FStatusBar.SimpleText := 'Saved: ' + FConfigFileName;
  finally
    Source.Free;
    Root.Free;
  end;
end;

procedure TConfigForm.UpdateCaption;
begin
  Caption := 'MCP Server Configurator';
  if FConfigFileName <> '' then
  begin
    Caption := Caption + ' - ' + ExtractFileName(FConfigFileName);
    FPathLabel.Caption := FConfigFileName;
    FPathLabel.Hint := FConfigFileName;
  end
  else
    FPathLabel.Caption := 'No file selected';
  if FDirty then
    Caption := Caption + ' *';
end;

procedure TConfigForm.ControlChanged(Sender: TObject);
begin
  if FLoading then
    Exit;
  FDirty := True;
  UpdateCaption;
end;

procedure TConfigForm.ApplicationHint(Sender: TObject);
begin
  if Application.Hint <> '' then
    FStatusBar.SimpleText := Application.Hint;
end;

procedure TConfigForm.OpenClick(Sender: TObject);
begin
  if (FConfigFileName <> '') then
  begin
    FOpenDialog.InitialDir := ExtractFileDir(FConfigFileName);
    FOpenDialog.FileName := ExtractFileName(FConfigFileName);
  end;
  if FOpenDialog.Execute then
  begin
    try
      LoadConfig(FOpenDialog.FileName);
    except
      on E: Exception do
        MessageDlg('Could not load configuration', E.Message,
          mtError, [mbOK], 0);
    end;
  end;
end;

function TConfigForm.SaveCurrent: Boolean;
begin
  Result := False;
  try
    if FConfigFileName = '' then
    begin
      SaveAsClick(Self);
      Result := not FDirty;
    end
    else
    begin
      SaveConfig(FConfigFileName);
      Result := True;
    end;
  except
    on E: Exception do
      MessageDlg('Could not save configuration', E.Message,
        mtError, [mbOK], 0);
  end;
end;

procedure TConfigForm.SaveClick(Sender: TObject);
begin
  SaveCurrent;
end;

procedure TConfigForm.SaveAsClick(Sender: TObject);
begin
  if FConfigFileName <> '' then
  begin
    FSaveDialog.InitialDir := ExtractFileDir(FConfigFileName);
    FSaveDialog.FileName := ExtractFileName(FConfigFileName);
  end
  else
    FSaveDialog.FileName := 'mcp-server.json';
  if FSaveDialog.Execute then
  begin
    try
      SaveConfig(FSaveDialog.FileName);
    except
      on E: Exception do
        MessageDlg('Could not save configuration', E.Message,
          mtError, [mbOK], 0);
    end;
  end;
end;

procedure TConfigForm.DefaultsClick(Sender: TObject);
begin
  if MessageDlg('Load defaults',
    'Replace all current field values with the defaults defined by the server code?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  FLoading := True;
  try
    ResetDefaults;
  finally
    FLoading := False;
  end;
  FDirty := True;
  UpdateCaption;
  FStatusBar.SimpleText := 'Defaults loaded - not saved yet.';
end;

procedure TConfigForm.ValidateClick(Sender: TObject);
var
  ErrorText: string;
begin
  if ValidateControls(ErrorText) then
    MessageDlg('Configuration is valid',
      'All fields are syntactically valid and within the server limits.',
      mtInformation, [mbOK], 0)
  else
    MessageDlg('Invalid configuration', ErrorText, mtError, [mbOK], 0);
end;

procedure TConfigForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Choice: TModalResult;
begin
  CanClose := True;
  if not FDirty then
    Exit;
  Choice := MessageDlg('Unsaved changes',
    'The configuration has changed. Save before closing?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case Choice of
    mrYes: CanClose := SaveCurrent;
    mrNo: CanClose := True;
  else
    CanClose := False;
  end;
end;

end.
