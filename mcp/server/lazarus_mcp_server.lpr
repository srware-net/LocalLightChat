program lazarus_mcp_server;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  cwstring,
  {$ENDIF}
  Classes, SysUtils, ServerConfig, McpHttpServer;

var
  Config: TServerConfig;
  ServerApplication: TMcpServerApplication;
  ConfigFile: string;
begin
  { This server treats JSON/tool text as UTF-8. Do not let the process locale
    (for example LANG=C under a service manager) turn Unicode into ?. }
  SetMultiByteConversionCodePage(CP_UTF8);

  Config := TServerConfig.Create;
  try
    if ParamCount > 0 then
      ConfigFile := ExpandFileName(ParamStr(1))
    else
    begin
      ConfigFile := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
        'mcp-server.json';
      if not FileExists(ConfigFile) then
        ConfigFile := ExpandFileName(IncludeTrailingPathDelimiter(
          ExtractFilePath(ParamStr(0))) + '..' + DirectorySeparator +
          'mcp-server.json');
    end;
    Config.LoadFromFile(ConfigFile);

    ServerApplication := TMcpServerApplication.Create(Config);
    try
      ServerApplication.Run;
    finally
      ServerApplication.Free;
    end;
  finally
    Config.Free;
  end;
end.
