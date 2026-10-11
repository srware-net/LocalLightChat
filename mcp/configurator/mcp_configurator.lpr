program mcp_configurator;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, MainForm;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.ShowHint := True;
  Application.CreateForm(TConfigForm, ConfigForm);
  Application.Run;
end.
