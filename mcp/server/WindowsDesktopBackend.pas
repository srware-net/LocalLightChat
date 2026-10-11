unit WindowsDesktopBackend;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, DesktopBackend;

type
  TWindowsDesktopBackend = class(TDesktopBackend)
  private
    function KeyNameToVirtualKey(const AName: string): Word;
    procedure SendVirtualKey(AVirtualKey: Word; const AState: string);
    procedure PasteText(const AText: string);
  public
    function ListWindows(AArguments: TJSONObject): TJSONObject; override;
    function PerformWindowAction(AArguments: TJSONObject): TJSONObject; override;
    function Capture(AArguments: TJSONObject;
      AMaximumImageBytes: Cardinal): TDesktopCaptureResult; override;
    function SendInput(AArguments: TJSONObject): TJSONObject; override;
  end;

implementation

uses
  Windows, Math, McpJson, FPImage, FPWriteJPEG, FPWritePNG, ZStream;

const
  CAPTUREBLT_FLAG = $40000000;
  WHEEL_DELTA_VALUE = 120;
  MCP_MONITOR_DEFAULTTOPRIMARY = 1;
  MCP_MONITOR_DEFAULTTONEAREST = 2;
  MCP_GA_ROOTOWNER = 3;
  MCP_PW_RENDERFULLCONTENT = $00000002;

type
  TMcpMonitorInfo = packed record
    cbSize: DWORD;
    rcMonitor: TRect;
    rcWork: TRect;
    dwFlags: DWORD;
  end;
  PMcpMonitorInfo = ^TMcpMonitorInfo;

  TWindowEnumContext = class
  public
    Items: TJSONArray;
    constructor Create;
    destructor Destroy; override;
  end;


function McpMonitorFromWindow(AWindow: HWND; AFlags: DWORD): HANDLE; stdcall;
  external 'user32.dll' name 'MonitorFromWindow';
function McpMonitorFromPoint(APoint: TPoint; AFlags: DWORD): HANDLE; stdcall;
  external 'user32.dll' name 'MonitorFromPoint';
function McpGetMonitorInfoW(AMonitor: HANDLE; AInfo: PMcpMonitorInfo): WINBOOL; stdcall;
  external 'user32.dll' name 'GetMonitorInfoW';
function McpGetAncestor(AWindow: HWND; AFlags: UINT): HWND; stdcall;
  external 'user32.dll' name 'GetAncestor';
function McpGetLastActivePopup(AWindow: HWND): HWND; stdcall;
  external 'user32.dll' name 'GetLastActivePopup';
function McpPrintWindow(AWindow: HWND; ADestination: HDC; AFlags: UINT): WINBOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';
function McpIsHungAppWindow(AWindow: HWND): WINBOOL; stdcall;
  external 'user32.dll' name 'IsHungAppWindow';

constructor TWindowEnumContext.Create;
begin
  inherited Create;
  Items := TJSONArray.Create;
end;

destructor TWindowEnumContext.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

function WideToUtf8(const AValue: UnicodeString): string;
begin
  Result := string(UTF8Encode(AValue));
end;

function MaxInteger(A, B: Integer): Integer;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

function WinBool(AValue: LongBool): Boolean; inline;
begin
  Result := Boolean(AValue);
end;

function EnumWindowCallback(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  Context: TWindowEnumContext;
  Item, Bounds: TJSONObject;
  Title, ClassName: UnicodeString;
  ClassBuffer: array[0..255] of WideChar;
  TitleLength, ClassLength: Integer;
  WindowRect: TRect;
  ProcessId: DWord;
begin
  Result := True;
  Context := TWindowEnumContext(Pointer(PtrUInt(AParam)));

  TitleLength := GetWindowTextLengthW(AWindow);
  SetLength(Title, TitleLength + 1);
  if TitleLength > 0 then
    TitleLength := GetWindowTextW(AWindow, PWideChar(Title), Length(Title))
  else
    TitleLength := 0;
  SetLength(Title, TitleLength);

  FillChar(ClassBuffer, SizeOf(ClassBuffer), 0);
  ClassLength := GetClassNameW(AWindow, PWideChar(@ClassBuffer[0]), Length(ClassBuffer));
  ProcessId := 0;
  GetWindowThreadProcessId(AWindow, @ProcessId);
  FillChar(WindowRect, SizeOf(WindowRect), 0);
  GetWindowRect(AWindow, WindowRect);

  Item := TJSONObject.Create;
  Item.Add('handle', UIntToStr(QWord(PtrUInt(AWindow))));
  Item.Add('title', WideToUtf8(Title));
  if ClassLength > 0 then
  begin
    SetString(ClassName, PWideChar(@ClassBuffer[0]), ClassLength);
    Item.Add('class_name', WideToUtf8(ClassName));
  end
  else
    Item.Add('class_name', '');
  Item.Add('process_id', Int64(ProcessId));
  Item.Add('visible', WinBool(IsWindowVisible(AWindow)));
  Item.Add('enabled', WinBool(IsWindowEnabled(AWindow)));
  Item.Add('minimized', WinBool(IsIconic(AWindow)));
  Item.Add('maximized', WinBool(IsZoomed(AWindow)));
  Item.Add('foreground', GetForegroundWindow = AWindow);

  Bounds := TJSONObject.Create;
  Bounds.Add('x', WindowRect.Left);
  Bounds.Add('y', WindowRect.Top);
  Bounds.Add('width', WindowRect.Right - WindowRect.Left);
  Bounds.Add('height', WindowRect.Bottom - WindowRect.Top);
  Item.Add('bounds', Bounds);
  Context.Items.Add(Item);
end;

function CompactWindowItem(AItem: TJSONObject): TJSONObject;
var
  BoundsData: TJSONData;
begin
  Result := TJSONObject.Create;
  Result.Add('handle', JsonString(AItem, 'handle'));
  Result.Add('title', JsonString(AItem, 'title'));
  Result.Add('process_id', JsonInteger(AItem, 'process_id'));
  Result.Add('foreground', JsonBoolean(AItem, 'foreground', False));
  Result.Add('minimized', JsonBoolean(AItem, 'minimized', False));
  Result.Add('maximized', JsonBoolean(AItem, 'maximized', False));
  BoundsData := AItem.Find('bounds');
  if BoundsData <> nil then
    Result.Add('bounds', BoundsData.Clone);
end;

function TWindowsDesktopBackend.ListWindows(
  AArguments: TJSONObject): TJSONObject;
var
  Context: TWindowEnumContext;
  Candidates, Returned: TJSONArray;
  I, FirstIndex, LastIndex, LimitValue, OffsetValue, TotalCount, ReturnedCount: Integer;
  IncludeInvisible, Details, MatchesVisibility, MatchesQuery: Boolean;
  Item: TJSONObject;
  TitleText, ClassText, QueryText: string;
begin
  IncludeInvisible := JsonBoolean(AArguments, 'include_invisible', False);
  Details := JsonBoolean(AArguments, 'details', False);
  LimitValue := JsonInteger(AArguments, 'limit', 25);
  OffsetValue := JsonInteger(AArguments, 'offset', 0);
  QueryText := LowerCase(Trim(JsonString(AArguments, 'query', '')));

  if (LimitValue < 1) or (LimitValue > 200) then
    raise Exception.Create('limit must be between 1 and 200');
  if OffsetValue < 0 then
    raise Exception.Create('offset must be zero or positive');

  Context := TWindowEnumContext.Create;
  Candidates := TJSONArray.Create;
  Returned := nil;
  try
    if not WinBool(EnumWindows(@EnumWindowCallback, LPARAM(PtrInt(Context)))) then
      RaiseLastOSError;

    for I := 0 to Context.Items.Count - 1 do
    begin
      Item := TJSONObject(Context.Items.Items[I]);
      TitleText := Trim(JsonString(Item, 'title'));
      ClassText := Trim(JsonString(Item, 'class_name'));

      if IncludeInvisible then
        MatchesVisibility := (TitleText <> '') or (ClassText <> '')
      else
        MatchesVisibility := JsonBoolean(Item, 'visible', False) and
          (TitleText <> '');

      MatchesQuery := (QueryText = '') or
        (Pos(QueryText, LowerCase(TitleText)) > 0) or
        (Pos(QueryText, LowerCase(ClassText)) > 0);

      if MatchesVisibility and MatchesQuery then
        Candidates.Add(Item.Clone);
    end;

    TotalCount := Candidates.Count;
    Returned := TJSONArray.Create;
    FirstIndex := OffsetValue;
    LastIndex := FirstIndex + LimitValue - 1;
    if LastIndex >= TotalCount then
      LastIndex := TotalCount - 1;

    if FirstIndex < TotalCount then
      for I := FirstIndex to LastIndex do
      begin
        Item := TJSONObject(Candidates.Items[I]);
        if Details then
          Returned.Add(Item.Clone)
        else
          Returned.Add(CompactWindowItem(Item));
      end;

    ReturnedCount := Returned.Count;
    Result := TJSONObject.Create;
    Result.Add('windows', Returned);
    Returned := nil;
    Result.Add('count', ReturnedCount);
    Result.Add('total', TotalCount);
    Result.Add('offset', OffsetValue);
    Result.Add('limit', LimitValue);
    Result.Add('truncated', OffsetValue + ReturnedCount < TotalCount);
    if OffsetValue + ReturnedCount < TotalCount then
      Result.Add('next_offset', OffsetValue + ReturnedCount);
  finally
    Returned.Free;
    Candidates.Free;
    Context.Free;
  end;
end;

function ResolveActivatableWindow(AWindow: HWND): HWND;
var
  RootWindow, PopupWindow: HWND;
begin
  Result := AWindow;
  RootWindow := McpGetAncestor(AWindow, MCP_GA_ROOTOWNER);
  if RootWindow <> 0 then
    Result := RootWindow;
  PopupWindow := McpGetLastActivePopup(Result);
  if (PopupWindow <> 0) and WinBool(IsWindowVisible(PopupWindow)) then
    Result := PopupWindow;
end;

function WindowActionCondition(AWindow: HWND;
  const AAction: string): Boolean;
begin
  if AAction = 'activate' then
    Result := GetForegroundWindow = AWindow
  else if AAction = 'restore' then
    Result := WinBool(IsWindow(AWindow)) and (not WinBool(IsIconic(AWindow)))
  else if AAction = 'minimize' then
    Result := WinBool(IsWindow(AWindow)) and WinBool(IsIconic(AWindow))
  else if AAction = 'maximize' then
    Result := WinBool(IsWindow(AWindow)) and WinBool(IsZoomed(AWindow))
  else if AAction = 'close' then
    Result := not WinBool(IsWindow(AWindow))
  else
    Result := False;
end;

function WaitForWindowAction(AWindow: HWND; const AAction: string;
  ATimeoutMs: Integer): Boolean;
var
  Remaining: Integer;
begin
  Remaining := ATimeoutMs;
  repeat
    if WindowActionCondition(AWindow, AAction) then
      Exit(True);
    if Remaining <= 0 then
      Break;
    Sleep(25);
    Dec(Remaining, 25);
  until False;
  Result := WindowActionCondition(AWindow, AAction);
end;

function RequestWindowActivation(AWindow: HWND; out AEffectiveWindow: HWND;
  out AStrategy: string): Boolean;
const
  MCP_SWP_ASYNCWINDOWPOS = $4000;
var
  ForegroundResult, WasIconic: Boolean;
begin
  AEffectiveWindow := ResolveActivatableWindow(AWindow);
  AWindow := AEffectiveWindow;
  AStrategy := 'set_foreground_window';

  { Do not attach input queues and do not call SetFocus/SetActiveWindow across
    processes. Those techniques can couple the server, debugger, and target
    GUI queues and make all involved applications appear locked. Every call in
    this path is bounded and does not wait for the target thread. }
  WasIconic := WinBool(IsIconic(AWindow));
  if WasIconic then
    ShowWindowAsync(AWindow, SW_RESTORE)
  else
    ShowWindowAsync(AWindow, SW_SHOW);

  { Give a minimized target one short scheduler slice to process the asynchronous
    restore request. This is a bounded delay only; no message queues or locks are
    shared with the target process. }
  if WasIconic then
    Sleep(25);

  SetWindowPos(AWindow, HWND_TOP, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW or MCP_SWP_ASYNCWINDOWPOS);
  ForegroundResult := WinBool(SetForegroundWindow(AWindow));

  if (not ForegroundResult) and (GetForegroundWindow <> AWindow) then
  begin
    { A short ALT press is a compatibility fallback for the ordinary Windows
      foreground-lock rules. It does not join another thread's input queue. }
    keybd_event(VK_MENU, 0, 0, 0);
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
    ForegroundResult := WinBool(SetForegroundWindow(AWindow));
    AStrategy := 'alt_then_set_foreground_window';
  end;

  { A request was dispatched successfully once the handle was validated. The
    optional verification step decides separately whether Windows completed it. }
  Result := True;
end;

function TWindowsDesktopBackend.PerformWindowAction(
  AArguments: TJSONObject): TJSONObject;
var
  WindowHandle, EffectiveWindow, ForegroundBefore, ForegroundAfter: HWND;
  HandleValue: QWord;
  HandleData: TJSONData;
  HandleText, ActionName, Strategy: string;
  RequestSent, VerifyRequested, VerificationPassed: Boolean;
  VerificationTimeoutMs: Integer;
begin
  HandleData := AArguments.Find('handle');
  if HandleData = nil then
    raise Exception.Create('handle is required');
  HandleText := HandleData.AsString;
  if not TryStrToQWord(HandleText, HandleValue) then
    raise Exception.Create('handle must be an unsigned integer string');
  WindowHandle := HWND(PtrUInt(HandleValue));
  if (WindowHandle = 0) or (not WinBool(IsWindow(WindowHandle))) then
    raise Exception.Create('handle does not identify a current Windows window');

  ActionName := LowerCase(Trim(JsonString(AArguments, 'action')));
  VerifyRequested := JsonBoolean(AArguments, 'verify', False);
  VerificationTimeoutMs := JsonInteger(AArguments,
    'verification_timeout_ms', 250);
  if (VerificationTimeoutMs < 0) or (VerificationTimeoutMs > 2000) then
    raise Exception.Create('verification_timeout_ms must be between 0 and 2000');

  ForegroundBefore := GetForegroundWindow;
  RequestSent := False;
  VerificationPassed := False;
  Strategy := 'async_window_request';
  EffectiveWindow := WindowHandle;

  if ActionName = 'activate' then
    RequestSent := RequestWindowActivation(WindowHandle, EffectiveWindow,
      Strategy)
  else if ActionName = 'restore' then
  begin
    ShowWindowAsync(WindowHandle, SW_RESTORE);
    RequestSent := True;
  end
  else if ActionName = 'minimize' then
  begin
    ShowWindowAsync(WindowHandle, SW_MINIMIZE);
    RequestSent := True;
  end
  else if ActionName = 'maximize' then
  begin
    ShowWindowAsync(WindowHandle, SW_MAXIMIZE);
    RequestSent := True;
  end
  else if ActionName = 'close' then
    RequestSent := WinBool(PostMessage(WindowHandle, WM_CLOSE, 0, 0))
  else
    raise Exception.Create('action must be activate, restore, minimize, maximize, or close');

  if VerifyRequested and RequestSent then
    VerificationPassed := WaitForWindowAction(EffectiveWindow, ActionName,
      VerificationTimeoutMs);

  ForegroundAfter := GetForegroundWindow;
  Result := TJSONObject.Create;
  Result.Add('handle', HandleText);
  Result.Add('effective_handle', UIntToStr(QWord(PtrUInt(EffectiveWindow))));
  Result.Add('action', ActionName);
  { success reports whether the action request was accepted. Optional
    verification is deliberately separate so a transient foreground check does
    not turn a dispatched action into a tool failure and trigger retry loops. }
  Result.Add('success', RequestSent);
  Result.Add('request_sent', RequestSent);
  Result.Add('strategy', Strategy);
  Result.Add('verification_requested', VerifyRequested);
  Result.Add('still_exists', WinBool(IsWindow(WindowHandle)));
  if VerifyRequested then
  begin
    Result.Add('verification_timeout_ms', VerificationTimeoutMs);
    Result.Add('verification_passed', VerificationPassed);
    Result.Add('foreground_before',
      UIntToStr(QWord(PtrUInt(ForegroundBefore))));
    Result.Add('foreground_after',
      UIntToStr(QWord(PtrUInt(ForegroundAfter))));
    Result.Add('foreground', ForegroundAfter = EffectiveWindow);
  end;
end;

procedure CaptureScreenPixels(ASourceX, ASourceY, ASourceWidth,
  ASourceHeight, AOutputWidth, AOutputHeight: Integer; out APixels: TBytes);
var
  ScreenDc, MemoryDc: HDC;
  Bitmap: HBITMAP;
  OldBitmap: HGDIOBJ;
  DibInfo: BITMAPINFO;
  Captured: LongBool;
  PixelBytes: QWord;
begin
  PixelBytes := QWord(AOutputWidth) * QWord(AOutputHeight) * 4;
  if PixelBytes > High(LongInt) then
    raise Exception.Create('capture is too large');

  ScreenDc := GetDC(0);
  if ScreenDc = 0 then
    RaiseLastOSError;
  MemoryDc := CreateCompatibleDC(ScreenDc);
  if MemoryDc = 0 then
  begin
    ReleaseDC(0, ScreenDc);
    RaiseLastOSError;
  end;
  Bitmap := CreateCompatibleBitmap(ScreenDc, AOutputWidth, AOutputHeight);
  if Bitmap = 0 then
  begin
    DeleteDC(MemoryDc);
    ReleaseDC(0, ScreenDc);
    RaiseLastOSError;
  end;

  OldBitmap := SelectObject(MemoryDc, Bitmap);
  try
    if (AOutputWidth = ASourceWidth) and (AOutputHeight = ASourceHeight) then
      Captured := BitBlt(MemoryDc, 0, 0, AOutputWidth, AOutputHeight,
        ScreenDc, ASourceX, ASourceY, SRCCOPY or CAPTUREBLT_FLAG)
    else
    begin
      SetStretchBltMode(MemoryDc, HALFTONE);
      Captured := StretchBlt(MemoryDc, 0, 0, AOutputWidth, AOutputHeight,
        ScreenDc, ASourceX, ASourceY, ASourceWidth, ASourceHeight,
        SRCCOPY or CAPTUREBLT_FLAG);
    end;
    if not WinBool(Captured) then
      RaiseLastOSError;

    SelectObject(MemoryDc, OldBitmap);
    OldBitmap := 0;

    FillChar(DibInfo, SizeOf(DibInfo), 0);
    DibInfo.bmiHeader.biSize := SizeOf(DibInfo.bmiHeader);
    DibInfo.bmiHeader.biWidth := AOutputWidth;
    DibInfo.bmiHeader.biHeight := -AOutputHeight;
    DibInfo.bmiHeader.biPlanes := 1;
    DibInfo.bmiHeader.biBitCount := 32;
    DibInfo.bmiHeader.biCompression := BI_RGB;

    SetLength(APixels, SizeInt(PixelBytes));
    if GetDIBits(ScreenDc, Bitmap, 0, AOutputHeight, @APixels[0],
      DibInfo, DIB_RGB_COLORS) = 0 then
      RaiseLastOSError;
  finally
    if OldBitmap <> 0 then
      SelectObject(MemoryDc, OldBitmap);
    DeleteObject(Bitmap);
    DeleteDC(MemoryDc);
    ReleaseDC(0, ScreenDc);
  end;
end;

function WindowTitleUtf8(AWindow: HWND): string;
var
  Title: UnicodeString;
  TitleLength: Integer;
begin
  Result := '';
  TitleLength := GetWindowTextLengthW(AWindow);
  if TitleLength <= 0 then
    Exit;
  SetLength(Title, TitleLength + 1);
  TitleLength := GetWindowTextW(AWindow, PWideChar(Title), Length(Title));
  if TitleLength <= 0 then
    Exit;
  SetLength(Title, TitleLength);
  Result := WideToUtf8(Title);
end;

function WindowOwnsForeground(AWindow: HWND): Boolean;
var
  ForegroundWindow, WindowRoot, ForegroundRoot: HWND;
begin
  ForegroundWindow := GetForegroundWindow;
  if ForegroundWindow = 0 then
    Exit(False);
  if ForegroundWindow = AWindow then
    Exit(True);
  WindowRoot := McpGetAncestor(AWindow, MCP_GA_ROOTOWNER);
  if WindowRoot = 0 then
    WindowRoot := AWindow;
  ForegroundRoot := McpGetAncestor(ForegroundWindow, MCP_GA_ROOTOWNER);
  if ForegroundRoot = 0 then
    ForegroundRoot := ForegroundWindow;
  Result := WindowRoot = ForegroundRoot;
end;

procedure ReadBitmapPixels(AReferenceDc: HDC; ABitmap: HBITMAP;
  AWidth, AHeight: Integer; out APixels: TBytes);
var
  DibInfo: BITMAPINFO;
  PixelBytes: QWord;
begin
  PixelBytes := QWord(AWidth) * QWord(AHeight) * 4;
  if PixelBytes > High(LongInt) then
    raise Exception.Create('capture is too large');
  FillChar(DibInfo, SizeOf(DibInfo), 0);
  DibInfo.bmiHeader.biSize := SizeOf(DibInfo.bmiHeader);
  DibInfo.bmiHeader.biWidth := AWidth;
  DibInfo.bmiHeader.biHeight := -AHeight;
  DibInfo.bmiHeader.biPlanes := 1;
  DibInfo.bmiHeader.biBitCount := 32;
  DibInfo.bmiHeader.biCompression := BI_RGB;
  SetLength(APixels, SizeInt(PixelBytes));
  if GetDIBits(AReferenceDc, ABitmap, 0, AHeight, @APixels[0],
    DibInfo, DIB_RGB_COLORS) = 0 then
    RaiseLastOSError;
end;

function PixelsHaveVisibleVariation(const APixels: TBytes): Boolean;
var
  I, StepSize, SampleCount, Brightness, MinimumValue, MaximumValue: Integer;
begin
  if Length(APixels) < 4 then
    Exit(False);
  StepSize := Length(APixels) div 4096;
  StepSize := (StepSize div 4) * 4;
  if StepSize < 4 then
    StepSize := 4;
  MinimumValue := High(Integer);
  MaximumValue := Low(Integer);
  SampleCount := 0;
  I := 0;
  while I + 2 < Length(APixels) do
  begin
    Brightness := Integer(APixels[I]) + Integer(APixels[I + 1]) +
      Integer(APixels[I + 2]);
    if Brightness < MinimumValue then
      MinimumValue := Brightness;
    if Brightness > MaximumValue then
      MaximumValue := Brightness;
    Inc(SampleCount);
    if (MaximumValue - MinimumValue) >= 18 then
      Exit(True);
    Inc(I, StepSize);
  end;
  Result := (SampleCount > 0) and ((MaximumValue - MinimumValue) >= 18);
end;

procedure CaptureWindowPixels(AWindow: HWND; ASourceX, ASourceY,
  ASourceWidth, ASourceHeight, AOutputWidth, AOutputHeight: Integer;
  out APixels: TBytes; out ACaptureMethod: string);
var
  ScreenDc, SourceDc, OutputDc: HDC;
  SourceBitmap, OutputBitmap: HBITMAP;
  OldSourceBitmap, OldOutputBitmap: HGDIOBJ;
  Captured: Boolean;
  WindowPixels: TBytes;
begin
  if WinBool(McpIsHungAppWindow(AWindow)) then
    raise Exception.Create('Target window is not responding; window rendering was not attempted');

  ScreenDc := GetDC(0);
  if ScreenDc = 0 then
    RaiseLastOSError;
  SourceDc := 0;
  OutputDc := 0;
  SourceBitmap := 0;
  OutputBitmap := 0;
  OldSourceBitmap := 0;
  OldOutputBitmap := 0;
  try
    SourceDc := CreateCompatibleDC(ScreenDc);
    if SourceDc = 0 then
      RaiseLastOSError;
    SourceBitmap := CreateCompatibleBitmap(ScreenDc, ASourceWidth,
      ASourceHeight);
    if SourceBitmap = 0 then
      RaiseLastOSError;
    OldSourceBitmap := SelectObject(SourceDc, SourceBitmap);
    PatBlt(SourceDc, 0, 0, ASourceWidth, ASourceHeight, BLACKNESS);

    Captured := WinBool(McpPrintWindow(AWindow, SourceDc,
      MCP_PW_RENDERFULLCONTENT));
    ACaptureMethod := 'print_window';

    if Captured then
    begin
      SelectObject(SourceDc, OldSourceBitmap);
      OldSourceBitmap := 0;
      ReadBitmapPixels(ScreenDc, SourceBitmap, ASourceWidth, ASourceHeight,
        WindowPixels);
      OldSourceBitmap := SelectObject(SourceDc, SourceBitmap);
      if not PixelsHaveVisibleVariation(WindowPixels) then
        Captured := False;
    end;

    if not Captured then
    begin
      if not WindowOwnsForeground(AWindow) then
        raise Exception.Create(
          'The requested window could not render itself and is not in the foreground. A screen-rectangle fallback was refused because it could capture another application. Activate the window or choose another handle.');
      if not WinBool(BitBlt(SourceDc, 0, 0, ASourceWidth, ASourceHeight,
        ScreenDc, ASourceX, ASourceY, SRCCOPY or CAPTUREBLT_FLAG)) then
        RaiseLastOSError;
      ACaptureMethod := 'foreground_screen_fallback';
    end;

    if (AOutputWidth = ASourceWidth) and
       (AOutputHeight = ASourceHeight) then
    begin
      SelectObject(SourceDc, OldSourceBitmap);
      OldSourceBitmap := 0;
      ReadBitmapPixels(ScreenDc, SourceBitmap, AOutputWidth, AOutputHeight,
        APixels);
    end
    else
    begin
      OutputDc := CreateCompatibleDC(ScreenDc);
      if OutputDc = 0 then
        RaiseLastOSError;
      OutputBitmap := CreateCompatibleBitmap(ScreenDc, AOutputWidth,
        AOutputHeight);
      if OutputBitmap = 0 then
        RaiseLastOSError;
      OldOutputBitmap := SelectObject(OutputDc, OutputBitmap);
      SetStretchBltMode(OutputDc, HALFTONE);
      if not WinBool(StretchBlt(OutputDc, 0, 0, AOutputWidth,
        AOutputHeight, SourceDc, 0, 0, ASourceWidth, ASourceHeight,
        SRCCOPY)) then
        RaiseLastOSError;
      SelectObject(OutputDc, OldOutputBitmap);
      OldOutputBitmap := 0;
      ReadBitmapPixels(ScreenDc, OutputBitmap, AOutputWidth, AOutputHeight,
        APixels);
    end;
  finally
    if (SourceDc <> 0) and (OldSourceBitmap <> 0) then
      SelectObject(SourceDc, OldSourceBitmap);
    if (OutputDc <> 0) and (OldOutputBitmap <> 0) then
      SelectObject(OutputDc, OldOutputBitmap);
    if OutputBitmap <> 0 then
      DeleteObject(OutputBitmap);
    if SourceBitmap <> 0 then
      DeleteObject(SourceBitmap);
    if OutputDc <> 0 then
      DeleteDC(OutputDc);
    if SourceDc <> 0 then
      DeleteDC(SourceDc);
    ReleaseDC(0, ScreenDc);
  end;
end;

procedure PixelsToFpImage(const APixels: TBytes; AWidth, AHeight: Integer;
  AImage: TFPMemoryImage);
var
  Color: TFPColor;
  X, Y, PixelIndex: Integer;
begin
  Color.Alpha := High(Word);
  PixelIndex := 0;
  for Y := 0 to AHeight - 1 do
    for X := 0 to AWidth - 1 do
    begin
      Color.Blue := Word(APixels[PixelIndex]) * 257;
      Color.Green := Word(APixels[PixelIndex + 1]) * 257;
      Color.Red := Word(APixels[PixelIndex + 2]) * 257;
      AImage.Colors[X, Y] := Color;
      Inc(PixelIndex, 4);
    end;
end;

function StreamToBytes(AStream: TMemoryStream): TBytes;
begin
  SetLength(Result, SizeInt(AStream.Size));
  if Length(Result) > 0 then
  begin
    AStream.Position := 0;
    AStream.ReadBuffer(Result[0], Length(Result));
  end;
end;

function EncodePixelsAsJpeg(const APixels: TBytes; AWidth, AHeight,
  AQuality: Integer): TBytes;
var
  Image: TFPMemoryImage;
  Writer: TFPWriterJPEG;
  Stream: TMemoryStream;
begin
  Image := TFPMemoryImage.Create(AWidth, AHeight);
  Writer := TFPWriterJPEG.Create;
  Stream := TMemoryStream.Create;
  try
    PixelsToFpImage(APixels, AWidth, AHeight, Image);
    Writer.CompressionQuality := AQuality;
    Writer.ProgressiveEncoding := True;
    Writer.ImageWrite(Stream, Image);
    Result := StreamToBytes(Stream);
  finally
    Stream.Free;
    Writer.Free;
    Image.Free;
  end;
end;

function EncodePixelsAsPng(const APixels: TBytes; AWidth,
  AHeight: Integer): TBytes;
var
  Image: TFPMemoryImage;
  Writer: TFPWriterPNG;
  Stream: TMemoryStream;
begin
  Image := TFPMemoryImage.Create(AWidth, AHeight);
  Writer := TFPWriterPNG.Create;
  Stream := TMemoryStream.Create;
  try
    PixelsToFpImage(APixels, AWidth, AHeight, Image);
    Writer.WordSized := False;
    Writer.UseAlpha := False;
    Writer.CompressionLevel := clMax;
    Writer.ImageWrite(Stream, Image);
    Result := StreamToBytes(Stream);
  finally
    Stream.Free;
    Writer.Free;
    Image.Free;
  end;
end;

function ReadWindowHandle(AArguments: TJSONObject; const AFieldName: string): HWND;
var
  HandleData: TJSONData;
  HandleValue: QWord;
begin
  HandleData := AArguments.Find(AFieldName);
  if HandleData = nil then
    raise Exception.Create(AFieldName + ' is required');
  if not TryStrToQWord(HandleData.AsString, HandleValue) then
    raise Exception.Create(AFieldName + ' must be an unsigned integer string');
  Result := HWND(PtrUInt(HandleValue));
  if (Result = 0) or (not WinBool(IsWindow(Result))) then
    raise Exception.Create(AFieldName + ' does not identify a current Windows window');
end;

procedure MonitorRectForWindow(AWindow: HWND; out ARect: TRect);
var
  MonitorHandle: HANDLE;
  MonitorInfo: TMcpMonitorInfo;
begin
  MonitorHandle := McpMonitorFromWindow(AWindow, MCP_MONITOR_DEFAULTTONEAREST);
  if MonitorHandle = 0 then
    raise Exception.Create('Could not resolve monitor for window');
  FillChar(MonitorInfo, SizeOf(MonitorInfo), 0);
  MonitorInfo.cbSize := SizeOf(MonitorInfo);
  if not WinBool(McpGetMonitorInfoW(MonitorHandle, @MonitorInfo)) then
    RaiseLastOSError;
  ARect := MonitorInfo.rcMonitor;
end;

procedure PrimaryMonitorRect(out ARect: TRect);
var
  Origin: TPoint;
  MonitorHandle: HANDLE;
  MonitorInfo: TMcpMonitorInfo;
begin
  Origin.X := 0;
  Origin.Y := 0;
  MonitorHandle := McpMonitorFromPoint(Origin, MCP_MONITOR_DEFAULTTOPRIMARY);
  if MonitorHandle = 0 then
    raise Exception.Create('Could not resolve primary monitor');
  FillChar(MonitorInfo, SizeOf(MonitorInfo), 0);
  MonitorInfo.cbSize := SizeOf(MonitorInfo);
  if not WinBool(McpGetMonitorInfoW(MonitorHandle, @MonitorInfo)) then
    RaiseLastOSError;
  ARect := MonitorInfo.rcMonitor;
end;

procedure ResolveCaptureRectangle(AArguments: TJSONObject; out ATarget: string;
  out ASourceX, ASourceY, ASourceWidth, ASourceHeight: Integer;
  out AWindowHandle: QWord);
var
  TargetWindow: HWND;
  CaptureRect: TRect;
  HasRegionFields: Boolean;
begin
  AWindowHandle := 0;
  HasRegionFields := (AArguments.Find('x') <> nil) or
    (AArguments.Find('y') <> nil) or (AArguments.Find('width') <> nil) or
    (AArguments.Find('height') <> nil);
  ATarget := LowerCase(Trim(JsonString(AArguments, 'target', '')));
  if ATarget = '' then
  begin
    if HasRegionFields then
      ATarget := 'region'
    else
      ATarget := 'foreground_monitor';
  end;

  if ATarget = 'virtual_desktop' then
  begin
    ASourceX := GetSystemMetrics(SM_XVIRTUALSCREEN);
    ASourceY := GetSystemMetrics(SM_YVIRTUALSCREEN);
    ASourceWidth := GetSystemMetrics(SM_CXVIRTUALSCREEN);
    ASourceHeight := GetSystemMetrics(SM_CYVIRTUALSCREEN);
  end
  else if ATarget = 'primary_monitor' then
  begin
    PrimaryMonitorRect(CaptureRect);
    ASourceX := CaptureRect.Left;
    ASourceY := CaptureRect.Top;
    ASourceWidth := CaptureRect.Right - CaptureRect.Left;
    ASourceHeight := CaptureRect.Bottom - CaptureRect.Top;
  end
  else if ATarget = 'foreground_monitor' then
  begin
    TargetWindow := GetForegroundWindow;
    if TargetWindow = 0 then
      PrimaryMonitorRect(CaptureRect)
    else
      MonitorRectForWindow(TargetWindow, CaptureRect);
    ASourceX := CaptureRect.Left;
    ASourceY := CaptureRect.Top;
    ASourceWidth := CaptureRect.Right - CaptureRect.Left;
    ASourceHeight := CaptureRect.Bottom - CaptureRect.Top;
  end
  else if ATarget = 'foreground_window' then
  begin
    TargetWindow := GetForegroundWindow;
    if TargetWindow = 0 then
      raise Exception.Create('No foreground window is currently available');
    if not WinBool(GetWindowRect(TargetWindow, CaptureRect)) then
      RaiseLastOSError;
    AWindowHandle := QWord(PtrUInt(TargetWindow));
    ASourceX := CaptureRect.Left;
    ASourceY := CaptureRect.Top;
    ASourceWidth := CaptureRect.Right - CaptureRect.Left;
    ASourceHeight := CaptureRect.Bottom - CaptureRect.Top;
  end
  else if ATarget = 'window' then
  begin
    TargetWindow := ReadWindowHandle(AArguments, 'handle');
    if not WinBool(GetWindowRect(TargetWindow, CaptureRect)) then
      RaiseLastOSError;
    AWindowHandle := QWord(PtrUInt(TargetWindow));
    ASourceX := CaptureRect.Left;
    ASourceY := CaptureRect.Top;
    ASourceWidth := CaptureRect.Right - CaptureRect.Left;
    ASourceHeight := CaptureRect.Bottom - CaptureRect.Top;
  end
  else if ATarget = 'region' then
  begin
    ASourceX := JsonInteger(AArguments, 'x',
      GetSystemMetrics(SM_XVIRTUALSCREEN));
    ASourceY := JsonInteger(AArguments, 'y',
      GetSystemMetrics(SM_YVIRTUALSCREEN));
    if AArguments.Find('width') = nil then
      raise Exception.Create('width is required when target=region');
    if AArguments.Find('height') = nil then
      raise Exception.Create('height is required when target=region');
    ASourceWidth := JsonInteger(AArguments, 'width');
    ASourceHeight := JsonInteger(AArguments, 'height');
  end
  else
    raise Exception.Create(
      'target must be foreground_monitor, primary_monitor, foreground_window, window, region, or virtual_desktop');
end;


function TWindowsDesktopBackend.Capture(AArguments: TJSONObject;
  AMaximumImageBytes: Cardinal): TDesktopCaptureResult;
const
  DEFAULT_PNG_IMAGE_BYTES = 16 * 1024 * 1024;
  MIN_CAPTURE_DIMENSION = 320;
var
  Pixels, Encoded: TBytes;
  SourceX, SourceY, SourceWidth, SourceHeight: Integer;
  SourceWindowHandle: QWord;
  OutputWidth, OutputHeight, MaximumWidth, MaximumHeight: Integer;
  RequestedQuality, ActualQuality, Attempt: Integer;
  RequestedMaxBytes, TargetMaxBytes: Int64;
  Scale: Double;
  FormatName, TargetName, CaptureMethod: string;
  CaptureWindow: HWND;
begin
  Result.MimeType := '';
  SetLength(Result.Data, 0);
  Result.Width := 0;
  Result.Height := 0;
  Result.SourceX := 0;
  Result.SourceY := 0;
  Result.SourceWidth := 0;
  Result.SourceHeight := 0;
  Result.Quality := 0;
  Result.WindowHandle := 0;
  Result.WindowTitle := '';
  Result.CaptureMethod := '';
  CaptureMethod := 'screen';

  ResolveCaptureRectangle(AArguments, TargetName, SourceX, SourceY,
    SourceWidth, SourceHeight, SourceWindowHandle);
  FormatName := LowerCase(Trim(JsonString(AArguments, 'format', 'png')));
  if FormatName = 'jpg' then
    FormatName := 'jpeg';
  MaximumWidth := JsonInteger(AArguments, 'max_width', 7680);
  MaximumHeight := JsonInteger(AArguments, 'max_height', 4320);
  RequestedQuality := JsonInteger(AArguments, 'quality', 85);
  RequestedMaxBytes := JsonInteger(AArguments, 'max_bytes',
    DEFAULT_PNG_IMAGE_BYTES);

  if (SourceWidth < 1) or (SourceHeight < 1) then
    raise Exception.Create('capture width and height must be positive');
  if (MaximumWidth < 1) or (MaximumHeight < 1) then
    raise Exception.Create('max_width and max_height must be positive');
  if (FormatName <> 'png') and (FormatName <> 'jpeg') then
    raise Exception.Create('format must be png or jpeg');
  if (RequestedQuality < 40) or (RequestedQuality > 95) then
    raise Exception.Create('quality must be between 40 and 95');
  if RequestedMaxBytes < 32768 then
    raise Exception.Create('max_bytes must be at least 32768');

  TargetMaxBytes := RequestedMaxBytes;
  if (AMaximumImageBytes > 0) and (TargetMaxBytes > AMaximumImageBytes) then
    TargetMaxBytes := AMaximumImageBytes;
  if TargetMaxBytes < 32768 then
    raise Exception.Create('desktop.maximum_image_bytes is too small');

  OutputWidth := SourceWidth;
  OutputHeight := SourceHeight;
  if OutputWidth > MaximumWidth then
  begin
    Scale := MaximumWidth / OutputWidth;
    OutputWidth := MaximumWidth;
    OutputHeight := MaxInteger(1, Round(OutputHeight * Scale));
  end;
  if OutputHeight > MaximumHeight then
  begin
    Scale := MaximumHeight / OutputHeight;
    OutputHeight := MaximumHeight;
    OutputWidth := MaxInteger(1, Round(OutputWidth * Scale));
  end;

  ActualQuality := RequestedQuality;
  for Attempt := 1 to 8 do
  begin
    if SourceWindowHandle <> 0 then
    begin
      CaptureWindow := HWND(PtrUInt(SourceWindowHandle));
      CaptureWindowPixels(CaptureWindow, SourceX, SourceY, SourceWidth,
        SourceHeight, OutputWidth, OutputHeight, Pixels, CaptureMethod);
    end
    else
    begin
      CaptureScreenPixels(SourceX, SourceY, SourceWidth, SourceHeight,
        OutputWidth, OutputHeight, Pixels);
      CaptureMethod := 'screen';
    end;
    if FormatName = 'png' then
      Encoded := EncodePixelsAsPng(Pixels, OutputWidth, OutputHeight)
    else
      Encoded := EncodePixelsAsJpeg(Pixels, OutputWidth, OutputHeight,
        ActualQuality);
    if Length(Encoded) <= TargetMaxBytes then
      Break;

    if (FormatName = 'jpeg') and (ActualQuality > 65) then
      ActualQuality := MaxInteger(65, ActualQuality - 8)
    else
    begin
      Scale := Sqrt(TargetMaxBytes / Length(Encoded)) * 0.94;
      if Scale > 0.90 then
        Scale := 0.90;
      if (OutputWidth <= MIN_CAPTURE_DIMENSION) or
         (OutputHeight <= MIN_CAPTURE_DIMENSION) then
        Break;
      OutputWidth := MaxInteger(1, Integer(Floor(OutputWidth * Scale)));
      OutputHeight := MaxInteger(1, Integer(Floor(OutputHeight * Scale)));
    end;
  end;

  if Length(Encoded) > TargetMaxBytes then
    raise Exception.CreateFmt(
      'Could not encode screenshot below %d bytes; capture a smaller target/region or use jpeg',
      [TargetMaxBytes]);

  Result.Data := Encoded;
  if FormatName = 'png' then
  begin
    Result.MimeType := 'image/png';
    Result.Quality := 0;
  end
  else
  begin
    Result.MimeType := 'image/jpeg';
    Result.Quality := ActualQuality;
  end;
  Result.Width := OutputWidth;
  Result.Height := OutputHeight;
  Result.SourceX := SourceX;
  Result.SourceY := SourceY;
  Result.SourceWidth := SourceWidth;
  Result.SourceHeight := SourceHeight;
  Result.WindowHandle := SourceWindowHandle;
  if SourceWindowHandle <> 0 then
    Result.WindowTitle := WindowTitleUtf8(HWND(PtrUInt(SourceWindowHandle)));
  Result.CaptureMethod := CaptureMethod;
end;

function TWindowsDesktopBackend.KeyNameToVirtualKey(
  const AName: string): Word;
var
  Name: string;
  FunctionNumber: Integer;
begin
  Name := UpperCase(Trim(AName));
  if Length(Name) = 1 then
  begin
    if Name[1] in ['A'..'Z', '0'..'9'] then
      Exit(Ord(Name[1]));
  end;

  if (Length(Name) >= 2) and (Name[1] = 'F') and
    TryStrToInt(Copy(Name, 2, MaxInt), FunctionNumber) and
    (FunctionNumber >= 1) and (FunctionNumber <= 24) then
    Exit(VK_F1 + FunctionNumber - 1);

  if (Copy(Name, 1, 6) = 'NUMPAD') and
    TryStrToInt(Copy(Name, 7, MaxInt), FunctionNumber) and
    (FunctionNumber >= 0) and (FunctionNumber <= 9) then
    Exit(VK_NUMPAD0 + FunctionNumber);

  if (Name = '+') or (Name = 'PLUS') or (Name = 'ADD') or
     (Name = 'NUMPAD_ADD') or (Name = 'NUMPAD_PLUS') then Exit(VK_ADD);
  if (Name = '-') or (Name = 'MINUS') or (Name = 'SUBTRACT') or
     (Name = 'NUMPAD_SUBTRACT') or (Name = 'NUMPAD_MINUS') then Exit(VK_SUBTRACT);
  if (Name = '*') or (Name = 'MULTIPLY') or
     (Name = 'NUMPAD_MULTIPLY') or (Name = 'NUMPAD_STAR') then Exit(VK_MULTIPLY);
  if (Name = '/') or (Name = 'DIVIDE') or
     (Name = 'NUMPAD_DIVIDE') or (Name = 'NUMPAD_SLASH') then Exit(VK_DIVIDE);
  if (Name = '.') or (Name = 'DECIMAL') or
     (Name = 'NUMPAD_DECIMAL') then Exit(VK_DECIMAL);
  if (Name = '=') or (Name = 'EQUALS') or (Name = 'RESULT') then Exit(VK_RETURN);

  if (Name = 'CTRL') or (Name = 'CONTROL') then Exit(VK_CONTROL);
  if Name = 'SHIFT' then Exit(VK_SHIFT);
  if Name = 'ALT' then Exit(VK_MENU);
  if (Name = 'WIN') or (Name = 'WINDOWS') then Exit(VK_LWIN);
  if Name = 'ENTER' then Exit(VK_RETURN);
  if Name = 'TAB' then Exit(VK_TAB);
  if (Name = 'ESC') or (Name = 'ESCAPE') then Exit(VK_ESCAPE);
  if Name = 'SPACE' then Exit(VK_SPACE);
  if Name = 'BACKSPACE' then Exit(VK_BACK);
  if (Name = 'DELETE') or (Name = 'DEL') then Exit(VK_DELETE);
  if (Name = 'INSERT') or (Name = 'INS') then Exit(VK_INSERT);
  if Name = 'HOME' then Exit(VK_HOME);
  if Name = 'END' then Exit(VK_END);
  if (Name = 'PAGEUP') or (Name = 'PGUP') then Exit(VK_PRIOR);
  if (Name = 'PAGEDOWN') or (Name = 'PGDN') then Exit(VK_NEXT);
  if Name = 'LEFT' then Exit(VK_LEFT);
  if Name = 'RIGHT' then Exit(VK_RIGHT);
  if Name = 'UP' then Exit(VK_UP);
  if Name = 'DOWN' then Exit(VK_DOWN);
  if Name = 'CAPSLOCK' then Exit(VK_CAPITAL);

  raise Exception.CreateFmt('Unsupported key name: %s', [AName]);
end;

procedure TWindowsDesktopBackend.SendVirtualKey(AVirtualKey: Word;
  const AState: string);
var
  State: string;
begin
  State := LowerCase(Trim(AState));
  if (State = '') or (State = 'press') then
  begin
    keybd_event(Byte(AVirtualKey), 0, 0, 0);
    keybd_event(Byte(AVirtualKey), 0, KEYEVENTF_KEYUP, 0);
  end
  else if State = 'down' then
    keybd_event(Byte(AVirtualKey), 0, 0, 0)
  else if State = 'up' then
    keybd_event(Byte(AVirtualKey), 0, KEYEVENTF_KEYUP, 0)
  else
    raise Exception.Create('key state must be press, down, or up');
end;

procedure TWindowsDesktopBackend.PasteText(const AText: string);
var
  WideText: UnicodeString;
  MemoryHandle: HGLOBAL;
  Target: Pointer;
  ByteCount, Attempt: Integer;
  ClipboardOpened: Boolean;
begin
  WideText := UTF8Decode(AText);
  ByteCount := (Length(WideText) + 1) * SizeOf(WideChar);
  MemoryHandle := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, ByteCount);
  if MemoryHandle = 0 then
    RaiseLastOSError;
  Target := GlobalLock(MemoryHandle);
  if Target = nil then
  begin
    GlobalFree(MemoryHandle);
    RaiseLastOSError;
  end;
  try
    if Length(WideText) > 0 then
      Move(PWideChar(WideText)^, Target^, Length(WideText) * SizeOf(WideChar));
  finally
    GlobalUnlock(MemoryHandle);
  end;

  ClipboardOpened := False;
  for Attempt := 1 to 20 do
  begin
    if WinBool(OpenClipboard(0)) then
    begin
      ClipboardOpened := True;
      Break;
    end;
    Sleep(10);
  end;
  if not ClipboardOpened then
  begin
    GlobalFree(MemoryHandle);
    raise Exception.Create('Could not open the Windows clipboard');
  end;

  try
    if not WinBool(EmptyClipboard) then
      RaiseLastOSError;
    if SetClipboardData(CF_UNICODETEXT, MemoryHandle) = 0 then
      RaiseLastOSError;
    MemoryHandle := 0;
  finally
    CloseClipboard;
    if MemoryHandle <> 0 then
      GlobalFree(MemoryHandle);
  end;

  SendVirtualKey(VK_CONTROL, 'down');
  try
    SendVirtualKey(Ord('V'), 'press');
  finally
    SendVirtualKey(VK_CONTROL, 'up');
  end;
end;

function TWindowsDesktopBackend.SendInput(
  AArguments: TJSONObject): TJSONObject;
var
  Events: TJSONArray;
  EventObject: TJSONObject;
  EventType, State, ButtonName, ActivationStrategy: string;
  I, X, Y, Delta, DelayMs, RelativeX, RelativeY: Integer;
  DownFlag, UpFlag: DWord;
  Cursor: TPoint;
  WindowRect: TRect;
  WindowHandle, EffectiveWindow: HWND;
  LastMappedWindow: QWord;
  LastRelativeX, LastRelativeY, LastAbsoluteX, LastAbsoluteY: Integer;
  ActivateRequested, RequireForeground, ActivationVerified: Boolean;
begin
  LastMappedWindow := 0;
  LastRelativeX := -1;
  LastRelativeY := -1;
  LastAbsoluteX := 0;
  LastAbsoluteY := 0;
  ActivationVerified := False;
  ActivationStrategy := 'not_requested';
  Events := JsonArray(AArguments, 'events');
  if (Events = nil) or (Events.Count = 0) then
    raise Exception.Create('events must contain at least one input event');

  for I := 0 to Events.Count - 1 do
  begin
    if Events.Items[I].JSONType <> jtObject then
      raise Exception.CreateFmt('events[%d] must be an object', [I]);
    EventObject := TJSONObject(Events.Items[I]);
    EventType := LowerCase(Trim(JsonString(EventObject, 'type')));

    if EventType = 'key' then
      SendVirtualKey(KeyNameToVirtualKey(JsonString(EventObject, 'key')),
        JsonString(EventObject, 'state', 'press'))
    else if EventType = 'text' then
      PasteText(JsonString(EventObject, 'text'))
    else if EventType = 'mouse_move' then
    begin
      X := JsonInteger(EventObject, 'x');
      Y := JsonInteger(EventObject, 'y');
      if not WinBool(SetCursorPos(X, Y)) then
        RaiseLastOSError;
    end
    else if EventType = 'mouse_move_window' then
    begin
      WindowHandle := ReadWindowHandle(EventObject, 'handle');
      RelativeX := JsonInteger(EventObject, 'x');
      RelativeY := JsonInteger(EventObject, 'y');
      if (RelativeX < 0) or (RelativeX > 1000) or
         (RelativeY < 0) or (RelativeY > 1000) then
        raise Exception.Create('window-relative x and y must be between 0 and 1000');

      ActivateRequested := JsonBoolean(EventObject, 'activate', True);
      RequireForeground := JsonBoolean(EventObject, 'require_foreground', True);
      EffectiveWindow := ResolveActivatableWindow(WindowHandle);
      if WindowOwnsForeground(WindowHandle) then
        ActivationStrategy := 'already_foreground'
      else if not ActivateRequested then
        ActivationStrategy := 'activation_disabled';
      if ActivateRequested and (not WindowOwnsForeground(WindowHandle)) then
      begin
        RequestWindowActivation(WindowHandle, EffectiveWindow,
          ActivationStrategy);
        ActivationVerified := WaitForWindowAction(EffectiveWindow,
          'activate', 350);
      end
      else
        ActivationVerified := WindowOwnsForeground(WindowHandle);

      if RequireForeground and (not WindowOwnsForeground(WindowHandle)) then
        raise Exception.Create(
          'Target window could not be confirmed in the foreground. No mouse movement or click was sent, because it could land in an overlapping application. Activate a different handle or retry after the window becomes visible.');

      { The screenshot and normalized coordinate space refer to the original
        requested handle. Activation may resolve an owner/popup internally, but
        coordinate mapping must remain tied to the captured window rectangle. }
      if not WinBool(GetWindowRect(WindowHandle, WindowRect)) then
        RaiseLastOSError;
      if (WindowRect.Right <= WindowRect.Left) or
         (WindowRect.Bottom <= WindowRect.Top) then
        raise Exception.Create('target window has an empty rectangle');

      X := WindowRect.Left + Integer((Int64(RelativeX) *
        (WindowRect.Right - WindowRect.Left - 1) + 500) div 1000);
      Y := WindowRect.Top + Integer((Int64(RelativeY) *
        (WindowRect.Bottom - WindowRect.Top - 1) + 500) div 1000);
      if not WinBool(SetCursorPos(X, Y)) then
        RaiseLastOSError;
      LastMappedWindow := QWord(PtrUInt(WindowHandle));
      LastRelativeX := RelativeX;
      LastRelativeY := RelativeY;
      LastAbsoluteX := X;
      LastAbsoluteY := Y;
    end
    else if EventType = 'mouse_button' then
    begin
      ButtonName := LowerCase(Trim(JsonString(EventObject, 'button', 'left')));
      if ButtonName = 'left' then
      begin
        DownFlag := MOUSEEVENTF_LEFTDOWN;
        UpFlag := MOUSEEVENTF_LEFTUP;
      end
      else if ButtonName = 'right' then
      begin
        DownFlag := MOUSEEVENTF_RIGHTDOWN;
        UpFlag := MOUSEEVENTF_RIGHTUP;
      end
      else if ButtonName = 'middle' then
      begin
        DownFlag := MOUSEEVENTF_MIDDLEDOWN;
        UpFlag := MOUSEEVENTF_MIDDLEUP;
      end
      else
        raise Exception.Create('mouse button must be left, right, or middle');

      State := LowerCase(Trim(JsonString(EventObject, 'state', 'click')));
      if State = 'click' then
      begin
        mouse_event(DownFlag, 0, 0, 0, 0);
        mouse_event(UpFlag, 0, 0, 0, 0);
      end
      else if State = 'down' then
        mouse_event(DownFlag, 0, 0, 0, 0)
      else if State = 'up' then
        mouse_event(UpFlag, 0, 0, 0, 0)
      else
        raise Exception.Create('mouse button state must be click, down, or up');
    end
    else if EventType = 'mouse_wheel' then
    begin
      Delta := JsonInteger(EventObject, 'delta', WHEEL_DELTA_VALUE);
      mouse_event(MOUSEEVENTF_WHEEL, 0, 0, DWord(Delta), 0);
    end
    else if EventType = 'delay' then
    begin
      DelayMs := JsonInteger(EventObject, 'milliseconds', 0);
      if (DelayMs < 0) or (DelayMs > 60000) then
        raise Exception.Create('delay milliseconds must be between 0 and 60000');
      Sleep(DelayMs);
    end
    else
      raise Exception.CreateFmt('Unsupported input event type: %s', [EventType]);
  end;

  Result := TJSONObject.Create;
  Result.Add('processed_events', Events.Count);
  Result.Add('foreground_window', UIntToStr(QWord(PtrUInt(GetForegroundWindow))));
  if LastMappedWindow <> 0 then
  begin
    EventObject := TJSONObject.Create;
    EventObject.Add('handle', UIntToStr(LastMappedWindow));
    EventObject.Add('relative_x', LastRelativeX);
    EventObject.Add('relative_y', LastRelativeY);
    EventObject.Add('absolute_x', LastAbsoluteX);
    EventObject.Add('absolute_y', LastAbsoluteY);
    EventObject.Add('foreground_confirmed',
      WindowOwnsForeground(HWND(PtrUInt(LastMappedWindow))));
    EventObject.Add('activation_verified', ActivationVerified);
    EventObject.Add('activation_strategy', ActivationStrategy);
    Result.Add('window_relative_mapping', EventObject);
  end;
  if WinBool(GetCursorPos(Cursor)) then
  begin
    EventObject := TJSONObject.Create;
    EventObject.Add('x', Cursor.X);
    EventObject.Add('y', Cursor.Y);
    Result.Add('cursor', EventObject);
  end;
end;

end.
