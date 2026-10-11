unit ToolRegistry;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpjson, ServerConfig, ServerLog, ToolProvider;

type
  TToolRegistry = class
  private
    FProviders: TFPObjectList;
    procedure RegisterProvider(AProvider: TToolProvider);
  public
    constructor Create(AConfig: TServerConfig; ALogger: TServerLogger);
    destructor Destroy; override;
    function ListTools: TJSONObject;
    function CallTool(const AName: string; AArguments: TJSONObject;
      const ACorrelationId: string): TJSONObject;
  end;

implementation

uses
  McpProtocol, FilesystemToolProvider, ProcessToolProvider,
  TerminalToolProvider, DesktopToolProvider;

constructor TToolRegistry.Create(AConfig: TServerConfig;
  ALogger: TServerLogger);
begin
  inherited Create;
  FProviders := TFPObjectList.Create(True);

  if AConfig.FilesystemEnabled then
    RegisterProvider(TFilesystemToolProvider.Create(
      AConfig.WorkspaceRoot, AConfig.AllowDelete));

  if AConfig.ProcessesEnabled and
    (AConfig.AllowProcessExec or AConfig.AllowShellExec or
     AConfig.AllowProcessStart or AConfig.AllowShellStart) then
    RegisterProvider(TProcessToolProvider.Create(AConfig, ALogger));

  if AConfig.TerminalEnabled then
    RegisterProvider(TTerminalToolProvider.Create(AConfig, ALogger));

  if AConfig.DesktopEnabled then
    RegisterProvider(TDesktopToolProvider.Create(AConfig, ALogger));
end;

destructor TToolRegistry.Destroy;
begin
  FProviders.Free;
  inherited Destroy;
end;

procedure TToolRegistry.RegisterProvider(AProvider: TToolProvider);
begin
  if AProvider = nil then
    Exit;
  FProviders.Add(AProvider);
end;

function TToolRegistry.ListTools: TJSONObject;
var
  Tools: TJSONArray;
  I: Integer;
begin
  Tools := TJSONArray.Create;
  for I := 0 to FProviders.Count - 1 do
    TToolProvider(FProviders[I]).AddTools(Tools);

  Result := TJSONObject.Create;
  Result.Add('tools', Tools);
end;

function TToolRegistry.CallTool(const AName: string;
  AArguments: TJSONObject; const ACorrelationId: string): TJSONObject;
var
  I: Integer;
  Provider: TToolProvider;
begin
  try
    for I := 0 to FProviders.Count - 1 do
    begin
      Provider := TToolProvider(FProviders[I]);
      if Provider.HandlesTool(AName) then
        Exit(Provider.CallTool(AName, AArguments, ACorrelationId));
    end;
    Result := NewToolTextResult('Unknown or disabled tool: ' + AName,
      nil, True);
  except
    on E: Exception do
      Result := NewToolTextResult(E.Message, nil, True);
  end;
end;

end.
