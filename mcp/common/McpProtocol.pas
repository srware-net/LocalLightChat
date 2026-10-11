unit McpProtocol;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

const
  MCP_PROTOCOL_VERSION = '2025-11-25';

  JSONRPC_PARSE_ERROR      = -32700;
  JSONRPC_INVALID_REQUEST  = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS   = -32602;
  JSONRPC_INTERNAL_ERROR   = -32603;

function NewJsonRpcResult(AId, AResult: TJSONData): TJSONObject;
function NewJsonRpcError(AId: TJSONData; ACode: Integer;
  const AMessage: string; AData: TJSONData = nil): TJSONObject;
function NewToolTextResult(const AText: string; AStructured: TJSONData = nil;
  AIsError: Boolean = False): TJSONObject;
function NewToolImageResult(const AMimeType, ABase64Data: string;
  AStructured: TJSONData = nil; const ADescription: string = ''): TJSONObject;

implementation

function NewJsonRpcResult(AId, AResult: TJSONData): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('jsonrpc', '2.0');
  if AId <> nil then
    Result.Add('id', AId.Clone)
  else
    Result.Add('id', TJSONNull.Create);
  if AResult <> nil then
    Result.Add('result', AResult)
  else
    Result.Add('result', TJSONObject.Create);
end;

function NewJsonRpcError(AId: TJSONData; ACode: Integer;
  const AMessage: string; AData: TJSONData): TJSONObject;
var
  ErrorObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('jsonrpc', '2.0');
  if AId <> nil then
    Result.Add('id', AId.Clone)
  else
    Result.Add('id', TJSONNull.Create);

  ErrorObject := TJSONObject.Create;
  ErrorObject.Add('code', ACode);
  ErrorObject.Add('message', AMessage);
  if AData <> nil then
    ErrorObject.Add('data', AData);
  Result.Add('error', ErrorObject);
end;

function NewToolTextResult(const AText: string; AStructured: TJSONData;
  AIsError: Boolean): TJSONObject;
var
  Content: TJSONArray;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Content := TJSONArray.Create;
  Item := TJSONObject.Create;
  Item.Add('type', 'text');
  Item.Add('text', AText);
  Content.Add(Item);
  Result.Add('content', Content);
  if AStructured <> nil then
    Result.Add('structuredContent', AStructured);
  Result.Add('isError', AIsError);
end;

function NewToolImageResult(const AMimeType, ABase64Data: string;
  AStructured: TJSONData; const ADescription: string): TJSONObject;
var
  Content: TJSONArray;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Content := TJSONArray.Create;

  if ADescription <> '' then
  begin
    Item := TJSONObject.Create;
    Item.Add('type', 'text');
    Item.Add('text', ADescription);
    Content.Add(Item);
  end;

  Item := TJSONObject.Create;
  Item.Add('type', 'image');
  Item.Add('mimeType', AMimeType);
  Item.Add('data', ABase64Data);
  Content.Add(Item);

  Result.Add('content', Content);
  if AStructured <> nil then
    Result.Add('structuredContent', AStructured);
  Result.Add('isError', False);
end;

end.
