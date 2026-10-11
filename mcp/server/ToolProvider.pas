unit ToolProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

type
  TToolProvider = class
  public
    procedure AddTools(ATools: TJSONArray); virtual; abstract;
    function HandlesTool(const AName: string): Boolean; virtual; abstract;
    function CallTool(const AName: string; AArguments: TJSONObject;
      const ACorrelationId: string): TJSONObject; virtual; abstract;
  end;

function BuildTool(const AName, ADescription: string;
  ASchema: TJSONObject; AMeta: TJSONObject = nil): TJSONObject;
function ObjectSchema(AProperties: TJSONObject;
  const ARequired: array of string): TJSONObject;
function StringProperty(const ADescription: string = ''): TJSONObject;
function IntegerProperty(ADefault, AMinimum, AMaximum: Int64;
  const ADescription: string = ''): TJSONObject;
function IntegerRangeProperty(AMinimum, AMaximum: Int64;
  const ADescription: string = ''): TJSONObject;
function BooleanProperty(ADefault: Boolean;
  const ADescription: string = ''): TJSONObject;
function ArrayProperty(AItemSchema: TJSONObject;
  const ADescription: string = ''): TJSONObject;

implementation

function BuildTool(const AName, ADescription: string;
  ASchema: TJSONObject; AMeta: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', AName);
  Result.Add('description', ADescription);
  Result.Add('inputSchema', ASchema);
  if AMeta <> nil then
    Result.Add('_meta', AMeta);
end;

function ObjectSchema(AProperties: TJSONObject;
  const ARequired: array of string): TJSONObject;
var
  Required: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'object');
  Result.Add('properties', AProperties);
  Required := TJSONArray.Create;
  for I := Low(ARequired) to High(ARequired) do
    Required.Add(ARequired[I]);
  Result.Add('required', Required);
  Result.Add('additionalProperties', False);
end;

function StringProperty(const ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'string');
  if ADescription <> '' then
    Result.Add('description', ADescription);
end;

function IntegerProperty(ADefault, AMinimum, AMaximum: Int64;
  const ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'integer');
  Result.Add('default', ADefault);
  Result.Add('minimum', AMinimum);
  Result.Add('maximum', AMaximum);
  if ADescription <> '' then
    Result.Add('description', ADescription);
end;

function IntegerRangeProperty(AMinimum, AMaximum: Int64;
  const ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'integer');
  Result.Add('minimum', AMinimum);
  Result.Add('maximum', AMaximum);
  if ADescription <> '' then
    Result.Add('description', ADescription);
end;

function BooleanProperty(ADefault: Boolean;
  const ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'boolean');
  Result.Add('default', ADefault);
  if ADescription <> '' then
    Result.Add('description', ADescription);
end;

function ArrayProperty(AItemSchema: TJSONObject;
  const ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('type', 'array');
  Result.Add('items', AItemSchema);
  if ADescription <> '' then
    Result.Add('description', ADescription);
end;

end.
