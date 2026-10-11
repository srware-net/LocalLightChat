unit McpHttpServer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpserver, httpdefs, ServerConfig, ServerLog,
  ToolRegistry, McpDispatcher;

type
  { FPC 3.2.2 keeps TFPCustomHttpServer.Address protected and does not
    republish it in TFPHttpServer. This small descendant exposes it so the
    configured bind address remains usable on older and newer FPC releases. }
  TMcpBindableHttpServer = class(TFPHttpServer)
  published
    property Address;
  end;

  TMcpServerApplication = class
  private
    FConfig: TServerConfig;
    FLogger: TServerLogger;
    FTools: TToolRegistry;
    FDispatcher: TMcpDispatcher;
    FServer: TMcpBindableHttpServer;
    FRequestCounter: LongInt;
    procedure HandleRequest(Sender: TObject;
      var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
    procedure WriteJsonResponse(AResponse: TFPHTTPConnectionResponse;
      ACode: Integer; const ABody: string);
    function RequestPath(ARequest: TFPHTTPConnectionRequest): string;
    function RequestOrigin(ARequest: TFPHTTPConnectionRequest): string;
    function IsOriginAllowed(const AOrigin: string): Boolean;
    procedure ApplyCorsHeaders(const AOrigin: string;
      AResponse: TFPHTTPConnectionResponse);
    function IsAuthorized(ARequest: TFPHTTPConnectionRequest): Boolean;
  public
    constructor Create(AConfig: TServerConfig);
    destructor Destroy; override;
    procedure Run;
  end;

implementation

uses
  fpjson, jsonparser, McpProtocol;

constructor TMcpServerApplication.Create(AConfig: TServerConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := TServerLogger.Create(FConfig.LogFile);
  FTools := TToolRegistry.Create(FConfig, FLogger);
  FDispatcher := TMcpDispatcher.Create(FTools);
  FServer := TMcpBindableHttpServer.Create(nil);
  FServer.Address := FConfig.Address;
  FServer.Port := FConfig.Port;
  FServer.Threaded := True;
  FServer.QueueSize := 32;
  FServer.OnRequest := @HandleRequest;
end;

destructor TMcpServerApplication.Destroy;
begin
  if FServer <> nil then
    FServer.Active := False;
  FServer.Free;
  FDispatcher.Free;
  FTools.Free;
  FLogger.Free;
  inherited Destroy;
end;

function TMcpServerApplication.RequestPath(
  ARequest: TFPHTTPConnectionRequest): string;
var
  P: SizeInt;
begin
  Result := ARequest.URI;
  P := Pos('?', Result);
  if P > 0 then
    Delete(Result, P, MaxInt);
end;

function TMcpServerApplication.RequestOrigin(
  ARequest: TFPHTTPConnectionRequest): string;
begin
  Result := Trim(ARequest.GetFieldByName('Origin'));
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function TMcpServerApplication.IsOriginAllowed(const AOrigin: string): Boolean;
var
  I: Integer;
begin
  { Non-browser clients such as PHP, curl and the Lazarus debugger normally do
    not send Origin and are unaffected by CORS. Browser origins must be
    explicitly enabled and allow-listed. }
  if AOrigin = '' then
    Exit(True);
  if not FConfig.CorsEnabled then
    Exit(False);

  for I := 0 to FConfig.AllowedOrigins.Count - 1 do
    if SameText(AOrigin, FConfig.AllowedOrigins[I]) then
      Exit(True);
  Result := False;
end;

procedure TMcpServerApplication.ApplyCorsHeaders(const AOrigin: string;
  AResponse: TFPHTTPConnectionResponse);
begin
  if AOrigin = '' then
    Exit;

  AResponse.SetCustomHeader('Access-Control-Allow-Origin', AOrigin);
  AResponse.SetCustomHeader('Vary', 'Origin');
  AResponse.SetCustomHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers',
    'Accept, Authorization, Content-Type, MCP-Protocol-Version, ' +
    'MCP-Session-Id, Last-Event-ID, MCP-Method, MCP-Name');
  AResponse.SetCustomHeader('Access-Control-Expose-Headers',
    'MCP-Protocol-Version, MCP-Session-Id, X-Request-Id');
  AResponse.SetCustomHeader('Access-Control-Max-Age', '600');
end;

function TMcpServerApplication.IsAuthorized(
  ARequest: TFPHTTPConnectionRequest): Boolean;
begin
  if FConfig.BearerToken = '' then
    Exit(True);
  Result := ARequest.Authorization = 'Bearer ' + FConfig.BearerToken;
end;

procedure TMcpServerApplication.WriteJsonResponse(
  AResponse: TFPHTTPConnectionResponse; ACode: Integer; const ABody: string);
begin
  AResponse.Code := ACode;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.CustomHeaders.Values['MCP-Protocol-Version'] := MCP_PROTOCOL_VERSION;
  AResponse.CustomHeaders.Values['X-Content-Type-Options'] := 'nosniff';
  AResponse.Content := UTF8Encode(ABody);
end;

procedure TMcpServerApplication.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  RequestNumber: LongInt;
  CorrelationId, Body, Origin: string;
  JsonData: TJSONData;
  RequestObject: TJSONObject;
  ResponseObject: TJSONObject;
  IsNotification: Boolean;
begin
  RequestNumber := InterlockedIncrement(FRequestCounter);
  CorrelationId := Format('REQ-%.8d', [RequestNumber]);
  AResponse.CustomHeaders.Values['X-Request-Id'] := CorrelationId;
  FLogger.Write(Format('%s %s %s from %s', [CorrelationId,
    ARequest.Method, ARequest.URI, ARequest.RemoteAddress]));

  Origin := RequestOrigin(ARequest);
  if not IsOriginAllowed(Origin) then
  begin
    FLogger.Write(Format('%s rejected Origin: %s', [CorrelationId, Origin]));
    WriteJsonResponse(AResponse, 403, '{"error":"Origin not allowed"}');
    Exit;
  end;
  ApplyCorsHeaders(Origin, AResponse);

  if RequestPath(ARequest) <> FConfig.Endpoint then
  begin
    WriteJsonResponse(AResponse, 404,
      '{"error":"Endpoint not found"}');
    Exit;
  end;

  if SameText(ARequest.Method, 'OPTIONS') then
  begin
    { Preflight requests intentionally bypass Bearer authentication: browsers
      do not send Authorization on the OPTIONS probe. }
    AResponse.Code := 204;
    AResponse.Allow := 'POST, OPTIONS';
    AResponse.Content := '';
    Exit;
  end;

  if not SameText(ARequest.Method, 'POST') then
  begin
    AResponse.Allow := 'POST, OPTIONS';
    WriteJsonResponse(AResponse, 405,
      '{"error":"Only HTTP POST is implemented in this draft"}');
    Exit;
  end;

  if not IsAuthorized(ARequest) then
  begin
    AResponse.WWWAuthenticate := 'Bearer';
    WriteJsonResponse(AResponse, 401, '{"error":"Unauthorized"}');
    Exit;
  end;

  if Length(ARequest.Content) > FConfig.MaximumRequestBytes then
  begin
    WriteJsonResponse(AResponse, 413, '{"error":"Request body too large"}');
    Exit;
  end;

  if Pos('application/json', LowerCase(ARequest.ContentType)) = 0 then
  begin
    WriteJsonResponse(AResponse, 415,
      '{"error":"Content-Type must be application/json"}');
    Exit;
  end;

  JsonData := nil;
  ResponseObject := nil;
  try
    try
      try
        JsonData := GetJSON(ARequest.Content);
      except
        on E: Exception do
        begin
          ResponseObject := NewJsonRpcError(nil, JSONRPC_PARSE_ERROR,
            'Parse error: ' + E.Message);
          WriteJsonResponse(AResponse, 200, ResponseObject.AsJSON);
          Exit;
        end;
      end;

      if JsonData.JSONType <> jtObject then
      begin
        ResponseObject := NewJsonRpcError(nil, JSONRPC_INVALID_REQUEST,
          'Only single JSON-RPC objects are supported');
        WriteJsonResponse(AResponse, 200, ResponseObject.AsJSON);
        Exit;
      end;

      RequestObject := TJSONObject(JsonData);
      ResponseObject := FDispatcher.DispatchRequest(RequestObject,
        IsNotification, CorrelationId);
      if IsNotification then
      begin
        AResponse.Code := 202;
        AResponse.Content := '';
        Exit;
      end;

      Body := ResponseObject.AsJSON;
      WriteJsonResponse(AResponse, 200, Body);
      FLogger.Write(Format('%s response %d bytes',
        [CorrelationId, Length(Body)]));
    except
      on E: Exception do
      begin
        FLogger.Write(CorrelationId + ' internal error: ' + E.Message);
        FreeAndNil(ResponseObject);
        ResponseObject := NewJsonRpcError(nil, JSONRPC_INTERNAL_ERROR,
          'Internal error');
        WriteJsonResponse(AResponse, 500, ResponseObject.AsJSON);
      end;
    end;
  finally
    ResponseObject.Free;
    JsonData.Free;
  end;
end;

procedure TMcpServerApplication.Run;
begin
  FLogger.Write(Format('Starting MCP server on http://%s:%d%s',
    [FConfig.Address, FConfig.Port, FConfig.Endpoint]));
  FLogger.Write('Workspace: ' + FConfig.WorkspaceRoot);
  FLogger.Write(Format('Modules filesystem=%s processes=%s terminal=%s desktop=%s',
    [BoolToStr(FConfig.FilesystemEnabled, True),
     BoolToStr(FConfig.ProcessesEnabled, True),
     BoolToStr(FConfig.TerminalEnabled, True),
     BoolToStr(FConfig.DesktopEnabled, True)]));
  if FConfig.ProcessesEnabled then
    FLogger.Write(Format('Process console mirror=%s mode=%s',
      [BoolToStr(FConfig.MirrorProcessOutputToConsole, True),
       FConfig.ProcessConsoleOutputMode]));
  if FConfig.TerminalEnabled then
  begin
    FLogger.Write(Format(
      'Terminal console mirror output=%s input=%s mode=%s log_output=%s log_input=%s',
      [BoolToStr(FConfig.TerminalMirrorOutputToConsole, True),
       BoolToStr(FConfig.TerminalMirrorInputToConsole, True),
       FConfig.TerminalConsoleOutputMode,
       BoolToStr(FConfig.TerminalLogOutput, True),
       BoolToStr(FConfig.TerminalLogInput, True)]));
    FLogger.Write(Format(
      'Terminal observation max_bytes=%d quiet_ms=%d default_wait_ms=%d scrollback_lines=%d',
      [FConfig.TerminalMaximumObservationBytes,
       FConfig.TerminalObservationQuietMs,
       FConfig.TerminalObservationDefaultWaitMs,
       FConfig.TerminalMaximumScrollbackLines]));
  end;
  FLogger.Write('Press Ctrl+C to stop.');
  FServer.Active := True;
end;

end.
