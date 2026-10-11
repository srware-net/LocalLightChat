program llc_mcp_gateway;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  cwstring,
  {$ENDIF}
  Classes, SysUtils, GatewayConfig, GatewayLog, GatewayHttpServer;

var
  Config: TGatewayConfig;
  Logger: TGatewayLogger;
  Application: TGatewayHttpApplication;
begin
  { MCP/JSON-RPC text on both HTTP and stdio is UTF-8.  Without this,
    implicit UnicodeString <-> AnsiString conversions may use the process
    locale (for example LANG=C) and irreversibly degrade characters such as
    em dash, bullets, arrows, checkmarks or emoji to '?'. }
  SetMultiByteConversionCodePage(CP_UTF8);

  Config := TGatewayConfig.Create;
  Logger := nil;
  Application := nil;
  try
    try
      Config.Load;
      if Config.ShowHelp then
      begin
        Config.PrintHelp;
        Halt(0);
      end;
      if Config.ShowVersion then
      begin
        Config.PrintVersion;
        Halt(0);
      end;

      Logger := TGatewayLogger.Create(Config.LogLevel, Config.LogFileName);
      Application := TGatewayHttpApplication.Create(Config, Logger);
      Application.Run;
    except
      on E: EGatewayConfig do
      begin
        WriteLn(StdErr, 'Konfigurationsfehler: ', E.Message);
        WriteLn(StdErr, 'Mit --help werden die Optionen angezeigt.');
        Halt(2);
      end;
      on E: Exception do
      begin
        if Logger <> nil then
          Logger.Error('Fatal: ' + E.Message)
        else
          WriteLn(StdErr, 'Fatal: ', E.Message);
        Halt(1);
      end;
    end;
  finally
    Application.Free;
    Logger.Free;
    Config.Free;
  end;
end.
