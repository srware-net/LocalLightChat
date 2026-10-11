unit McpJson;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

function JsonString(AObject: TJSONObject; const AName: string;
  const ADefault: string = ''): string;
function JsonUtf8String(AObject: TJSONObject; const AName: string;
  const ADefault: UTF8String = ''): UTF8String;
function JsonInteger(AObject: TJSONObject; const AName: string;
  ADefault: Int64 = 0): Int64;
function JsonBoolean(AObject: TJSONObject; const AName: string;
  ADefault: Boolean = False): Boolean;
function JsonObject(AObject: TJSONObject; const AName: string): TJSONObject;
function JsonArray(AObject: TJSONObject; const AName: string): TJSONArray;
function CloneJson(AData: TJSONData): TJSONData;
function NewStringArray(const AValues: array of string): TJSONArray;

implementation

function JsonString(AObject: TJSONObject; const AName: string;
  const ADefault: string): string;
var
  Data: TJSONData;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtString) then
    Result := Data.AsString;
end;

function JsonUtf8String(AObject: TJSONObject; const AName: string;
  const ADefault: UTF8String): UTF8String;
var
  Data: TJSONData;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtString) then
    Result := Data.AsString;
end;

function JsonInteger(AObject: TJSONObject; const AName: string;
  ADefault: Int64): Int64;
var
  Data: TJSONData;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType in [jtNumber, jtString]) then
    try
      Result := Data.AsInt64;
    except
      Result := ADefault;
    end;
end;

function JsonBoolean(AObject: TJSONObject; const AName: string;
  ADefault: Boolean): Boolean;
var
  Data: TJSONData;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Data := AObject.Find(AName);
  if Data <> nil then
    try
      Result := Data.AsBoolean;
    except
      Result := ADefault;
    end;
end;

function JsonObject(AObject: TJSONObject; const AName: string): TJSONObject;
var
  Data: TJSONData;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtObject) then
    Result := TJSONObject(Data);
end;

function JsonArray(AObject: TJSONObject; const AName: string): TJSONArray;
var
  Data: TJSONData;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtArray) then
    Result := TJSONArray(Data);
end;

function CloneJson(AData: TJSONData): TJSONData;
begin
  if AData = nil then
    Exit(TJSONNull.Create);
  Result := AData.Clone;
end;

function NewStringArray(const AValues: array of string): TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := Low(AValues) to High(AValues) do
    Result.Add(AValues[I]);
end;

end.
