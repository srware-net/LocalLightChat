unit GatewayConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, GatewayLog;

const
  LLC_MCP_GATEWAY_VERSION = '0.1.2';

type
  EGatewayConfig = class(Exception);

  TGatewayConfig = class
  private
    FListenHost: string;
    FPort: Word;
    FEndpoint: string;
    FSessionTimeoutMs: QWord;
    FRequestTimeoutMs: QWord;
    FSsePollTimeoutMs: QWord;
    FMaximumRequestBytes: Int64;
    FStdioCommand: string;
    FExecutable: string;
    FArguments: TStringList;
    FWorkingDirectory: string;
    FEnvironment: TStringList;
    FCorsEnabled: Boolean;
    FAllowedOrigins: TStringList;
    FHealthEndpoints: TStringList;
    FResponseHeaders: TStringList;
    FLogLevel: TGatewayLogLevel;
    FLogFileName: string;
    FAuthToken: string;
    FStrictAccept: Boolean;
    FShowHelp: Boolean;
    FShowVersion: Boolean;
    procedure ResetDefaults;
    procedure LoadJsonFile(const AFileName: string);
    procedure ParseArguments;
    procedure AddNameValue(AList: TStringList; const AValue, AOptionName: string);
    function NormalizeEndpoint(const AValue: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Load;
    procedure Validate;
    procedure PrintHelp;
    procedure PrintVersion;
    function UsesShell: Boolean;

    property ListenHost: string read FListenHost;
    property Port: Word read FPort;
    property Endpoint: string read FEndpoint;
    property SessionTimeoutMs: QWord read FSessionTimeoutMs;
    property RequestTimeoutMs: QWord read FRequestTimeoutMs;
    property SsePollTimeoutMs: QWord read FSsePollTimeoutMs;
    property MaximumRequestBytes: Int64 read FMaximumRequestBytes;
    property StdioCommand: string read FStdioCommand;
    property Executable: string read FExecutable;
    property Arguments: TStringList read FArguments;
    property WorkingDirectory: string read FWorkingDirectory;
    property Environment: TStringList read FEnvironment;
    property CorsEnabled: Boolean read FCorsEnabled;
    property AllowedOrigins: TStringList read FAllowedOrigins;
    property HealthEndpoints: TStringList read FHealthEndpoints;
    property ResponseHeaders: TStringList read FResponseHeaders;
    property LogLevel: TGatewayLogLevel read FLogLevel;
    property LogFileName: string read FLogFileName;
    property AuthToken: string read FAuthToken;
    property StrictAccept: Boolean read FStrictAccept;
    property ShowHelp: Boolean read FShowHelp;
    property ShowVersion: Boolean read FShowVersion;
  end;

implementation

uses
  fpjson, jsonparser;

function JsonStringValue(AObject: TJSONObject; const AName,
  ADefault: string): string;
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

function JsonIntValue(AObject: TJSONObject; const AName: string;
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

function JsonBoolValue(AObject: TJSONObject; const AName: string;
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

procedure LoadJsonStringArray(AObject: TJSONObject; const AName: string;
  ATarget: TStrings; AClear: Boolean = True);
var
  Data: TJSONData;
  Arr: TJSONArray;
  I: Integer;
begin
  if AClear then
    ATarget.Clear;
  Data := AObject.Find(AName);
  if (Data = nil) or (Data.JSONType <> jtArray) then
    Exit;
  Arr := TJSONArray(Data);
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I].JSONType = jtString then
      ATarget.Add(Arr.Strings[I]);
end;

procedure LoadJsonNameValues(AObject: TJSONObject; const AName: string;
  ATarget: TStrings; AClear: Boolean = True);
var
  Data, Item: TJSONData;
  Obj: TJSONObject;
  I: Integer;
begin
  if AClear then
    ATarget.Clear;
  Data := AObject.Find(AName);
  if (Data = nil) or (Data.JSONType <> jtObject) then
    Exit;
  Obj := TJSONObject(Data);
  for I := 0 to Obj.Count - 1 do
  begin
    Item := Obj.Items[I];
    if Item.JSONType = jtString then
      ATarget.Values[Obj.Names[I]] := Item.AsString
    else
      ATarget.Values[Obj.Names[I]] := Item.AsJSON;
  end;
end;

constructor TGatewayConfig.Create;
begin
  inherited Create;
  FArguments := TStringList.Create;
  FEnvironment := TStringList.Create;
  FEnvironment.CaseSensitive := {$IFDEF WINDOWS}False{$ELSE}True{$ENDIF};
  FAllowedOrigins := TStringList.Create;
  FAllowedOrigins.CaseSensitive := False;
  FHealthEndpoints := TStringList.Create;
  FResponseHeaders := TStringList.Create;
  FResponseHeaders.CaseSensitive := False;
  ResetDefaults;
end;

destructor TGatewayConfig.Destroy;
begin
  FResponseHeaders.Free;
  FHealthEndpoints.Free;
  FAllowedOrigins.Free;
  FEnvironment.Free;
  FArguments.Free;
  inherited Destroy;
end;

procedure TGatewayConfig.ResetDefaults;
begin
  FListenHost := '127.0.0.1';
  FPort := 8000;
  FEndpoint := '/mcp';
  FSessionTimeoutMs := 3600000;
  FRequestTimeoutMs := 120000;
  FSsePollTimeoutMs := 25000;
  FMaximumRequestBytes := 16 * 1024 * 1024;
  FStdioCommand := '';
  FExecutable := '';
  FArguments.Clear;
  FWorkingDirectory := '';
  FEnvironment.Clear;
  FCorsEnabled := False;
  FAllowedOrigins.Clear;
  FHealthEndpoints.Clear;
  FResponseHeaders.Clear;
  FLogLevel := gllInfo;
  FLogFileName := '';
  FAuthToken := '';
  FStrictAccept := False;
  FShowHelp := False;
  FShowVersion := False;
end;

function TGatewayConfig.NormalizeEndpoint(const AValue: string): string;
begin
  Result := Trim(AValue);
  if Result = '' then
    Result := '/mcp';
  if Result[1] <> '/' then
    Result := '/' + Result;
  while (Length(Result) > 1) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

procedure TGatewayConfig.AddNameValue(AList: TStringList; const AValue,
  AOptionName: string);
var
  P: SizeInt;
  NamePart, ValuePart: string;
begin
  P := Pos('=', AValue);
  if P = 0 then
    P := Pos(':', AValue);
  if P <= 1 then
    raise EGatewayConfig.CreateFmt('%s erwartet NAME=WERT oder NAME: WERT',
      [AOptionName]);
  NamePart := Trim(Copy(AValue, 1, P - 1));
  ValuePart := Trim(Copy(AValue, P + 1, MaxInt));
  if NamePart = '' then
    raise EGatewayConfig.CreateFmt('%s enthält einen leeren Namen',
      [AOptionName]);
  AList.Values[NamePart] := ValuePart;
end;

procedure TGatewayConfig.LoadJsonFile(const AFileName: string);
var
  Stream: TFileStream;
  Data: TJSONData;
  Obj: TJSONObject;
  CorsData: TJSONData;
  I: Integer;
  Value64: Int64;
begin
  if not FileExists(AFileName) then
    raise EGatewayConfig.Create('Konfigurationsdatei nicht gefunden: ' + AFileName);
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  Data := nil;
  try
    Data := GetJSON(Stream);
    if Data.JSONType <> jtObject then
      raise EGatewayConfig.Create('Gateway-Konfiguration muss ein JSON-Objekt sein');
    Obj := TJSONObject(Data);

    FListenHost := JsonStringValue(Obj, 'listen', FListenHost);
    FListenHost := JsonStringValue(Obj, 'host', FListenHost);
    Value64 := JsonIntValue(Obj, 'port', FPort);
    if (Value64 > 0) and (Value64 <= 65535) then
      FPort := Word(Value64);
    FEndpoint := NormalizeEndpoint(JsonStringValue(Obj, 'path', FEndpoint));
    FEndpoint := NormalizeEndpoint(JsonStringValue(Obj, 'streamableHttpPath', FEndpoint));
    FStdioCommand := JsonStringValue(Obj, 'stdio', FStdioCommand);
    FExecutable := JsonStringValue(Obj, 'exec', FExecutable);
    FExecutable := JsonStringValue(Obj, 'executable', FExecutable);
    FWorkingDirectory := JsonStringValue(Obj, 'cwd', FWorkingDirectory);
    LoadJsonStringArray(Obj, 'args', FArguments);
    LoadJsonNameValues(Obj, 'env', FEnvironment);

    Value64 := JsonIntValue(Obj, 'sessionTimeout', FSessionTimeoutMs);
    if Value64 >= 0 then
      FSessionTimeoutMs := QWord(Value64);
    Value64 := JsonIntValue(Obj, 'requestTimeout', FRequestTimeoutMs);
    if Value64 > 0 then
      FRequestTimeoutMs := QWord(Value64);
    Value64 := JsonIntValue(Obj, 'ssePollTimeout', FSsePollTimeoutMs);
    if Value64 > 0 then
      FSsePollTimeoutMs := QWord(Value64);
    Value64 := JsonIntValue(Obj, 'maximumRequestBytes', FMaximumRequestBytes);
    if Value64 > 0 then
      FMaximumRequestBytes := Value64;

    FLogLevel := ParseGatewayLogLevel(JsonStringValue(Obj, 'logLevel',
      GatewayLogLevelName(FLogLevel)));
    FLogFileName := JsonStringValue(Obj, 'logFile', FLogFileName);
    FAuthToken := JsonStringValue(Obj, 'authToken', FAuthToken);
    FStrictAccept := JsonBoolValue(Obj, 'strictAccept', FStrictAccept);

    CorsData := Obj.Find('cors');
    if CorsData <> nil then
      case CorsData.JSONType of
        jtBoolean:
          begin
            FCorsEnabled := CorsData.AsBoolean;
            FAllowedOrigins.Clear;
            if FCorsEnabled then
              FAllowedOrigins.Add('*');
          end;
        jtString:
          begin
            FCorsEnabled := True;
            FAllowedOrigins.Clear;
            FAllowedOrigins.Add(CorsData.AsString);
          end;
        jtArray:
          begin
            FCorsEnabled := True;
            FAllowedOrigins.Clear;
            for I := 0 to TJSONArray(CorsData).Count - 1 do
              if TJSONArray(CorsData).Items[I].JSONType = jtString then
                FAllowedOrigins.Add(TJSONArray(CorsData).Strings[I]);
          end;
      end;
    LoadJsonStringArray(Obj, 'healthEndpoints', FHealthEndpoints);
    LoadJsonNameValues(Obj, 'headers', FResponseHeaders);
  finally
    Data.Free;
    Stream.Free;
  end;
end;

procedure TGatewayConfig.ParseArguments;
var
  I, P: Integer;
  Arg, Name, Value, OutputTransport: string;
  Parsed: Int64;

  function NextValue(const AOption: string): string;
  begin
    Inc(I);
    if I > ParamCount then
      raise EGatewayConfig.Create(AOption + ' erwartet einen Wert');
    Result := ParamStr(I);
  end;

begin
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    Name := Arg;
    Value := '';
    P := Pos('=', Arg);
    if (P > 2) and (Copy(Arg, 1, 2) = '--') then
    begin
      Name := Copy(Arg, 1, P - 1);
      Value := Copy(Arg, P + 1, MaxInt);
    end;

    if (Name = '--help') or (Name = '-h') then
      FShowHelp := True
    else if Name = '--version' then
      FShowVersion := True
    else if Name = '--config' then
    begin
      if Value = '' then
        NextValue(Name);
      { Already loaded during the first pass. }
    end
    else if Name = '--stdio' then
    begin
      if Value = '' then Value := NextValue(Name);
      FStdioCommand := Value;
      FExecutable := '';
      FArguments.Clear;
    end
    else if (Name = '--exec') or (Name = '--executable') then
    begin
      if Value = '' then Value := NextValue(Name);
      FExecutable := Value;
      FStdioCommand := '';
    end
    else if Name = '--arg' then
    begin
      if P = 0 then
        Value := NextValue(Name);
      FArguments.Add(Value);
    end
    else if Name = '--cwd' then
    begin
      if Value = '' then Value := NextValue(Name);
      FWorkingDirectory := Value;
    end
    else if Name = '--env' then
    begin
      if Value = '' then Value := NextValue(Name);
      AddNameValue(FEnvironment, Value, Name);
    end
    else if (Name = '--listen') or (Name = '--host') then
    begin
      if Value = '' then Value := NextValue(Name);
      FListenHost := Value;
    end
    else if Name = '--port' then
    begin
      if Value = '' then Value := NextValue(Name);
      if not TryStrToInt64(Value, Parsed) or (Parsed < 1) or (Parsed > 65535) then
        raise EGatewayConfig.Create('Ungültiger Port: ' + Value);
      FPort := Word(Parsed);
    end
    else if (Name = '--streamableHttpPath') or (Name = '--path') then
    begin
      if Value = '' then Value := NextValue(Name);
      FEndpoint := NormalizeEndpoint(Value);
    end
    else if Name = '--sessionTimeout' then
    begin
      if Value = '' then Value := NextValue(Name);
      if not TryStrToInt64(Value, Parsed) or (Parsed < 0) then
        raise EGatewayConfig.Create('Ungültiges Session-Timeout: ' + Value);
      FSessionTimeoutMs := QWord(Parsed);
    end
    else if Name = '--requestTimeout' then
    begin
      if Value = '' then Value := NextValue(Name);
      if not TryStrToInt64(Value, Parsed) or (Parsed < 1) then
        raise EGatewayConfig.Create('Ungültiges Request-Timeout: ' + Value);
      FRequestTimeoutMs := QWord(Parsed);
    end
    else if Name = '--ssePollTimeout' then
    begin
      if Value = '' then Value := NextValue(Name);
      if not TryStrToInt64(Value, Parsed) or (Parsed < 1) then
        raise EGatewayConfig.Create('Ungültiges SSE-Poll-Timeout: ' + Value);
      FSsePollTimeoutMs := QWord(Parsed);
    end
    else if Name = '--maximumRequestBytes' then
    begin
      if Value = '' then Value := NextValue(Name);
      if not TryStrToInt64(Value, Parsed) or (Parsed < 1) then
        raise EGatewayConfig.Create('Ungültige maximale Request-Größe: ' + Value);
      FMaximumRequestBytes := Parsed;
    end
    else if Name = '--cors' then
    begin
      FCorsEnabled := True;
      if Value = '' then
      begin
        FAllowedOrigins.Clear;
        FAllowedOrigins.Add('*');
      end
      else
        FAllowedOrigins.Add(Value);
    end
    else if Name = '--cors-origin' then
    begin
      if Value = '' then Value := NextValue(Name);
      FCorsEnabled := True;
      if (FAllowedOrigins.Count = 1) and (FAllowedOrigins[0] = '*') then
        FAllowedOrigins.Clear;
      FAllowedOrigins.Add(Value);
    end
    else if Name = '--no-cors' then
    begin
      FCorsEnabled := False;
      FAllowedOrigins.Clear;
    end
    else if Name = '--healthEndpoint' then
    begin
      if Value = '' then Value := NextValue(Name);
      FHealthEndpoints.Add(NormalizeEndpoint(Value));
    end
    else if Name = '--header' then
    begin
      if Value = '' then Value := NextValue(Name);
      AddNameValue(FResponseHeaders, Value, Name);
    end
    else if Name = '--authToken' then
    begin
      if Value = '' then Value := NextValue(Name);
      FAuthToken := Value;
    end
    else if Name = '--logLevel' then
    begin
      if Value = '' then Value := NextValue(Name);
      FLogLevel := ParseGatewayLogLevel(Value);
    end
    else if Name = '--logFile' then
    begin
      if Value = '' then Value := NextValue(Name);
      FLogFileName := Value;
    end
    else if Name = '--strictAccept' then
      FStrictAccept := True
    else if Name = '--no-strictAccept' then
      FStrictAccept := False
    else if Name = '--stateful' then
    begin
      { This gateway intentionally implements the stateful core mode only. }
    end
    else if Name = '--outputTransport' then
    begin
      if Value = '' then Value := NextValue(Name);
      OutputTransport := LowerCase(Trim(Value));
      if OutputTransport <> 'streamablehttp' then
        raise EGatewayConfig.Create('Nur --outputTransport streamableHttp wird unterstützt');
    end
    else if Copy(Name, 1, 2) = '--' then
      raise EGatewayConfig.Create('Unbekannte Option: ' + Name)
    else
      raise EGatewayConfig.Create('Unerwartetes Argument: ' + Arg);
    Inc(I);
  end;
end;

procedure TGatewayConfig.Load;
var
  I, P: Integer;
  Arg, ConfigFile: string;
begin
  ResetDefaults;
  ConfigFile := '';
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--config' then
    begin
      Inc(I);
      if I > ParamCount then
        raise EGatewayConfig.Create('--config erwartet einen Dateinamen');
      ConfigFile := ParamStr(I);
    end
    else if Pos('--config=', Arg) = 1 then
    begin
      P := Pos('=', Arg);
      ConfigFile := Copy(Arg, P + 1, MaxInt);
    end;
    Inc(I);
  end;
  if ConfigFile <> '' then
    LoadJsonFile(ExpandFileName(ConfigFile));
  ParseArguments;
  if not (FShowHelp or FShowVersion) then
    Validate;
end;

procedure TGatewayConfig.Validate;
var
  I: Integer;
begin
  if (Trim(FStdioCommand) = '') and (Trim(FExecutable) = '') then
    raise EGatewayConfig.Create('Es fehlt --stdio "COMMAND" oder --exec PROGRAM');
  if (Trim(FStdioCommand) <> '') and (Trim(FExecutable) <> '') then
    raise EGatewayConfig.Create('--stdio und --exec dürfen nicht gleichzeitig gesetzt sein');
  if (FWorkingDirectory <> '') and not DirectoryExists(FWorkingDirectory) then
    raise EGatewayConfig.Create('Arbeitsverzeichnis nicht gefunden: ' + FWorkingDirectory);
  if FEndpoint = '/' then
    raise EGatewayConfig.Create('Der MCP-Endpunkt darf nicht der Root-Pfad / sein');
  for I := 0 to FHealthEndpoints.Count - 1 do
    if SameText(FHealthEndpoints[I], FEndpoint) then
      raise EGatewayConfig.Create('Health-Endpunkt kollidiert mit MCP-Endpunkt: ' + FEndpoint);
  if FCorsEnabled and (FAllowedOrigins.Count = 0) then
    FAllowedOrigins.Add('*');
end;

function TGatewayConfig.UsesShell: Boolean;
begin
  Result := Trim(FStdioCommand) <> '';
end;

procedure TGatewayConfig.PrintVersion;
begin
  WriteLn('llc-mcp-gateway ', LLC_MCP_GATEWAY_VERSION);
end;

procedure TGatewayConfig.PrintHelp;
begin
  PrintVersion;
  WriteLn;
  WriteLn('Generischer MCP stdio -> stateful Streamable-HTTP Gateway.');
  WriteLn;
  WriteLn('Supergateway-kompatibler Kernmodus:');
  WriteLn('  llc-mcp-gateway --stdio "uvx blender-mcp" --stateful --port 8766');
  WriteLn;
  WriteLn('Robuste direkte Prozessform:');
  WriteLn('  llc-mcp-gateway --exec uv --arg run --arg=--directory \');
  WriteLn('    --arg /pfad/gimp-mcp --arg gimp_mcp_server.py --port 8766');
  WriteLn;
  WriteLn('Wichtige Optionen:');
  WriteLn('  --stdio COMMAND                 Kommando über System-Shell starten');
  WriteLn('  --exec PROGRAM --arg VALUE     Programm direkt und ohne Shell starten');
  WriteLn('  --cwd DIRECTORY                Arbeitsverzeichnis des MCP-Servers');
  WriteLn('  --env NAME=VALUE               Zusätzliche/geänderte Umgebungsvariable');
  WriteLn('  --listen HOST                  Bind-Adresse, Standard 127.0.0.1');
  WriteLn('  --port PORT                    Listen-Port, Standard 8000');
  WriteLn('  --streamableHttpPath PATH      MCP-Pfad, Standard /mcp');
  WriteLn('  --stateful                     Akzeptierte Kompatibilitätsoption');
  WriteLn('  --sessionTimeout MS            Idle-Timeout, 0 deaktiviert es');
  WriteLn('  --requestTimeout MS            Timeout je JSON-RPC-Request');
  WriteLn('  --cors[=ORIGIN]                CORS aktivieren; ohne Wert alle Origins');
  WriteLn('  --cors-origin ORIGIN           Erlaubte Origin wiederholbar ergänzen');
  WriteLn('  --healthEndpoint PATH          Einfacher Health-Endpunkt, wiederholbar');
  WriteLn('  --header NAME:VALUE            Zusätzlicher HTTP-Response-Header');
  WriteLn('  --authToken TOKEN              Bearer-Token für den Gateway-Zugriff');
  WriteLn('  --logLevel debug|info|none     Logging');
  WriteLn('  --config FILE                  JSON-Konfiguration laden');
  WriteLn('  --help / --version');
end;

end.
