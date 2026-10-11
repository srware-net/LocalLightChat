unit McpHttpClient;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  TMcpHttpResponse = record
    StatusCode: Integer;
    StatusText: string;
    Body: string;
    Headers: string;
    ContentType: string;
    SessionId: string;
    ProtocolVersion: string;
    DurationMs: Int64;
  end;

  TMcpHttpClient = class
  private
    FEndpoint: string;
    FToken: string;
    FProtocolVersion: string;
    FSessionId: string;
    FNextId: Int64;
    function NextId: Int64;
    procedure SetEndpoint(const AValue: string);
    procedure SetToken(const AValue: string);
  public
    constructor Create;
    procedure ResetSession;
    function SendRaw(const AJson: string): TMcpHttpResponse;
    function SendRequest(const AMethod: string; AParams: TJSONData = nil): TMcpHttpResponse;
    function SendNotification(const AMethod: string; AParams: TJSONData = nil): TMcpHttpResponse;
    property Endpoint: string read FEndpoint write SetEndpoint;
    property Token: string read FToken write SetToken;
    property ProtocolVersion: string read FProtocolVersion write FProtocolVersion;
    property SessionId: string read FSessionId;
  end;

implementation

uses
  fphttpclient, jsonparser;

const
  DEFAULT_MCP_PROTOCOL_VERSION = '2025-11-25';

function HeaderValue(AHeaders: TStrings; const AName: string): string;
var
  I, P: Integer;
  Line, NamePart: string;
begin
  Result := '';
  if AHeaders = nil then
    Exit;
  for I := 0 to AHeaders.Count - 1 do
  begin
    Line := AHeaders[I];
    P := Pos(':', Line);
    if P <= 0 then
      Continue;
    NamePart := Trim(Copy(Line, 1, P - 1));
    if SameText(NamePart, AName) then
      Exit(Trim(Copy(Line, P + 1, MaxInt)));
  end;
end;

function JsonIdText(AData: TJSONData): string;
begin
  Result := '';
  if AData = nil then
    Exit;
  if AData.JSONType = jtString then
    Result := AData.AsString
  else
    Result := AData.AsJSON;
end;

procedure InspectJsonRpcRequest(const AJson: string; out AMethod, AId: string);
var
  Root, Data: TJSONData;
begin
  AMethod := '';
  AId := '';
  Root := nil;
  try
    try
      Root := GetJSON(AJson);
      if (Root = nil) or (Root.JSONType <> jtObject) then
        Exit;
      Data := Root.FindPath('method');
      if (Data <> nil) and (Data.JSONType = jtString) then
        AMethod := Data.AsString;
      Data := Root.FindPath('id');
      AId := JsonIdText(Data);
    except
      AMethod := '';
      AId := '';
    end;
  finally
    Root.Free;
  end;
end;

function SseEventJsonMatches(const AEventData, AExpectedId: string;
  out AJson: string): Boolean;
var
  Root, IdData: TJSONData;
  CandidateId: string;
begin
  Result := False;
  AJson := '';
  if (Trim(AEventData) = '') or (Trim(AEventData) = '[DONE]') then
    Exit;
  Root := nil;
  try
    try
      Root := GetJSON(AEventData);
      if (Root = nil) or (Root.JSONType <> jtObject) then
        Exit;
      AJson := Trim(AEventData);
      if AExpectedId = '' then
        Exit(True);
      IdData := Root.FindPath('id');
      CandidateId := JsonIdText(IdData);
      Result := CandidateId = AExpectedId;
    except
      AJson := '';
      Result := False;
    end;
  finally
    Root.Free;
  end;
end;

function ExtractSseJson(const ABody, AExpectedId: string): string;
var
  Lines: TStringList;
  I: Integer;
  Line, DataBuffer, Candidate, FirstJson: string;

  function ProcessEvent: Boolean;
  var
    EventJson: string;
  begin
    Result := False;
    if Trim(DataBuffer) = '' then
      Exit;
    if SseEventJsonMatches(DataBuffer, '', EventJson) and (FirstJson = '') then
      FirstJson := EventJson;
    if SseEventJsonMatches(DataBuffer, AExpectedId, EventJson) then
    begin
      Candidate := EventJson;
      Result := True;
    end;
    DataBuffer := '';
  end;

begin
  Result := ABody;
  Lines := TStringList.Create;
  try
    Lines.Text := StringReplace(ABody, #13#10, #10, [rfReplaceAll]);
    DataBuffer := '';
    Candidate := '';
    FirstJson := '';
    I := 0;
    while I < Lines.Count do
    begin
      Line := Lines[I];
      if Line = '' then
      begin
        if ProcessEvent then
          Break;
      end
      else if Copy(Line, 1, 5) = 'data:' then
      begin
        if DataBuffer <> '' then
          DataBuffer := DataBuffer + #10;
        DataBuffer := DataBuffer + TrimLeft(Copy(Line, 6, MaxInt));
      end;
      Inc(I);
    end;
    if (Candidate = '') and (DataBuffer <> '') then
      ProcessEvent;
    if Candidate <> '' then
      Result := Candidate
    else if FirstJson <> '' then
      Result := FirstJson;
  finally
    Lines.Free;
  end;
end;

function ExtractNegotiatedProtocolVersion(const AJson: string): string;
var
  Root, Data: TJSONData;
begin
  Result := '';
  Root := nil;
  try
    try
      Root := GetJSON(AJson);
      Data := Root.FindPath('result.protocolVersion');
      if (Data <> nil) and (Data.JSONType = jtString) then
        Result := Trim(Data.AsString);
    except
      Result := '';
    end;
  finally
    Root.Free;
  end;
end;

constructor TMcpHttpClient.Create;
begin
  inherited Create;
  FEndpoint := 'http://127.0.0.1:8765/mcp';
  FToken := '';
  ResetSession;
end;

procedure TMcpHttpClient.ResetSession;
begin
  FProtocolVersion := DEFAULT_MCP_PROTOCOL_VERSION;
  FSessionId := '';
  FNextId := 1;
end;

procedure TMcpHttpClient.SetEndpoint(const AValue: string);
var
  NewValue: string;
begin
  NewValue := Trim(AValue);
  if FEndpoint = NewValue then
    Exit;
  FEndpoint := NewValue;
  ResetSession;
end;

procedure TMcpHttpClient.SetToken(const AValue: string);
begin
  if FToken = AValue then
    Exit;
  FToken := AValue;
  ResetSession;
end;

function TMcpHttpClient.NextId: Int64;
begin
  Result := FNextId;
  Inc(FNextId);
end;

function TMcpHttpClient.SendRaw(const AJson: string): TMcpHttpResponse;
var
  Client: TFPHTTPClient;
  RequestStream: TStringStream;
  ResponseStream: TStringStream;
  StartedAt: QWord;
  RequestMethod, RequestId: string;
  IsInitialize: Boolean;
  ReturnedSessionId, NegotiatedVersion: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  InspectJsonRpcRequest(AJson, RequestMethod, RequestId);
  IsInitialize := SameText(RequestMethod, 'initialize');
  if IsInitialize then
  begin
    FProtocolVersion := DEFAULT_MCP_PROTOCOL_VERSION;
    FSessionId := '';
  end;

  Client := TFPHTTPClient.Create(nil);
  RequestStream := TStringStream.Create(AJson);
  ResponseStream := TStringStream.Create('');
  try
    Client.AllowRedirect := False;
    Client.AddHeader('Content-Type', 'application/json; charset=utf-8');
    Client.AddHeader('Accept', 'application/json, text/event-stream');
    Client.AddHeader('User-Agent', 'LazarusMcpDebugger/0.9');
    if (not IsInitialize) and (FProtocolVersion <> '') then
      Client.AddHeader('MCP-Protocol-Version', FProtocolVersion);
    if (not IsInitialize) and (FSessionId <> '') then
      Client.AddHeader('Mcp-Session-Id', FSessionId);
    if FToken <> '' then
      Client.AddHeader('Authorization', 'Bearer ' + FToken);

    Client.RequestBody := RequestStream;
    StartedAt := GetTickCount64;
    try
      Client.Post(FEndpoint, ResponseStream);
    except
      on E: Exception do
      begin
        Result.StatusCode := Client.ResponseStatusCode;
        Result.StatusText := E.Message;
      end;
    end;
    Result.DurationMs := GetTickCount64 - StartedAt;
    if Result.StatusCode = 0 then
      Result.StatusCode := Client.ResponseStatusCode;
    if Result.StatusText = '' then
      Result.StatusText := Client.ResponseStatusText;

    Result.Headers := Client.ResponseHeaders.Text;
    Result.ContentType := HeaderValue(Client.ResponseHeaders, 'Content-Type');
    ReturnedSessionId := HeaderValue(Client.ResponseHeaders, 'Mcp-Session-Id');
    Result.Body := ResponseStream.DataString;
    if Pos('text/event-stream', LowerCase(Result.ContentType)) > 0 then
      Result.Body := ExtractSseJson(Result.Body, RequestId);

    if (Result.StatusCode >= 200) and (Result.StatusCode < 300) and
       (ReturnedSessionId <> '') then
      FSessionId := ReturnedSessionId;

    if IsInitialize and (Result.StatusCode >= 200) and (Result.StatusCode < 300) then
    begin
      NegotiatedVersion := ExtractNegotiatedProtocolVersion(Result.Body);
      if NegotiatedVersion <> '' then
        FProtocolVersion := NegotiatedVersion;
    end
    else if (Result.StatusCode = 404) and (FSessionId <> '') then
      ResetSession;

    Result.SessionId := FSessionId;
    Result.ProtocolVersion := FProtocolVersion;
    Client.RequestBody := nil;
  finally
    ResponseStream.Free;
    RequestStream.Free;
    Client.Free;
  end;
end;

function TMcpHttpClient.SendRequest(const AMethod: string;
  AParams: TJSONData): TMcpHttpResponse;
var
  RequestObject: TJSONObject;
begin
  if SameText(AMethod, 'initialize') then
    ResetSession;
  RequestObject := TJSONObject.Create;
  try
    RequestObject.Add('jsonrpc', '2.0');
    RequestObject.Add('id', NextId);
    RequestObject.Add('method', AMethod);
    if AParams <> nil then
      RequestObject.Add('params', AParams)
    else
      RequestObject.Add('params', TJSONObject.Create);
    Result := SendRaw(RequestObject.AsJSON);
  finally
    RequestObject.Free;
  end;
end;

function TMcpHttpClient.SendNotification(const AMethod: string;
  AParams: TJSONData): TMcpHttpResponse;
var
  RequestObject: TJSONObject;
begin
  RequestObject := TJSONObject.Create;
  try
    RequestObject.Add('jsonrpc', '2.0');
    RequestObject.Add('method', AMethod);
    if AParams <> nil then
      RequestObject.Add('params', AParams)
    else
      RequestObject.Add('params', TJSONObject.Create);
    Result := SendRaw(RequestObject.AsJSON);
  finally
    RequestObject.Free;
  end;
end;

end.
