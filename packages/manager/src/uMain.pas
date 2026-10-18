unit uMain;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Menus, LCLIntf, LCLType, IniFiles, Types, Process, uServices, uBranding
  {$IFDEF UNIX}, FileUtil{$ENDIF}
  {$IFDEF WINDOWS}, uModernButton{$ENDIF};

type
  {$IFDEF WINDOWS}
  TManagerButton = TModernButton;
  {$ELSE}
  TManagerButton = TButton;
  {$ENDIF}

  TManagerForm = class(TForm)
  private
    FServices: TLocalServices;
    FTray: TTrayIcon;
    FMenu: TPopupMenu;
    FStartItem, FStopItem, FChatItem, FStatusItem: TMenuItem;
    FServiceButton, FChatButton, FConfigButton: TManagerButton;
    FConfigMenu: TPopupMenu;
    FLogo: TImage;
    FStatus: TLabel;
    FTimer: TTimer;
    {$IFDEF UNIX}
    FBrowserLaunchers: TList; // Track xdg-open helpers, never own the browser itself.
    {$ENDIF}
    FStartupDone, FQuitting, FHideInProgress, FAutoBrowserPending: Boolean;
    FWithoutRAG, FWithoutAgent, FDoNotAutoOpenChat: Boolean;
    FHintCount: Integer;
    {$IFDEF UNIX}
    procedure CleanupBrowserLaunchers;
    function LaunchLinuxTarget(const Target: string; IsURL: Boolean): Boolean;
    {$ENDIF}
    procedure BuildUI;
    procedure BuildTray;
    procedure AddMenuItem(const ACaption: string; AHandler: TNotifyEvent;
      out AItem: TMenuItem);
    procedure SetBrandIcon;
    procedure LogLine(const S: string);
    procedure RefreshStatus;
    procedure StartupTick(Sender: TObject);
    procedure DoStart(Sender: TObject);
    procedure DoStop(Sender: TObject);
    procedure ToggleServices(Sender: TObject);
    procedure ShowConfigMenu(Sender: TObject);
    procedure OpenRAGConfig(Sender: TObject);
    procedure OpenAgentConfig(Sender: TObject);
    procedure OpenServiceConfig(const ARelativePath, ALabel: string);
    procedure DoRestart(Sender: TObject);
    procedure OpenBrowser(Sender: TObject);
    procedure OpenPanel(Sender: TObject);
    procedure OpenOptions(Sender: TObject);
    procedure OptionsOKClick(Sender: TObject);
    procedure OptionsCancelClick(Sender: TObject);
    procedure OptionsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure QuitProgram(Sender: TObject);
    procedure TrayClick(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure FormResized(Sender: TObject);
    procedure HideToTray;
    procedure TrayNotice;
    procedure SaveTrayHintCount;
    procedure ShowStartError(const S: string);
    function SettingsFile: string;
    procedure LoadSettings;
    procedure SaveSettings;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  ManagerForm: TManagerForm;

implementation

constructor TManagerForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'LocalLightChat';
  // Fixed-size utility window: minimize is available, maximize/resize is not.
  // bsSingle retains the normal title bar, with no sizing border.
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  ClientWidth := 432;
  ClientHeight := 224; // Slightly more breathing room below Options.
  Position := poScreenCenter;
  Scaled := True;
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  Color := clWhite;
  {$IFDEF UNIX}
  FBrowserLaunchers := TList.Create;
  {$ENDIF}

  BuildUI;
  SetBrandIcon;
  LoadSettings;
  FServices := TLocalServices.Create(ExtractFilePath(ParamStr(0)));
  FServices.OnLog := @LogLine;
  BuildTray;
  OnCloseQuery := @Closing;
  OnResize := @FormResized;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 700;
  FTimer.OnTimer := @StartupTick;
  FTimer.Enabled := True;
  RefreshStatus;
end;

destructor TManagerForm.Destroy;
{$IFDEF UNIX}
var
  I: Integer;
{$ENDIF}
begin
  {$IFDEF UNIX}
  // TProcess.Destroy only releases bookkeeping; it does not stop a browser.
  if Assigned(FBrowserLaunchers) then
  begin
    for I := 0 to FBrowserLaunchers.Count - 1 do
      TProcess(FBrowserLaunchers[I]).Free;
    FBrowserLaunchers.Free;
  end;
  {$ENDIF}
  FServices.Free;
  inherited Destroy;
end;

procedure TManagerForm.SetBrandIcon;
{$IFNDEF WINDOWS}
var
  B: TBitmap;
{$ENDIF}
begin
  // Windows: Application.Initialize has already loaded the native MAINICON
  // RT_GROUP_ICON from LLCIcon.res; do not reload a raw .ico stream.
  {$IFNDEF WINDOWS}
  B := TBitmap.Create;
  try
    B.SetSize(64, 64);
    B.Canvas.StretchDraw(Rect(0, 0, 64, 64), FLogo.Picture.Graphic);
    try
      Application.Icon.Assign(B);
    except
      // Do not prevent startup on desktops with limited icon support.
    end;
  finally
    B.Free;
  end;
  {$ENDIF}
  Icon.Assign(Application.Icon);
end;

procedure TManagerForm.BuildUI;
var
  TitleLabel: TLabel;
  ConfigItem: TMenuItem;
  OptionsButton, QuitButton: TManagerButton;
begin
  FLogo := TImage.Create(Self);
  FLogo.Parent := Self;
  FLogo.SetBounds(24, 19, 52, 52);
  FLogo.Center := True;
  // Resource image chosen at its actual display resolution (avoids jaggies).
  LoadEmbeddedLLCLogo(FLogo);

  TitleLabel := TLabel.Create(Self);
  TitleLabel.Parent := Self;
  TitleLabel.Caption := 'LocalLightChat';
  TitleLabel.Font.Size := 18;
  TitleLabel.Font.Style := [fsBold];
  // The form has a white background even when the GTK desktop uses a dark theme.
  // Do not inherit the theme's (often white) label foreground colour.
  TitleLabel.ParentFont := False;
  TitleLabel.Font.Color := RGBToColor(30, 32, 36);
  TitleLabel.SetBounds(92, 23, 307, 32);

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Caption := 'Starting...';
  FStatus.Font.Size := 10;
  FStatus.SetBounds(93, 57, 306, 24);
  FStatus.Anchors := [akLeft, akTop, akRight];

  // One state-aware service button; the separate Start/Stop tray menu stays.
  FServiceButton := TManagerButton.Create(Self);
  FServiceButton.Parent := Self;
  FServiceButton.Caption := 'Start';
  FServiceButton.SetBounds(24, 103, 115, 38);
  FServiceButton.OnClick := @ToggleServices;

  FChatButton := TManagerButton.Create(Self);
  FChatButton.Parent := Self;
  FChatButton.Caption := 'Open Chat';
  {$IFDEF WINDOWS}
  FChatButton.Primary := True;
  {$ENDIF}
  FChatButton.SetBounds(149, 103, 115, 38);
  FChatButton.OnClick := @OpenBrowser;

  FConfigMenu := TPopupMenu.Create(Self);
  ConfigItem := TMenuItem.Create(FConfigMenu);
  ConfigItem.Caption := 'Open RAG Config';
  ConfigItem.OnClick := @OpenRAGConfig;
  FConfigMenu.Items.Add(ConfigItem);

  ConfigItem := TMenuItem.Create(FConfigMenu);
  ConfigItem.Caption := 'Open Agent Config';
  ConfigItem.OnClick := @OpenAgentConfig;
  FConfigMenu.Items.Add(ConfigItem);

  FConfigButton := TManagerButton.Create(Self);
  FConfigButton.Parent := Self;
  FConfigButton.Caption := 'Config ' + #$E2#$96#$BE; // ▼ (UTF-8)
  FConfigButton.SetBounds(274, 103, 134, 38);
  FConfigButton.OnClick := @ShowConfigMenu;
  FConfigButton.Anchors := [akTop, akRight];

  // Explicit Quit: the X button on Windows only hides the panel to tray.
  QuitButton := TManagerButton.Create(Self);
  QuitButton.Parent := Self;
  QuitButton.Caption := 'Quit';
  QuitButton.SetBounds(24, 160, 110, 30);
  QuitButton.OnClick := @QuitProgram;

  OptionsButton := TManagerButton.Create(Self);
  OptionsButton.Parent := Self;
  OptionsButton.Caption := 'Options...';
  OptionsButton.SetBounds(298, 160, 110, 30);
  OptionsButton.Anchors := [akTop, akRight];
  OptionsButton.OnClick := @OpenOptions;
end;

procedure TManagerForm.AddMenuItem(const ACaption: string;
  AHandler: TNotifyEvent; out AItem: TMenuItem);
begin
  AItem := TMenuItem.Create(FMenu);
  AItem.Caption := ACaption;
  AItem.OnClick := AHandler;
  FMenu.Items.Add(AItem);
end;

procedure TManagerForm.BuildTray;
var
  M: TMenuItem;
begin
  FMenu := TPopupMenu.Create(Self);
  AddMenuItem('Status: checking', nil, FStatusItem);
  FStatusItem.Enabled := False;
  AddMenuItem('-', nil, M);
  AddMenuItem('Start', @DoStart, FStartItem);
  AddMenuItem('Stop', @DoStop, FStopItem);
  AddMenuItem('Restart', @DoRestart, M);
  AddMenuItem('Open Chat', @OpenBrowser, FChatItem);
  AddMenuItem('-', nil, M);
  AddMenuItem('Show Control Panel', @OpenPanel, M);
  AddMenuItem('Options...', @OpenOptions, M);
  AddMenuItem('-', nil, M);
  AddMenuItem('Quit', @QuitProgram, M);

  FTray := TTrayIcon.Create(Self);
  FTray.Visible := False;
  FTray.Hint := 'LocalLightChat';
  FTray.PopUpMenu := FMenu;
  FTray.OnClick := @TrayClick;
  FTray.BalloonTitle := 'LocalLightChat is still running';
  FTray.BalloonHint := 'LocalLightChat is in the system tray. Click its icon to open the Control Panel.';
  FTray.BalloonTimeout := 4000;
  // Always use original LLC artwork. Never substitute a fabricated fallback icon.
  FTray.Icon.Assign(Application.Icon);
  FTray.Visible := True;
end;

function TManagerForm.SettingsFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) +
    'LocalLightChatManager.ini';
end;

procedure TManagerForm.LoadSettings;
var
  Ini: TIniFile;
begin
  // Defaults: autostart the complete stack (RAG and Agent included).
  FWithoutRAG := False;
  FWithoutAgent := False;
  FDoNotAutoOpenChat := False;
  // The tray reminder limit is per user, not per process launch.
  FHintCount := 0;
  if not FileExists(SettingsFile) then Exit;
  Ini := TIniFile.Create(SettingsFile);
  try
    // Migrate the old combined option. Individual values override the legacy flag.
    FWithoutRAG := Ini.ReadBool('Start', 'WithoutRAG',
      Ini.ReadBool('Start', 'WithoutAgents', False));
    FWithoutAgent := Ini.ReadBool('Start', 'WithoutAgent',
      Ini.ReadBool('Start', 'WithoutAgents', False));
    // Old DoNotAutoStart intentionally not migrated: it controlled service startup.
    FDoNotAutoOpenChat := Ini.ReadBool('Start', 'DoNotAutoOpenChat', False);
    FHintCount := Ini.ReadInteger('Notifications', 'TrayHintCount', 0);
    if FHintCount < 0 then FHintCount := 0;
    if FHintCount > 2 then FHintCount := 2;
  finally
    Ini.Free;
  end;
end;

procedure TManagerForm.SaveSettings;
var
  Ini: TIniFile;
begin
  ForceDirectories(ExtractFileDir(SettingsFile));
  Ini := TIniFile.Create(SettingsFile);
  try
    Ini.WriteBool('Start', 'WithoutRAG', FWithoutRAG);
    Ini.WriteBool('Start', 'WithoutAgent', FWithoutAgent);
    Ini.WriteBool('Start', 'DoNotAutoOpenChat', FDoNotAutoOpenChat);
    Ini.DeleteKey('Start', 'DoNotAutoStart'); // Old setting had different semantics.
    Ini.DeleteKey('Start', 'WithoutAgents'); // Old combined option is obsolete.
  finally
    Ini.Free;
  end;
end;

procedure TManagerForm.LogLine(const S: string);
var
  FileName: string;
  F: TFileStream;
  L: UTF8String;
begin
  try
    FileName := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) +
      'manager.log';
    ForceDirectories(ExtractFileDir(FileName));
    if FileExists(FileName) then
      F := TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyNone)
    else
      F := TFileStream.Create(FileName, fmCreate);
    try
      F.Seek(0, soEnd);
      L := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '  ' + S + LineEnding;
      if Length(L) > 0 then F.WriteBuffer(L[1], Length(L));
    finally
      F.Free;
    end;
  except
    // Logging is optional.
  end;
end;

procedure TManagerForm.RefreshStatus;
var
  P, N, A, M, Running, Partial: Boolean;
begin
  if not Assigned(FServices) then Exit;
  P := FServices.PHPAlive;
  N := FServices.NginxAlive;
  A := FServices.RAGAlive;
  M := FServices.MCPAlive;
  // The options only affect the next start, not services already running.
  Running := P and N and
    ((not FServices.StartedWithRAG) or A) and
    ((not FServices.StartedWithAgent) or M);
  Partial := P or N or A or M;
  if Running then
  begin
    FStatus.Caption := '●  Running';
    FStatus.Font.Color := clGreen;
    FStatusItem.Caption := 'Status: running';
    FTray.Hint := 'LocalLightChat - Running';
  end
  else if Partial then
  begin
    FStatus.Caption := '●  Starting / partially running';
    FStatus.Font.Color := clMaroon;
    FStatusItem.Caption := 'Status: partial';
    FTray.Hint := 'LocalLightChat - Partial';
  end
  else
  begin
    FStatus.Caption := '●  Stopped';
    FStatus.Font.Color := clGray;
    FStatusItem.Caption := 'Status: stopped';
    FTray.Hint := 'LocalLightChat - Stopped';
  end;
  // A partial startup offers Stop so that the user can reset services.
  if Partial then
    FServiceButton.Caption := 'Stop'
  else
    FServiceButton.Caption := 'Start';
  FServiceButton.Enabled := True;
  FChatButton.Enabled := Running;
  FChatItem.Enabled := Running;
  {$IFDEF WINDOWS}
  // Custom-drawn controls need explicit repaints on state changes.
  FServiceButton.Invalidate;
  FChatButton.Invalidate;
  {$ENDIF}
  FStartItem.Enabled := not Partial;
  FStopItem.Enabled := Partial;
  if FAutoBrowserPending and Running then
  begin
    FAutoBrowserPending := False;
    OpenBrowser(nil);
  end;
end;

procedure TManagerForm.ShowStartError(const S: string);
begin
  LogLine('Error: ' + S);
  FAutoBrowserPending := False;
  OpenPanel(nil);
  MessageDlg('Unable to start LocalLightChat', S, mtError, [mbOK], 0);
end;

procedure TManagerForm.StartupTick(Sender: TObject);
begin
  {$IFDEF UNIX}
  CleanupBrowserLaunchers;
  {$ENDIF}
  if not FStartupDone then
  begin
    FStartupDone := True;
    FTimer.Interval := 2000;
    {$IFDEF WINDOWS}
    TrayNotice;
    {$ELSE}
    OpenPanel(nil);
    {$ENDIF}
    // Always start services on manager startup. This option only suppresses
    // opening the Chat browser once services are ready.
    DoStart(nil);
  end;
  RefreshStatus;
end;

procedure TManagerForm.DoStart(Sender: TObject);
begin
  if FServices.PHPAlive or FServices.NginxAlive or
    FServices.RAGAlive or FServices.MCPAlive then Exit;
  FStatus.Caption := 'Starting...';
  try
    FServices.Start(not FWithoutRAG, not FWithoutAgent);
    FAutoBrowserPending := not FDoNotAutoOpenChat;
  except
    on E: Exception do ShowStartError(E.Message);
  end;
  RefreshStatus;
end;

procedure TManagerForm.DoStop(Sender: TObject);
begin
  FAutoBrowserPending := False;
  try
    FServices.Stop;
  except
    on E: Exception do ShowStartError(E.Message);
  end;
  RefreshStatus;
end;

procedure TManagerForm.ToggleServices(Sender: TObject);
begin
  // An incomplete startup is treated as active: click Stop to reset it.
  if FServices.PHPAlive or FServices.NginxAlive or
     FServices.RAGAlive or FServices.MCPAlive then
    DoStop(Sender)
  else
    DoStart(Sender);
end;

procedure TManagerForm.ShowConfigMenu(Sender: TObject);
var
  P: TPoint;
begin
  // Left-click opens the popup directly below the third button.
  P := FConfigButton.ClientToScreen(Point(0, FConfigButton.Height));
  FConfigMenu.PopUp(P.X, P.Y);
end;

procedure TManagerForm.OpenServiceConfig(const ARelativePath, ALabel: string);
var
  ConfigPath: string;
  {$IFDEF WINDOWS}
  Editor: TProcess;
  {$ENDIF}
begin
  // These are the daemon working directories used by uServices.StartRAG/
  // StartAgent. Never fabricate a config or overwrite a user's changes.
  ConfigPath := ExpandFileName(FServices.Root + ARelativePath);
  if not FileExists(ConfigPath) then
  begin
    MessageDlg('LocalLightChat',
      ALabel + ' configuration was not found:' + LineEnding + ConfigPath +
      LineEnding + LineEnding +
      'Place the configuration in the service directory before opening it.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  {$IFDEF UNIX}
  // Use a desktop opener, or a directly installed text editor on minimal
  // Linux systems. Never wait for the editor to exit on the GUI thread.
  if not LaunchLinuxTarget(ConfigPath, False) then
    MessageDlg('LocalLightChat',
      'No application was found to open the configuration.' + LineEnding +
      'Install xdg-utils or a text editor (for example gnome-text-editor).',
      mtWarning, [mbOK], 0);
  {$ELSE}
  // Use a text editor explicitly: .conf/.json are not necessarily associated
  // with an editor on Windows and must remain editable even if malformed.
  Editor := TProcess.Create(nil);
  try
    Editor.Executable := 'notepad.exe';
    Editor.Parameters.Add(ConfigPath);
    Editor.Options := [poNoConsole];
    Editor.Execute;
  except
    on E: Exception do
      MessageDlg('LocalLightChat', 'Could not open config: ' + E.Message,
        mtError, [mbOK], 0);
  end;
  Editor.Free;
  {$ENDIF}
end;

procedure TManagerForm.OpenRAGConfig(Sender: TObject);
begin
  OpenServiceConfig('rag' + PathDelim + 'ragd.conf', 'RAG');
end;

procedure TManagerForm.OpenAgentConfig(Sender: TObject);
begin
  OpenServiceConfig('mcp' + PathDelim + 'server' + PathDelim +
    'mcp-server.json', 'Agent');
end;

procedure TManagerForm.DoRestart(Sender: TObject);
begin
  FAutoBrowserPending := False;
  try
    FServices.Restart(not FWithoutRAG, not FWithoutAgent);
    FAutoBrowserPending := not FDoNotAutoOpenChat;
  except
    on E: Exception do ShowStartError(E.Message);
  end;
  RefreshStatus;
end;

{$IFDEF UNIX}
procedure TManagerForm.CleanupBrowserLaunchers;
var
  I: Integer;
  Launcher: TProcess;
begin
  if not Assigned(FBrowserLaunchers) then Exit;
  for I := FBrowserLaunchers.Count - 1 downto 0 do
  begin
    Launcher := TProcess(FBrowserLaunchers[I]);
    // Running uses a non-blocking status check; never wait for the browser.
    if not Launcher.Running then
    begin
      if Launcher.ExitStatus <> 0 then
        LogLine(Format('%s finished with exit code %d',
          [ExtractFileName(Launcher.Executable), Launcher.ExitStatus]));
      FBrowserLaunchers.Delete(I);
      Launcher.Free;
    end;
  end;
end;

function TManagerForm.LaunchLinuxTarget(const Target: string; IsURL: Boolean): Boolean;
const
  // First use the desktop's default-file/URL opener; on lightweight or fresh
  // installations (e.g. Rocky) xdg-utils may not yet be installed.
  Openers: array[0..5] of string = (
    'xdg-open', 'gio', 'kde-open6', 'kde-open5', 'exo-open', 'gvfs-open');
  Browsers: array[0..8] of string = (
    'firefox', 'firefox-esr', 'chromium', 'chromium-browser', 'google-chrome',
    'google-chrome-stable', 'brave-browser', 'vivaldi', 'epiphany');
  Editors: array[0..5] of string = (
    'gnome-text-editor', 'gedit', 'kate', 'mousepad', 'xed', 'leafpad');
var
  I: Integer;

  function TryLauncher(const CommandName: string): Boolean;
  var
    Path: string;
    Launcher: TProcess;
  begin
    Result := False;
    Path := FindDefaultExecutablePath(CommandName);
    if Path = '' then Exit;

    Launcher := TProcess.Create(nil);
    try
      Launcher.Executable := Path;
      if CommandName = 'gio' then
        Launcher.Parameters.Add('open');
      Launcher.Parameters.Add(Target);
      // Never poWaitOnExit: opening a previously closed browser may leave
      // its launcher alive until the browser exits.
      Launcher.Options := [];
      Launcher.Execute;
      FBrowserLaunchers.Add(Launcher);
      LogLine('Opened with ' + CommandName + ': ' + Target);
      Result := True;
    except
      on E: Exception do
      begin
        LogLine('Unable to start ' + CommandName + ': ' + E.Message);
        Launcher.Free;
      end;
    end;
  end;

begin
  Result := False;
  for I := Low(Openers) to High(Openers) do
    if TryLauncher(Openers[I]) then Exit(True);

  if IsURL then
  begin
    for I := Low(Browsers) to High(Browsers) do
      if TryLauncher(Browsers[I]) then Exit(True);
  end
  else
  begin
    for I := Low(Editors) to High(Editors) do
      if TryLauncher(Editors[I]) then Exit(True);
  end;
end;
{$ENDIF}

procedure TManagerForm.OpenBrowser(Sender: TObject);
begin
  // The tray menu can invoke this even when the main panel is hidden.
  // Never open a dead service URL after Stop or during a partial start.
  if not (FServices.PHPAlive and FServices.NginxAlive and
    ((not FServices.StartedWithRAG) or FServices.RAGAlive) and
    ((not FServices.StartedWithAgent) or FServices.MCPAlive)) then Exit;
  {$IFDEF UNIX}
  // Open asynchronously. Fresh desktops may have a browser but lack xdg-open.
  if not LaunchLinuxTarget('http://127.0.0.1:8081/', True) then
    MessageDlg('LocalLightChat',
      'No browser or desktop URL opener was found.' + LineEnding +
      'Install a browser or xdg-utils (on Rocky Linux: sudo dnf install xdg-utils).',
      mtWarning, [mbOK], 0);
  {$ELSE}
  if not OpenURL('http://127.0.0.1:8081/') then
    MessageDlg('LocalLightChat', 'Could not open the browser.', mtWarning, [mbOK], 0);
  {$ENDIF}
end;

procedure TManagerForm.OpenPanel(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  LoadEmbeddedLLCLogo(FLogo); // DPI scaling may occur on first show.
  BringToFront;
end;

procedure TManagerForm.OptionsOKClick(Sender: TObject);
begin
  // Custom-drawn TModernButton has no ModalResult property.
  // Its parent is the temporary modal options form.
  if (Sender is TControl) and (TControl(Sender).Parent is TForm) then
    TForm(TControl(Sender).Parent).ModalResult := mrOK;
end;

procedure TManagerForm.OptionsCancelClick(Sender: TObject);
begin
  if (Sender is TControl) and (TControl(Sender).Parent is TForm) then
    TForm(TControl(Sender).Parent).ModalResult := mrCancel;
end;

procedure TManagerForm.OptionsKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // KeyPreview makes Enter / Escape work even with owner-drawn buttons.
  if (Shift <> []) or not (Sender is TForm) then Exit;
  case Key of
    VK_RETURN:
      begin
        TForm(Sender).ModalResult := mrOK;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        TForm(Sender).ModalResult := mrCancel;
        Key := 0;
      end;
  end;
end;

procedure TManagerForm.OpenOptions(Sender: TObject);
var
  D: TForm;
  TitleLabel, Note: TLabel;
  RAGCheck, AgentCheck, AutoOpenCheck, LANCheck: TCheckBox;
  PreviouslyLAN, LANAvailable: Boolean;
  LANError: string;
  OKButton, CancelButton: TManagerButton;
begin
  LANAvailable := True;
  LANError := '';
  PreviouslyLAN := False;
  try
    PreviouslyLAN := FServices.NetworkAccessEnabled;
  except
    on E: Exception do
    begin
      LANAvailable := False;
      LANError := E.Message;
      LogLine('Network mode unavailable: ' + LANError);
    end;
  end;
  D := TForm.CreateNew(Self, 1);
  try
    D.Caption := 'LocalLightChat - Options';
    D.BorderStyle := bsSingle;
    D.BorderIcons := [biSystemMenu];
    D.Position := poMainFormCenter;
    D.ClientWidth := 420;
    D.ClientHeight := 302;
    D.Scaled := True;
    D.KeyPreview := True;
    D.OnKeyDown := @OptionsKeyDown;
    D.Font.Name := Font.Name;
    D.Font.Size := Font.Size;
    D.Color := clWhite;

    TitleLabel := TLabel.Create(D);
    TitleLabel.Parent := D;
    TitleLabel.Caption := 'Startup options';
    TitleLabel.Font.Size := 12;
    TitleLabel.Font.Style := [fsBold];
    TitleLabel.ParentFont := False;
    TitleLabel.Font.Color := RGBToColor(30, 32, 36);
    TitleLabel.SetBounds(20, 16, 220, 24);

    RAGCheck := TCheckBox.Create(D);
    RAGCheck.Parent := D;
    RAGCheck.Caption := 'Start without RAG';
    RAGCheck.SetBounds(20, 52, 370, 28);
    RAGCheck.Checked := FWithoutRAG;
    RAGCheck.Color := clWhite;
    RAGCheck.ParentColor := False;

    AgentCheck := TCheckBox.Create(D);
    AgentCheck.Parent := D;
    AgentCheck.Caption := 'Start without Agent';
    AgentCheck.SetBounds(20, 86, 370, 28);
    AgentCheck.Checked := FWithoutAgent;
    AgentCheck.Color := clWhite;
    AgentCheck.ParentColor := False;

    AutoOpenCheck := TCheckBox.Create(D);
    AutoOpenCheck.Parent := D;
    AutoOpenCheck.Caption := 'Do not open Chat automatically';
    AutoOpenCheck.SetBounds(20, 120, 386, 28);
    AutoOpenCheck.Checked := FDoNotAutoOpenChat;
    AutoOpenCheck.Color := clWhite;
    AutoOpenCheck.ParentColor := False;

    LANCheck := TCheckBox.Create(D);
    LANCheck.Parent := D;
    LANCheck.Caption := 'Allow access from other devices (LAN)';
    LANCheck.SetBounds(20, 169, 386, 28);
    LANCheck.Checked := PreviouslyLAN;
    LANCheck.Enabled := LANAvailable;
    LANCheck.Color := clWhite;
    LANCheck.ParentColor := False;
    LANCheck.TabOrder := 3;

    Note := TLabel.Create(D);
    Note.Parent := D;
    if LANAvailable then
      Note.Caption := 'Changes apply on the next start / restart.'
    else
      Note.Caption := 'Network option unavailable (check nginx.conf).';
    Note.Font.Color := clGray;
    Note.SetBounds(22, 220, 375, 20);

    OKButton := TManagerButton.Create(D);
    OKButton.Parent := D;
    OKButton.Caption := 'OK';
    OKButton.SetBounds(226, 259, 82, 32);
    {$IFDEF WINDOWS}
    OKButton.Primary := True;
    {$ENDIF}
    OKButton.OnClick := @OptionsOKClick;
    OKButton.TabOrder := 4;

    CancelButton := TManagerButton.Create(D);
    CancelButton.Parent := D;
    CancelButton.Caption := 'Cancel';
    CancelButton.SetBounds(318, 259, 82, 32);
    CancelButton.OnClick := @OptionsCancelClick;
    CancelButton.TabOrder := 5;

    if D.ShowModal = mrOK then
    begin
      if LANAvailable and (LANCheck.Checked <> PreviouslyLAN) then
      begin
        try
          FServices.SetNetworkAccessEnabled(LANCheck.Checked);
        except
          on E: Exception do
          begin
            MessageDlg('Network settings',
              'Could not update nginx.conf: ' + E.Message,
              mtError, [mbOK], 0);
            Exit;
          end;
        end;
      end;
      FWithoutRAG := RAGCheck.Checked;
      FWithoutAgent := AgentCheck.Checked;
      FDoNotAutoOpenChat := AutoOpenCheck.Checked;
      SaveSettings;
      RefreshStatus;
    end;
  finally
    D.Free;
  end;
end;

procedure TManagerForm.TrayClick(Sender: TObject);
begin
  OpenPanel(Sender);
end;

procedure TManagerForm.SaveTrayHintCount;
var
  Ini: TIniFile;
begin
  // Save immediately, not only when the user changes Options or quits.
  ForceDirectories(ExtractFileDir(SettingsFile));
  Ini := TIniFile.Create(SettingsFile);
  try
    Ini.WriteInteger('Notifications', 'TrayHintCount', FHintCount);
  finally
    Ini.Free;
  end;
end;

procedure TManagerForm.TrayNotice;
begin
  {$IFDEF WINDOWS}
  if (FHintCount >= 2) or (not Assigned(FTray)) or
     (not FTray.Visible) then Exit;
  Inc(FHintCount);
  try
    // Persist before requesting the toast; a restart must not reset the limit.
    SaveTrayHintCount;
  except
    on E: Exception do
    begin
      Dec(FHintCount);
      LogLine('Unable to save tray reminder count: ' + E.Message);
      Exit;
    end;
  end;
  FTray.ShowBalloonHint;
  {$ENDIF}
end;

procedure TManagerForm.HideToTray;
begin
  if FHideInProgress then Exit;
  FHideInProgress := True;
  try
    Hide;
    TrayNotice;
  finally
    FHideInProgress := False;
  end;
end;

procedure TManagerForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  if FQuitting then
  begin
    CanClose := True;
    Exit;
  end;

  // Windows: X is non-destructive and keeps the services running.
  // The explicit Quit button (or tray menu) performs the shutdown.
  CanClose := False;
  {$IFDEF WINDOWS}
  HideToTray;
  {$ELSE}
  // Linux has no guaranteed system tray: X quits normally.
  QuitProgram(Sender);
  {$ENDIF}
end;

procedure TManagerForm.FormResized(Sender: TObject);
begin
  // Windows: minimize into the tray. Linux: normal minimize to taskbar.
  {$IFDEF WINDOWS}
  if (WindowState = wsMinimized) and (not FQuitting) then
    HideToTray;
  {$ENDIF}
end;

procedure TManagerForm.QuitProgram(Sender: TObject);
begin
  if FQuitting then Exit;
  FQuitting := True;
  FTimer.Enabled := False;
  try
    FServices.Stop;
  except
    on E: Exception do
      MessageDlg('LocalLightChat', 'Error while quitting: ' + E.Message,
        mtWarning, [mbOK], 0);
  end;
  FTray.Visible := False;
  Application.Terminate;
end;

end.
