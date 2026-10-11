unit McpDispatcher;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, ToolRegistry;

type
  TMcpDispatcher = class
  private
    FTools: TToolRegistry;
    function HandleInitialize(AParams: TJSONObject): TJSONObject;
    function HandleToolCall(AParams: TJSONObject;
      const ACorrelationId: string): TJSONObject;
  public
    constructor Create(ATools: TToolRegistry);
    function DispatchRequest(ARequest: TJSONObject;
      out AIsNotification: Boolean; const ACorrelationId: string): TJSONObject;
  end;

implementation

uses
  McpJson, McpProtocol;

constructor TMcpDispatcher.Create(ATools: TToolRegistry);
begin
  inherited Create;
  FTools := ATools;
end;

function TMcpDispatcher.HandleInitialize(AParams: TJSONObject): TJSONObject;
var
  Capabilities, ToolsCapability, ServerInfo: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('protocolVersion', MCP_PROTOCOL_VERSION);

  Capabilities := TJSONObject.Create;
  ToolsCapability := TJSONObject.Create;
  ToolsCapability.Add('listChanged', False);
  Capabilities.Add('tools', ToolsCapability);
  Result.Add('capabilities', Capabilities);

  ServerInfo := TJSONObject.Create;
  ServerInfo.Add('name', 'lazarus-mcp-server');
  ServerInfo.Add('version', '0.17.0-draft');
  Result.Add('serverInfo', ServerInfo);
  Result.Add('instructions',
    'Only tools enabled in the server configuration are advertised. Filesystem paths and process working directories remain restricted to the configured workspace. Desktop tools expose basic Windows window management, visual observation, and raw keyboard primitives when enabled; they do not claim general GUI automation.');
end;

function TMcpDispatcher.HandleToolCall(AParams: TJSONObject;
  const ACorrelationId: string): TJSONObject;
var
  ToolName: string;
  Arguments: TJSONObject;
begin
  if AParams = nil then
    raise Exception.Create('Missing params');
  ToolName := JsonString(AParams, 'name');
  if ToolName = '' then
    raise Exception.Create('Missing tool name');
  Arguments := JsonObject(AParams, 'arguments');
  if Arguments = nil then
    Arguments := TJSONObject.Create
  else
    Arguments := TJSONObject(Arguments.Clone);
  try
    Result := FTools.CallTool(ToolName, Arguments, ACorrelationId);
  finally
    Arguments.Free;
  end;
end;

function TMcpDispatcher.DispatchRequest(ARequest: TJSONObject;
  out AIsNotification: Boolean; const ACorrelationId: string): TJSONObject;
var
  RequestMethod: string;
  IdData: TJSONData;
  Params: TJSONObject;
  MethodResult: TJSONObject;
begin
  AIsNotification := False;
  Result := nil;
  if ARequest = nil then
    Exit(NewJsonRpcError(nil, JSONRPC_INVALID_REQUEST, 'Request must be an object'));

  if JsonString(ARequest, 'jsonrpc') <> '2.0' then
    Exit(NewJsonRpcError(ARequest.Find('id'), JSONRPC_INVALID_REQUEST,
      'jsonrpc must be "2.0"'));

  RequestMethod := JsonString(ARequest, 'method');
  if RequestMethod = '' then
    Exit(NewJsonRpcError(ARequest.Find('id'), JSONRPC_INVALID_REQUEST,
      'Missing method'));

  IdData := ARequest.Find('id');
  AIsNotification := IdData = nil;
  Params := JsonObject(ARequest, 'params');

  if AIsNotification then
  begin
    // The initialization notification currently needs no server-side state.
    Exit(nil);
  end;

  try
    MethodResult := nil;
    if RequestMethod = 'initialize' then
      MethodResult := HandleInitialize(Params)
    else if RequestMethod = 'ping' then
      MethodResult := TJSONObject.Create
    else if RequestMethod = 'tools/list' then
      MethodResult := FTools.ListTools
    else if RequestMethod = 'tools/call' then
      MethodResult := HandleToolCall(Params, ACorrelationId)
    else
      Exit(NewJsonRpcError(IdData, JSONRPC_METHOD_NOT_FOUND,
        'Method not found: ' + RequestMethod));

    Result := NewJsonRpcResult(IdData, MethodResult);
  except
    on E: Exception do
      Result := NewJsonRpcError(IdData, JSONRPC_INVALID_PARAMS, E.Message);
  end;
end;

end.
