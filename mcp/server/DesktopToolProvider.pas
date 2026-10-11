unit DesktopToolProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, ToolProvider, ServerConfig, ServerLog, DesktopRuntime;

type
  TDesktopToolProvider = class(TToolProvider)
  private
    FConfig: TServerConfig;
    FLogger: TServerLogger;
    FRuntime: TDesktopRuntime;
    procedure Log(const ACorrelationId, AMessage: string);
    function BytesToBase64(const AData: TBytes): string;
    function ExecuteInputEvents(AEvents: TJSONArray): TJSONObject;
    procedure AddCaptureProperties(AProperties: TJSONObject);
    procedure AddObserveProperties(AProperties: TJSONObject);
    function ObserveMeta: TJSONObject;
  public
    constructor Create(AConfig: TServerConfig; ALogger: TServerLogger);
    destructor Destroy; override;
    procedure AddTools(ATools: TJSONArray); override;
    function HandlesTool(const AName: string): Boolean; override;
    function CallTool(const AName: string; AArguments: TJSONObject;
      const ACorrelationId: string): TJSONObject; override;
  end;

implementation

uses
  McpProtocol, DesktopBackend, McpJson;

constructor TDesktopToolProvider.Create(AConfig: TServerConfig;
  ALogger: TServerLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FRuntime := TDesktopRuntime.Create;
end;

destructor TDesktopToolProvider.Destroy;
begin
  FRuntime.Free;
  inherited Destroy;
end;

procedure TDesktopToolProvider.Log(const ACorrelationId, AMessage: string);
begin
  if FLogger = nil then Exit;
  if ACorrelationId <> '' then
    FLogger.Write(ACorrelationId + ' desktop ' + AMessage)
  else
    FLogger.Write('desktop ' + AMessage);
end;

function TDesktopToolProvider.BytesToBase64(const AData: TBytes): string;
const
  Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  I, O, Remaining: SizeInt;
  B0, B1, B2: Byte;
begin
  if Length(AData) = 0 then Exit('');
  SetLength(Result, ((Length(AData) + 2) div 3) * 4);
  I := 0; O := 1;
  while I < Length(AData) do
  begin
    Remaining := Length(AData) - I;
    B0 := AData[I];
    if Remaining > 1 then B1 := AData[I + 1] else B1 := 0;
    if Remaining > 2 then B2 := AData[I + 2] else B2 := 0;
    Result[O] := Alphabet[(B0 shr 2) + 1];
    Result[O + 1] := Alphabet[(((B0 and $03) shl 4) or (B1 shr 4)) + 1];
    if Remaining > 1 then
      Result[O + 2] := Alphabet[(((B1 and $0F) shl 2) or (B2 shr 6)) + 1]
    else Result[O + 2] := '=';
    if Remaining > 2 then
      Result[O + 3] := Alphabet[(B2 and $3F) + 1]
    else Result[O + 3] := '=';
    Inc(I, 3); Inc(O, 4);
  end;
end;

function TDesktopToolProvider.ExecuteInputEvents(AEvents: TJSONArray): TJSONObject;
var
  Arguments: TJSONObject;
begin
  Arguments := TJSONObject.Create;
  try
    Arguments.Add('events', AEvents);
    Result := FRuntime.SendInput(Arguments);
  finally
    Arguments.Free;
  end;
end;

procedure TDesktopToolProvider.AddCaptureProperties(AProperties: TJSONObject);
begin
  AProperties.Add('target', StringProperty(
    'Capture target: foreground_monitor (default), primary_monitor, foreground_window, window, region, or virtual_desktop.'));
  AProperties.Add('handle', StringProperty(
    'Window handle from desktop_windows when target=window'));
  AProperties.Add('x', IntegerRangeProperty(Low(LongInt), High(LongInt),
    'Source x coordinate for target=region'));
  AProperties.Add('y', IntegerRangeProperty(Low(LongInt), High(LongInt),
    'Source y coordinate for target=region'));
  AProperties.Add('width', IntegerRangeProperty(1, 32768,
    'Source width required for target=region'));
  AProperties.Add('height', IntegerRangeProperty(1, 32768,
    'Source height required for target=region'));
  AProperties.Add('format', StringProperty(
    'png (default) or jpeg'));
  AProperties.Add('max_width', IntegerProperty(7680, 1, 16384,
    'Maximum returned image width; defaults to 7680'));
  AProperties.Add('max_height', IntegerProperty(4320, 1, 16384,
    'Maximum returned image height; defaults to 4320'));
  AProperties.Add('quality', IntegerProperty(85, 40, 95,
    'JPEG quality; ignored for PNG'));
  AProperties.Add('max_bytes', IntegerProperty(16777216, 32768, 33554432,
    'Maximum encoded image bytes; defaults to 16 MiB and is capped by server configuration'));
end;

procedure TDesktopToolProvider.AddObserveProperties(AProperties: TJSONObject);
begin
  AProperties.Add('target', StringProperty(
    'Capture target: foreground_window (default), window, foreground_monitor, primary_monitor, region, or virtual_desktop.'));
  AProperties.Add('handle', StringProperty(
    'Window handle from desktop_windows when target=window'));
  AProperties.Add('x', IntegerRangeProperty(Low(LongInt), High(LongInt),
    'Source x coordinate for target=region'));
  AProperties.Add('y', IntegerRangeProperty(Low(LongInt), High(LongInt),
    'Source y coordinate for target=region'));
  AProperties.Add('width', IntegerRangeProperty(1, 32768,
    'Source width required for target=region'));
  AProperties.Add('height', IntegerRangeProperty(1, 32768,
    'Source height required for target=region'));
  AProperties.Add('format', StringProperty(
    'png (default) or jpeg'));
  AProperties.Add('max_width', IntegerProperty(2048, 1, 16384,
    'Maximum returned image width; defaults to 2048'));
  AProperties.Add('max_height', IntegerProperty(2048, 1, 16384,
    'Maximum returned image height; defaults to 2048'));
  AProperties.Add('quality', IntegerProperty(85, 40, 95,
    'JPEG quality; ignored for PNG'));
  AProperties.Add('max_bytes', IntegerProperty(8388608, 32768, 33554432,
    'Maximum encoded image bytes; defaults to 8 MiB and is capped by server configuration'));
end;

function TDesktopToolProvider.ObserveMeta: TJSONObject;
var
  Requirements, Handling: TJSONObject;
  Modalities: TJSONArray;
begin
  Result := TJSONObject.Create;
  Requirements := TJSONObject.Create;
  Modalities := TJSONArray.Create;
  Modalities.Add('image');
  Requirements.Add('inputModalities', Modalities);
  Result.Add('com.locallightai/modelRequirements', Requirements);
  Handling := TJSONObject.Create;
  Handling.Add('image', 'model_context');
  Result.Add('com.locallightai/outputHandling', Handling);
end;

procedure TDesktopToolProvider.AddTools(ATools: TJSONArray);
var
  Props: TJSONObject;
begin
  {$IFDEF WINDOWS}
  if FConfig.DesktopWindowManagementEnabled then
  begin
    Props := TJSONObject.Create;
    Props.Add('include_invisible', BooleanProperty(False,
      'Include hidden or untitled top-level windows; normally leave false'));
    Props.Add('query', StringProperty(
      'Optional case-insensitive title or window-class filter'));
    Props.Add('limit', IntegerProperty(25, 1, 200,
      'Maximum number of windows returned'));
    Props.Add('offset', IntegerProperty(0, 0, 1000000,
      'Pagination offset; use next_offset when present'));
    Props.Add('details', BooleanProperty(False,
      'Include class name, visibility, enabled state and all raw fields'));
    ATools.Add(BuildTool('desktop_windows',
      'Lists current top-level Windows windows. Re-query whenever the GUI may have opened, closed, or replaced a window; handles are transient OS state.',
      ObjectSchema(Props, [])));

    Props := TJSONObject.Create;
    Props.Add('handle', StringProperty('Native window handle returned by desktop_windows'));
    Props.Add('action', StringProperty('activate, restore, minimize, maximize, or close'));
    Props.Add('verify', BooleanProperty(False,
      'Optionally wait briefly and verify the requested window state'));
    Props.Add('verification_timeout_ms', IntegerProperty(250, 0, 2000,
      'Verification wait in milliseconds when verify=true'));
    ATools.Add(BuildTool('desktop_window',
      'Performs one basic top-level window operation. This is window management, not semantic GUI automation.',
      ObjectSchema(Props, ['handle','action'])));
  end;

  if FConfig.DesktopCaptureEnabled then
  begin
    Props := TJSONObject.Create;
    AddCaptureProperties(Props);
    ATools.Add(BuildTool('desktop_capture',
      'Captures the foreground monitor, a selected window, a region, or the virtual desktop and returns the image as normal MCP image content.',
      ObjectSchema(Props, [])));

    Props := TJSONObject.Create;
    AddObserveProperties(Props);
    ATools.Add(BuildTool('desktop_observe',
      'Returns an internal screenshot for visual inspection by the current model. REQUIRES a model/host that can receive and understand image input; clients should not expose this tool to text-only models. This tool only observes pixels and does not identify clickable controls or perform GUI actions.',
      ObjectSchema(Props, []), ObserveMeta));
  end;

  if FConfig.DesktopInputEnabled then
  begin
    Props := TJSONObject.Create;
    Props.Add('text', StringProperty(
      'UTF-8 text sent to the application that currently owns keyboard focus'));
    ATools.Add(BuildTool('desktop_type_text',
      'Types text into the currently focused application/control. This is raw keyboard input: the server does not infer or verify which field receives it.',
      ObjectSchema(Props, ['text'])));

    Props := TJSONObject.Create;
    Props.Add('key', StringProperty(
      'Key name such as enter, escape, tab, left, right, up, down, home, end, delete, backspace, ctrl, alt, shift, F1..F24, a letter, or a digit'));
    Props.Add('state', StringProperty(
      'press (default), down, or up'));
    ATools.Add(BuildTool('desktop_key',
      'Sends a raw keyboard key action to the application that currently owns keyboard focus. The server does not infer the intended GUI control.',
      ObjectSchema(Props, ['key'])));
  end;
  {$ENDIF}
end;

function TDesktopToolProvider.HandlesTool(const AName: string): Boolean;
begin
  {$IFDEF WINDOWS}
  Result := FConfig.DesktopEnabled and
    ((FConfig.DesktopWindowManagementEnabled and
      ((AName = 'desktop_windows') or (AName = 'desktop_window'))) or
     (FConfig.DesktopCaptureEnabled and
      ((AName = 'desktop_capture') or (AName = 'desktop_observe'))) or
     (FConfig.DesktopInputEnabled and
      ((AName = 'desktop_type_text') or (AName = 'desktop_key'))));
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

function TDesktopToolProvider.CallTool(const AName: string;
  AArguments: TJSONObject; const ACorrelationId: string): TJSONObject;
var
  Structured: TJSONObject;
  Events: TJSONArray;
  EventObject: TJSONObject;
  CaptureResult: TDesktopCaptureResult;
  Encoded, Summary, TargetName: string;
begin
  Log(ACorrelationId, 'call ' + AName);

  if AName = 'desktop_windows' then
  begin
    Structured := FRuntime.ListWindows(AArguments);
    Exit(NewToolTextResult('Current top-level window list returned.', Structured, False));
  end;

  if AName = 'desktop_window' then
  begin
    Structured := FRuntime.PerformWindowAction(AArguments);
    Exit(NewToolTextResult('Window operation completed.', Structured, False));
  end;

  if AName = 'desktop_type_text' then
  begin
    Events := TJSONArray.Create;
    EventObject := TJSONObject.Create;
    EventObject.Add('type', 'text');
    EventObject.Add('text', JsonString(AArguments, 'text'));
    Events.Add(EventObject);
    Structured := ExecuteInputEvents(Events);
    Exit(NewToolTextResult('Text sent to the current keyboard focus.', Structured, False));
  end;

  if AName = 'desktop_key' then
  begin
    Events := TJSONArray.Create;
    EventObject := TJSONObject.Create;
    EventObject.Add('type', 'key');
    EventObject.Add('key', JsonString(AArguments, 'key'));
    EventObject.Add('state', JsonString(AArguments, 'state', 'press'));
    Events.Add(EventObject);
    Structured := ExecuteInputEvents(Events);
    Exit(NewToolTextResult('Key action sent to the current keyboard focus.', Structured, False));
  end;

  if (AName = 'desktop_capture') or (AName = 'desktop_observe') then
  begin
    if AName = 'desktop_observe' then
    begin
      if (AArguments.Find('target') = nil) and
         (AArguments.Find('x') = nil) and (AArguments.Find('y') = nil) and
         (AArguments.Find('width') = nil) and (AArguments.Find('height') = nil) then
      begin
        if AArguments.Find('handle') <> nil then
          AArguments.Add('target', 'window')
        else
          AArguments.Add('target', 'foreground_window');
      end;
      if AArguments.Find('max_width') = nil then AArguments.Add('max_width', 2048);
      if AArguments.Find('max_height') = nil then AArguments.Add('max_height', 2048);
      if AArguments.Find('max_bytes') = nil then AArguments.Add('max_bytes', 8388608);
    end;

    CaptureResult := FRuntime.Capture(AArguments, FConfig.DesktopMaximumImageBytes);
    Encoded := BytesToBase64(CaptureResult.Data);
    Structured := TJSONObject.Create;
    Structured.Add('mime_type', CaptureResult.MimeType);
    Structured.Add('bytes', Length(CaptureResult.Data));
    Structured.Add('width', CaptureResult.Width);
    Structured.Add('height', CaptureResult.Height);
    if CaptureResult.Quality > 0 then Structured.Add('quality', CaptureResult.Quality);
    if CaptureResult.CaptureMethod <> '' then Structured.Add('capture_method', CaptureResult.CaptureMethod);
    if AName = 'desktop_observe' then
      TargetName := LowerCase(Trim(JsonString(AArguments, 'target', 'foreground_window')))
    else
      TargetName := LowerCase(Trim(JsonString(AArguments, 'target', 'foreground_monitor')));
    Structured.Add('target', TargetName);
    if CaptureResult.WindowHandle <> 0 then
    begin
      Structured.Add('window_handle', UIntToStr(CaptureResult.WindowHandle));
      if CaptureResult.WindowTitle <> '' then
        Structured.Add('window_title', CaptureResult.WindowTitle);
    end;
    if AName = 'desktop_observe' then
    begin
      Structured.Add('delivery', 'model_context');
      Summary := Format('Internal visual observation: %s %dx%d (%d bytes).',
        [CaptureResult.MimeType, CaptureResult.Width, CaptureResult.Height,
         Length(CaptureResult.Data)]);
    end
    else
      Summary := Format('Desktop capture: %s %dx%d (%d bytes).',
        [CaptureResult.MimeType, CaptureResult.Width, CaptureResult.Height,
         Length(CaptureResult.Data)]);
    Exit(NewToolImageResult(CaptureResult.MimeType, Encoded, Structured, Summary));
  end;

  raise Exception.CreateFmt('Unknown or disabled desktop tool: %s', [AName]);
end;

end.
