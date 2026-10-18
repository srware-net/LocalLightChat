program LocalLightChat;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Dialogs, SysUtils,
  uMain in 'src/uMain.pas',
  uServices in 'src/uServices.pas',
  uPrerequisites in 'src/uPrerequisites.pas',
  uBranding in 'src/uBranding.pas',
  uSingleInstance in 'src/uSingleInstance.pas';

// Lazarus generates LocalLightChat.res for the Windows manifest.
// Its Common Controls v6 dependency activates native Windows visual styles.
// Keep MAINICON and the logo in their own independently compiled resources.
{$R *.res}
{$R resources/LLCIcon.res}
{$R resources/LLCLogo.res}

// Keep the previous user configuration directory even after the executable
// is renamed from LocalLightChatManager to LocalLightChat.
function LegacyApplicationName: string;
begin
  Result := 'LocalLightChatManager';
end;

begin
  OnGetApplicationName := @LegacyApplicationName;
  RequireDerivedFormResource := False;
  Application.Scaled:=True;
  Application.Initialize;
  try
    if AcquireSingleInstance then
    begin
      try
        {$IFDEF WINDOWS}
        // Windows: launch into the tray; the panel is opened on demand.
        Application.ShowMainForm := False;
        {$ENDIF}
        Application.CreateForm(TManagerForm, ManagerForm);
        Application.Run;
      finally
        ReleaseSingleInstance;
      end;
    end
    else
    begin
      {$IFDEF WINDOWS}
      MessageDlg('LocalLightChat is already running',
        'LocalLightChat is already running in the system tray.' + LineEnding +
        'Click the LocalLightChat icon next to the clock to open the Control Panel.',
        mtInformation, [mbOK], 0);
      {$ELSE}
      MessageDlg('LocalLightChat is already running',
        'LocalLightChat is already running.' + LineEnding +
        'Check your taskbar or system tray to open the Control Panel.',
        mtInformation, [mbOK], 0);
      {$ENDIF}
    end;
  except
    on E: Exception do
      MessageDlg('LocalLightChat - Startup error', E.Message,
        mtError, [mbOK], 0);
  end;
end.
