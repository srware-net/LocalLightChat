unit GatewayHttpServer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpserver, httpdefs, GatewayConfig, GatewayLog,
  GatewaySession;

type
  TGatewayBindableHttpServer = class(TFPHttpServer)
  published
    property Address;
  end;

  TJsonRpcMessageKind = (jmkInvalid, jmkRequest, jmkNotification, jmkResponse);

  TGatewayHttpApplication = class
  private
    FConfig: TGatewayConfig;
    FLogger: TGatewayLogger;
    FSessions: TGatewaySessionManager;
    FServer: TGatewayBindableHttpServer;
    FRequestCounter: LongInt;
    procedure HandleRequest(Sender: TObject;
      var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
    function RequestPath(ARequest: TFPHTTPConnectionRequest): string;
    function RequestOrigin(ARequest: TFPHTTPConnectionRequest): string;
    function IsOriginAllowed(const AOrigin: string): Boolean;
    procedure ApplyCorsHeaders(const AOrigin: string;
      AResponse: TFPHTTPConnectionResponse);
    procedure ApplyConfiguredHeaders(AResponse: TFPHTTPConnectionResponse);
    procedure ApplyMcpHeaders(AResponse: TFPHTTPConnectionResponse;
      ASession: TGatewaySession);
    function IsAuthorized(ARequest: TFPHTTPConnectionRequest): Boolean;
    function IsHealthEndpoint(const APath: string): Boolean;
    function HeaderContains(ARequest: TFPHTTPConnectionRequest;
      const AHeader, AValue: string): Boolean;
    procedure WriteEmpty(AResponse: TFPHTTPConnectionResponse; ACode: Integer);
    procedure WriteJson(AResponse: TFPHTTPConnectionResponse; ACode: Integer;
      const ABody: string; ASession: TGatewaySession = nil);
    procedure WriteSse(AResponse: TFPHTTPConnectionResponse; ACode: Integer;
      const ABody: string; ASession: TGatewaySession = nil);
    procedure WriteJsonRpcError(AResponse: TFPHTTPConnectionResponse;
      AHttpCode, ARpcCode: Integer; const AMessage: string;
      AId: TObject = nil; ASession: TGatewaySession = nil);
    function ClassifyMessage(AObject: TObject; out AMethod,
      AIdKey: string): TJsonRpcMessageKind;
    function IsInitializeRequest(AObject: TObject): Boolean;
    function ExtractNegotiatedVersion(const AResponseJson: string;
      out AProtocolVersion: string): Boolean;
    function ValidateProtocolHeader(ARequest: TFPHTTPConnectionRequest;
      ASession: TGatewaySession; out AError: string): Boolean;
    procedure HandlePost(ARequest: TFPHTTPConnectionRequest;
      AResponse: TFPHTTPConnectionResponse; const ACorrelationId: string);
    procedure HandleGet(ARequest: TFPHTTPConnectionRequest;
      AResponse: TFPHTTPConnectionResponse; const ACorrelationId: string);
    procedure HandleDelete(ARequest: TFPHTTPConnectionRequest;
      AResponse: TFPHTTPConnectionResponse; const ACorrelationId: string);
  public
    constructor Create(AConfig: TGatewayConfig; ALogger: TGatewayLogger);
    destructor Destroy; override;
    procedure Run;
  end;

implementation

uses
  fpjson, jsonparser, McpProtocol, McpStdioProcess;

function JsonDataFromObject(AObject: TObject): TJSONData;
begin
  if AObject is TJSONData then
    Result := TJSONData(AObject)
  else
    Result := nil;
end;

constructor TGatewayHttpApplication.Create(AConfig: TGatewayConfig;
  ALogger: TGatewayLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FSessions := TGatewaySessionManager.Create(FConfig, FLogger);
  FServer := TGatewayBindableHttpServer.Create(nil);
  FServer.Address := FConfig.ListenHost;
  FServer.Port := FConfig.Port;
  FServer.Threaded := True;
  FServer.QueueSize := 64;
  FServer.OnRequest := @HandleRequest;
end;

destructor TGatewayHttpApplication.Destroy;
begin
  if FServer <> nil then
    FServer.Active := False;
  FServer.Free;
  FSessions.Free;
  inherited Destroy;
end;

function TGatewayHttpApplication.RequestPath(
  ARequest: TFPHTTPConnectionRequest): string;
var
  P: SizeInt;
begin
  Result := ARequest.URI;
  P := Pos('?', Result);
  if P > 0 then
    Delete(Result, P, MaxInt);
end;

function TGatewayHttpApplication.RequestOrigin(
  ARequest: TFPHTTPConnectionRequest): string;
begin
  Result := Trim(ARequest.GetFieldByName('Origin'));
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function TGatewayHttpApplication.IsOriginAllowed(
  const AOrigin: string): Boolean;
var
  I: Integer;
begin
  if AOrigin = '' then
    Exit(True);
  if not FConfig.CorsEnabled then
    Exit(False);
  for I := 0 to FConfig.AllowedOrigins.Count - 1 do
  begin
    if FConfig.AllowedOrigins[I] = '*' then
      Exit(True);
    if SameText(AOrigin, FConfig.AllowedOrigins[I]) then
      Exit(True);
  end;
  Result := False;
end;

procedure TGatewayHttpApplication.ApplyCorsHeaders(const AOrigin: string;
  AResponse: TFPHTTPConnectionResponse);
var
  AllowedOrigin: string;
begin
  if not FConfig.CorsEnabled then
    Exit;
  if FConfig.AllowedOrigins.IndexOf('*') >= 0 then
    AllowedOrigin := '*'
  else
    AllowedOrigin := AOrigin;
  if AllowedOrigin = '' then
    Exit;
  AResponse.SetCustomHeader('Access-Control-Allow-Origin', AllowedOrigin);
  AResponse.SetCustomHeader('Vary', 'Origin');
  AResponse.SetCustomHeader('Access-Control-Allow-Methods',
    'POST, GET, DELETE, OPTIONS');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers',
    'Accept, Authorization, Content-Type, MCP-Protocol-Version, ' +
    'MCP-Session-Id, Last-Event-ID');
  AResponse.SetCustomHeader('Access-Control-Expose-Headers',
    'MCP-Protocol-Version, MCP-Session-Id, X-Request-Id');
  AResponse.SetCustomHeader('Access-Control-Max-Age', '600');
end;

procedure TGatewayHttpApplication.ApplyConfiguredHeaders(
  AResponse: TFPHTTPConnectionResponse);
var
  I: Integer;
begin
  for I := 0 to FConfig.ResponseHeaders.Count - 1 do
    AResponse.SetCustomHeader(FConfig.ResponseHeaders.Names[I],
      FConfig.ResponseHeaders.ValueFromIndex[I]);
  AResponse.SetCustomHeader('X-Content-Type-Options', 'nosniff');
end;

procedure TGatewayHttpApplication.ApplyMcpHeaders(
  AResponse: TFPHTTPConnectionResponse; ASession: TGatewaySession);
var
  ProtocolVersion: string;
begin
  if ASession <> nil then
  begin
    AResponse.SetCustomHeader('MCP-Session-Id', ASession.Id);
    ProtocolVersion := ASession.ProtocolVersion;
  end
  else
    ProtocolVersion := '';
  if ProtocolVersion = '' then
    ProtocolVersion := MCP_PROTOCOL_VERSION;
  AResponse.SetCustomHeader('MCP-Protocol-Version', ProtocolVersion);
end;

function TGatewayHttpApplication.IsAuthorized(
  ARequest: TFPHTTPConnectionRequest): Boolean;
begin
  if FConfig.AuthToken = '' then
    Exit(True);
  Result := ARequest.Authorization = 'Bearer ' + FConfig.AuthToken;
end;

function TGatewayHttpApplication.IsHealthEndpoint(
  const APath: string): Boolean;
begin
  Result := FConfig.HealthEndpoints.IndexOf(APath) >= 0;
end;

function TGatewayHttpApplication.HeaderContains(
  ARequest: TFPHTTPConnectionRequest; const AHeader, AValue: string): Boolean;
begin
  Result := Pos(LowerCase(AValue),
    LowerCase(ARequest.GetFieldByName(AHeader))) > 0;
end;

procedure TGatewayHttpApplication.WriteEmpty(
  AResponse: TFPHTTPConnectionResponse; ACode: Integer);
begin
  AResponse.Code := ACode;
  AResponse.Content := '';
  ApplyConfiguredHeaders(AResponse);
end;

procedure TGatewayHttpApplication.WriteJson(
  AResponse: TFPHTTPConnectionResponse; ACode: Integer;
  const ABody: string; ASession: TGatewaySession);
begin
  AResponse.Code := ACode;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.Content := UTF8Encode(ABody);
  ApplyMcpHeaders(AResponse, ASession);
  ApplyConfiguredHeaders(AResponse);
end;

procedure TGatewayHttpApplication.WriteSse(
  AResponse: TFPHTTPConnectionResponse; ACode: Integer;
  const ABody: string; ASession: TGatewaySession);
begin
  AResponse.Code := ACode;
  AResponse.ContentType := 'text/event-stream; charset=utf-8';
  AResponse.SetCustomHeader('Cache-Control', 'no-cache, no-transform');
  AResponse.SetCustomHeader('X-Accel-Buffering', 'no');
  AResponse.Content := UTF8Encode(ABody);
  ApplyMcpHeaders(AResponse, ASession);
  ApplyConfiguredHeaders(AResponse);
end;

procedure TGatewayHttpApplication.WriteJsonRpcError(
  AResponse: TFPHTTPConnectionResponse; AHttpCode, ARpcCode: Integer;
  const AMessage: string; AId: TObject; ASession: TGatewaySession);
var
  ErrorObject: TJSONObject;
  IdData: TJSONData;
begin
  IdData := JsonDataFromObject(AId);
  ErrorObject := NewJsonRpcError(IdData, ARpcCode, AMessage);
  try
    WriteJson(AResponse, AHttpCode, ErrorObject.AsJSON, ASession);
  finally
    ErrorObject.Free;
  end;
end;

function TGatewayHttpApplication.ClassifyMessage(AObject: TObject;
  out AMethod, AIdKey: string): TJsonRpcMessageKind;
var
  Obj: TJSONObject;
  Data: TJSONData;
  HasId, HasMethod: Boolean;
begin
  Result := jmkInvalid;
  AMethod := '';
  AIdKey := '';
  if not (AObject is TJSONObject) then
    Exit;
  Obj := TJSONObject(AObject);
  Data := Obj.Find('jsonrpc');
  if (Data = nil) or (Data.JSONType <> jtString) or
     (Data.AsString <> '2.0') then
    Exit;

  Data := Obj.Find('method');
  HasMethod := (Data <> nil) and (Data.JSONType = jtString);
  if HasMethod then
    AMethod := Data.AsString;
  Data := Obj.Find('id');
  HasId := Data <> nil;
  if HasId then
    AIdKey := JsonRpcIdKey(Data.AsJSON);

  if HasMethod and HasId then
    Result := jmkRequest
  else if HasMethod then
    Result := jmkNotification
  else if HasId and ((Obj.Find('result') <> nil) or
    (Obj.Find('error') <> nil)) then
    Result := jmkResponse;
end;

function TGatewayHttpApplication.IsInitializeRequest(AObject: TObject): Boolean;
var
  RpcMethod, IdKey: string;
begin
  Result := (ClassifyMessage(AObject, RpcMethod, IdKey) = jmkRequest) and
    (RpcMethod = 'initialize');
end;

function TGatewayHttpApplication.ExtractNegotiatedVersion(
  const AResponseJson: string; out AProtocolVersion: string): Boolean;
var
  Data, ResultData, VersionData: TJSONData;
  Obj, ResultObj: TJSONObject;
begin
  Result := False;
  AProtocolVersion := '';
  Data := nil;
  try
    Data := GetJSON(AResponseJson);
    if Data.JSONType <> jtObject then
      Exit;
    Obj := TJSONObject(Data);
    ResultData := Obj.Find('result');
    if (ResultData = nil) or (ResultData.JSONType <> jtObject) then
      Exit;
    ResultObj := TJSONObject(ResultData);
    VersionData := ResultObj.Find('protocolVersion');
    if (VersionData = nil) or (VersionData.JSONType <> jtString) then
      Exit;
    AProtocolVersion := VersionData.AsString;
    Result := AProtocolVersion <> '';
  finally
    Data.Free;
  end;
end;

function TGatewayHttpApplication.ValidateProtocolHeader(
  ARequest: TFPHTTPConnectionRequest; ASession: TGatewaySession;
  out AError: string): Boolean;
var
  HeaderVersion, SessionVersion: string;
begin
  Result := True;
  AError := '';
  HeaderVersion := Trim(ARequest.GetFieldByName('MCP-Protocol-Version'));
  SessionVersion := ASession.ProtocolVersion;
  if HeaderVersion = '' then
  begin
    if FConfig.StrictAccept then
    begin
      AError := 'MCP-Protocol-Version header is required after initialization';
      Exit(False);
    end;
    Exit(True);
  end;
  if (SessionVersion <> '') and (HeaderVersion <> SessionVersion) then
  begin
    AError := Format('Unsupported MCP protocol version %s; session negotiated %s',
      [HeaderVersion, SessionVersion]);
    Result := False;
  end;
end;

procedure TGatewayHttpApplication.HandlePost(
  ARequest: TFPHTTPConnectionRequest; AResponse: TFPHTTPConnectionResponse;
  const ACorrelationId: string);
var
  Data: TJSONData;
  Obj: TJSONObject;
  Kind: TJsonRpcMessageKind;
  RpcMethod, IdKey, SessionId, ChildResponse, ChildError,
  ProtocolVersion, ProtocolError, SseBody: string;
  Session: TGatewaySession;
  NewSession, Success, HasJsonAccept, HasSseAccept: Boolean;
  IdData: TJSONData;
begin
  if Length(ARequest.Content) > FConfig.MaximumRequestBytes then
  begin
    WriteJsonRpcError(AResponse, 413, JSONRPC_INVALID_REQUEST,
      'Request body too large');
    Exit;
  end;
  if Pos('application/json', LowerCase(ARequest.ContentType)) = 0 then
  begin
    WriteJsonRpcError(AResponse, 415, JSONRPC_INVALID_REQUEST,
      'Content-Type must be application/json');
    Exit;
  end;

  HasJsonAccept := HeaderContains(ARequest, 'Accept', 'application/json');
  HasSseAccept := HeaderContains(ARequest, 'Accept', 'text/event-stream');
  if FConfig.StrictAccept and not (HasJsonAccept and HasSseAccept) then
  begin
    WriteJsonRpcError(AResponse, 406, JSONRPC_INVALID_REQUEST,
      'Accept must include application/json and text/event-stream');
    Exit;
  end;

  Data := nil;
  Session := nil;
  NewSession := False;
  try
    try
      Data := GetJSON(ARequest.Content);
    except
      on E: Exception do
      begin
        WriteJsonRpcError(AResponse, 400, JSONRPC_PARSE_ERROR,
          'Parse error: ' + E.Message);
        Exit;
      end;
    end;
    if Data.JSONType <> jtObject then
    begin
      WriteJsonRpcError(AResponse, 400, JSONRPC_INVALID_REQUEST,
        'Only one JSON-RPC object per POST is supported');
      Exit;
    end;
    Obj := TJSONObject(Data);
    Kind := ClassifyMessage(Obj, RpcMethod, IdKey);
    if Kind = jmkInvalid then
    begin
      WriteJsonRpcError(AResponse, 400, JSONRPC_INVALID_REQUEST,
        'Invalid JSON-RPC message');
      Exit;
    end;

    SessionId := Trim(ARequest.GetFieldByName('MCP-Session-Id'));
    if SessionId = '' then
    begin
      if not IsInitializeRequest(Obj) then
      begin
        WriteJsonRpcError(AResponse, 400, -32000,
          'Bad Request: No valid session ID provided');
        Exit;
      end;
      try
        Session := FSessions.CreateSession;
        NewSession := True;
      except
        on E: Exception do
        begin
          FLogger.Error(ACorrelationId + ' child start failed: ' + E.Message);
          WriteJsonRpcError(AResponse, 502, JSONRPC_INTERNAL_ERROR,
            E.Message, Obj.Find('id'));
          Exit;
        end;
      end;
    end
    else
    begin
      Session := FSessions.AcquireSession(SessionId);
      if Session = nil then
      begin
        WriteJsonRpcError(AResponse, 404, -32001,
          'Session not found or expired');
        Exit;
      end;
      if RpcMethod = 'initialize' then
      begin
        WriteJsonRpcError(AResponse, 400, JSONRPC_INVALID_REQUEST,
          'Session is already initialized', Obj.Find('id'), Session);
        Exit;
      end;
      if not ValidateProtocolHeader(ARequest, Session, ProtocolError) then
      begin
        WriteJsonRpcError(AResponse, 400, JSONRPC_INVALID_REQUEST,
          ProtocolError, Obj.Find('id'), Session);
        Exit;
      end;
    end;

    if Kind in [jmkNotification, jmkResponse] then
    begin
      Success := Session.SendMessage(Obj.AsJSON, ChildError);
      if not Success then
      begin
        WriteJsonRpcError(AResponse, 502, JSONRPC_INTERNAL_ERROR,
          ChildError, nil, Session);
        FSessions.RetireSession(Session.Id, ChildError);
        Exit;
      end;
      AResponse.SetCustomHeader('MCP-Session-Id', Session.Id);
      ApplyMcpHeaders(AResponse, Session);
      WriteEmpty(AResponse, 202);
      Exit;
    end;

    Success := Session.SendRequest(Obj.AsJSON, IdKey,
      FConfig.RequestTimeoutMs, ChildResponse, ChildError);
    if not Success then
    begin
      FLogger.Error(Format('%s session %s request failed: %s',
        [ACorrelationId, Session.Id, ChildError]));
      IdData := Obj.Find('id');
      if Pos('Zeitüberschreitung', ChildError) > 0 then
        WriteJsonRpcError(AResponse, 504, JSONRPC_INTERNAL_ERROR,
          ChildError, IdData, Session)
      else
        WriteJsonRpcError(AResponse, 502, JSONRPC_INTERNAL_ERROR,
          ChildError, IdData, Session);
      if not Session.IsRunning then
        FSessions.RetireSession(Session.Id, ChildError);
      Exit;
    end;

    if NewSession then
    begin
      if not ExtractNegotiatedVersion(ChildResponse, ProtocolVersion) then
      begin
        FSessions.RetireSession(Session.Id,
          'initialize did not return a protocolVersion');
        WriteJson(AResponse, 200, ChildResponse);
        Exit;
      end;
      Session.SetProtocolVersion(ProtocolVersion);
      FLogger.Info(Format('Session %s negotiated MCP %s',
        [Session.Id, ProtocolVersion]));
    end;

    if (not HasJsonAccept) and HasSseAccept then
    begin
      SseBody := 'id: response-' + ACorrelationId + #10 +
        'event: message' + #10 + 'data: ' + ChildResponse + #10#10;
      WriteSse(AResponse, 200, SseBody, Session);
    end
    else
      WriteJson(AResponse, 200, ChildResponse, Session);
  finally
    if Session <> nil then
      FSessions.ReleaseSession(Session);
    Data.Free;
  end;
end;

procedure TGatewayHttpApplication.HandleGet(
  ARequest: TFPHTTPConnectionRequest; AResponse: TFPHTTPConnectionResponse;
  const ACorrelationId: string);
var
  SessionId, Body: string;
  Session: TGatewaySession;
begin
  if FConfig.StrictAccept and
     not HeaderContains(ARequest, 'Accept', 'text/event-stream') then
  begin
    WriteJsonRpcError(AResponse, 406, JSONRPC_INVALID_REQUEST,
      'Accept must include text/event-stream');
    Exit;
  end;
  SessionId := Trim(ARequest.GetFieldByName('MCP-Session-Id'));
  if SessionId = '' then
  begin
    WriteJsonRpcError(AResponse, 400, -32000,
      'Invalid or missing session ID');
    Exit;
  end;
  Session := FSessions.AcquireSession(SessionId);
  if Session = nil then
  begin
    WriteJsonRpcError(AResponse, 404, -32001,
      'Session not found or expired');
    Exit;
  end;
  try
    if not Session.PollSse(ARequest.GetFieldByName('Last-Event-ID'),
      FConfig.SsePollTimeoutMs, Body) then
    begin
      WriteJsonRpcError(AResponse, 500, JSONRPC_INTERNAL_ERROR,
        'SSE polling failed', nil, Session);
      Exit;
    end;
    WriteSse(AResponse, 200, Body, Session);
    FLogger.Debug(Format('%s SSE poll returned %d bytes',
      [ACorrelationId, Length(Body)]));
  finally
    FSessions.ReleaseSession(Session);
  end;
end;

procedure TGatewayHttpApplication.HandleDelete(
  ARequest: TFPHTTPConnectionRequest; AResponse: TFPHTTPConnectionResponse;
  const ACorrelationId: string);
var
  SessionId: string;
  Session: TGatewaySession;
begin
  SessionId := Trim(ARequest.GetFieldByName('MCP-Session-Id'));
  if SessionId = '' then
  begin
    WriteJsonRpcError(AResponse, 400, -32000,
      'Invalid or missing session ID');
    Exit;
  end;
  Session := FSessions.AcquireSession(SessionId);
  if Session = nil then
  begin
    WriteJsonRpcError(AResponse, 404, -32001,
      'Session not found or expired');
    Exit;
  end;
  try
    FSessions.RetireSession(SessionId, 'client DELETE');
    AResponse.SetCustomHeader('MCP-Session-Id', SessionId);
    ApplyMcpHeaders(AResponse, Session);
    WriteEmpty(AResponse, 200);
    FLogger.Info(ACorrelationId + ' session deleted: ' + SessionId);
  finally
    FSessions.ReleaseSession(Session);
  end;
end;

procedure TGatewayHttpApplication.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  RequestNumber: LongInt;
  CorrelationId, Path, Origin: string;
begin
  RequestNumber := InterlockedIncrement(FRequestCounter);
  CorrelationId := Format('GW-%.8d', [RequestNumber]);
  AResponse.SetCustomHeader('X-Request-Id', CorrelationId);
  Path := RequestPath(ARequest);
  Origin := RequestOrigin(ARequest);
  FLogger.Debug(Format('%s %s %s from %s', [CorrelationId,
    ARequest.Method, ARequest.URI, ARequest.RemoteAddress]));

  if not IsOriginAllowed(Origin) then
  begin
    FLogger.Error(Format('%s rejected Origin: %s', [CorrelationId, Origin]));
    WriteJsonRpcError(AResponse, 403, -32000, 'Origin not allowed');
    Exit;
  end;
  ApplyCorsHeaders(Origin, AResponse);

  if IsHealthEndpoint(Path) then
  begin
    if not SameText(ARequest.Method, 'GET') then
    begin
      AResponse.Allow := 'GET';
      WriteEmpty(AResponse, 405);
    end
    else
    begin
      AResponse.Code := 200;
      AResponse.ContentType := 'text/plain; charset=utf-8';
      AResponse.Content := 'ok';
      ApplyConfiguredHeaders(AResponse);
    end;
    Exit;
  end;

  if Path <> FConfig.Endpoint then
  begin
    WriteJsonRpcError(AResponse, 404, -32001, 'Endpoint not found');
    Exit;
  end;

  if SameText(ARequest.Method, 'OPTIONS') then
  begin
    AResponse.Allow := 'POST, GET, DELETE, OPTIONS';
    WriteEmpty(AResponse, 204);
    Exit;
  end;

  if not IsAuthorized(ARequest) then
  begin
    AResponse.WWWAuthenticate := 'Bearer';
    WriteJsonRpcError(AResponse, 401, -32000, 'Unauthorized');
    Exit;
  end;

  try
    if SameText(ARequest.Method, 'POST') then
      HandlePost(ARequest, AResponse, CorrelationId)
    else if SameText(ARequest.Method, 'GET') then
      HandleGet(ARequest, AResponse, CorrelationId)
    else if SameText(ARequest.Method, 'DELETE') then
      HandleDelete(ARequest, AResponse, CorrelationId)
    else
    begin
      AResponse.Allow := 'POST, GET, DELETE, OPTIONS';
      WriteJsonRpcError(AResponse, 405, -32000, 'Method not allowed');
    end;
  except
    on E: Exception do
    begin
      FLogger.Error(CorrelationId + ' internal error: ' + E.Message);
      WriteJsonRpcError(AResponse, 500, JSONRPC_INTERNAL_ERROR,
        'Gateway internal error: ' + E.Message);
    end;
  end;
end;

procedure TGatewayHttpApplication.Run;
var
  CommandDescription: string;
begin
  if FConfig.UsesShell then
    CommandDescription := FConfig.StdioCommand
  else
    CommandDescription := FConfig.Executable + ' ' + FConfig.Arguments.Text;
  FLogger.Info('LLC MCP Gateway ' + LLC_MCP_GATEWAY_VERSION);
  FLogger.Info(Format('Stateful Streamable HTTP: http://%s:%d%s',
    [FConfig.ListenHost, FConfig.Port, FConfig.Endpoint]));
  FLogger.Info('stdio child command: ' + StringReplace(CommandDescription,
    LineEnding, ' ', [rfReplaceAll]));
  FLogger.Info(Format('Session timeout: %d ms; request timeout: %d ms',
    [FConfig.SessionTimeoutMs, FConfig.RequestTimeoutMs]));
  if (FConfig.ListenHost = '0.0.0.0') or (FConfig.ListenHost = '::') then
    FLogger.Error('Gateway listens on all interfaces; use --authToken or a firewall.');
  FLogger.Info('Press Ctrl+C to stop.');
  FServer.Active := True;
end;

end.
