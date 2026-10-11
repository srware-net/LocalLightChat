unit WindowsNativeControls;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

type
  TWindowsNativeControls = class
  public
    class function GetStatus: TJSONObject;
    class function IsNativeRef(const ARef: string): Boolean;
    class function ListElements(AArguments: TJSONObject): TJSONObject;
    class function PerformAction(AArguments: TJSONObject): TJSONObject;
  end;

implementation

uses
  Classes, Windows, McpJson;

const
  { Common-control message bases. }
  TV_FIRST = $1100;
  LVM_FIRST = $1000;

  TVM_EXPAND = TV_FIRST + 2;
  TVM_GETITEMRECT = TV_FIRST + 4;
  TVM_GETNEXTITEM = TV_FIRST + 10;
  TVM_SELECTITEM = TV_FIRST + 11;
  TVM_GETITEMW = TV_FIRST + 62;
  TVM_ENSUREVISIBLE = TV_FIRST + 20;

  TVGN_ROOT = $0000;
  TVGN_NEXT = $0001;
  TVGN_PARENT = $0003;
  TVGN_CHILD = $0004;
  TVGN_CARET = $0009;

  TVE_COLLAPSE = $0001;
  TVE_EXPAND = $0002;

  TVIF_TEXT = $0001;
  TVIF_STATE = $0008;
  TVIF_CHILDREN = $0040;
  TVIS_EXPANDED = $0020;

  LVM_GETITEMCOUNT = LVM_FIRST + 4;
  LVM_GETITEMRECT = LVM_FIRST + 14;
  LVM_ENSUREVISIBLE = LVM_FIRST + 19;
  LVM_SETITEMSTATE = LVM_FIRST + 43;
  LVM_GETITEMTEXTW = LVM_FIRST + 115;

  LVIR_BOUNDS = 0;
  LVIS_FOCUSED = $0001;
  LVIS_SELECTED = $0002;

  SMTO_NORMAL_VALUE = $0000;
  SMTO_BLOCK_VALUE = $0001;
  SMTO_ABORTIFHUNG_VALUE = $0002;
  NATIVE_MESSAGE_TIMEOUT_MS = 350;

  PROCESS_VM_OPERATION_VALUE = $0008;
  PROCESS_VM_READ_VALUE = $0010;
  PROCESS_VM_WRITE_VALUE = $0020;
  PROCESS_QUERY_INFORMATION_VALUE = $0400;
  MEM_COMMIT_VALUE = $1000;
  MEM_RESERVE_VALUE = $2000;
  MEM_RELEASE_VALUE = $8000;
  PAGE_READWRITE_VALUE = $04;

  MAX_NATIVE_ITEMS = 5000;
  TEXT_CAPACITY_CHARS = 1024;

type
  PNativeUIntValue = ^PtrUInt;
  PSizeUIntValue = ^SizeUInt;

  TNativeElementKind = (nekTreeItem, nekListItem);

  TNativeElement = record
    Kind: TNativeElementKind;
    ControlHandle: HWND;
    ItemValue: QWord; { HTREEITEM value or zero-based list index }
    Name: string;
    Path: string;
    ClassName: string;
    Depth: Integer;
    HasChildren: Boolean;
    Expanded: Boolean;
    HasBounds: Boolean;
    Bounds: TRect; { screen coordinates }
  end;

  TNativeElementArray = array of TNativeElement;

  TControlEnumContext = class
  public
    Handles: array of HWND;
    procedure Add(AHandle: HWND);
  end;

function McpSendMessageTimeoutW(AWindow: HWND; AMsg: UINT;
  AWParam: WPARAM; ALParam: LPARAM; AFlags, ATimeout: UINT;
  AResult: PNativeUIntValue): LRESULT; stdcall;
  external 'user32.dll' name 'SendMessageTimeoutW';

function McpReadProcessMemory(AProcess: THandle; ABaseAddress, ABuffer: Pointer;
  ASize: SizeUInt; ABytesRead: PSizeUIntValue): WINBOOL; stdcall;
  external 'kernel32.dll' name 'ReadProcessMemory';
function McpWriteProcessMemory(AProcess: THandle; ABaseAddress,
  ABuffer: Pointer; ASize: SizeUInt; ABytesWritten: PSizeUIntValue): WINBOOL; stdcall;
  external 'kernel32.dll' name 'WriteProcessMemory';
function McpVirtualAllocEx(AProcess: THandle; AAddress: Pointer;
  ASize: SizeUInt; AAllocationType, AProtect: DWORD): Pointer; stdcall;
  external 'kernel32.dll' name 'VirtualAllocEx';
function McpVirtualFreeEx(AProcess: THandle; AAddress: Pointer;
  ASize: SizeUInt; AFreeType: DWORD): WINBOOL; stdcall;
  external 'kernel32.dll' name 'VirtualFreeEx';
function McpIsWow64Process(AProcess: THandle; var AWow64: LongBool): WINBOOL; stdcall;
  external 'kernel32.dll' name 'IsWow64Process';

procedure TControlEnumContext.Add(AHandle: HWND);
var
  N: Integer;
begin
  N := Length(Handles);
  SetLength(Handles, N + 1);
  Handles[N] := AHandle;
end;

function WinBool(AValue: LongBool): Boolean; inline;
begin
  Result := Boolean(AValue);
end;

procedure ResetNativeElement(var AElement: TNativeElement);
begin
  AElement.Name := '';
  AElement.Path := '';
  AElement.ClassName := '';
  AElement.Kind := nekTreeItem;
  AElement.ControlHandle := 0;
  AElement.ItemValue := 0;
  AElement.Depth := 0;
  AElement.HasChildren := False;
  AElement.Expanded := False;
  AElement.HasBounds := False;
  FillChar(AElement.Bounds, SizeOf(AElement.Bounds), 0);
end;

function ReadWindowHandle(AArguments: TJSONObject): HWND;
var
  HandleText: string;
  HandleValue: QWord;
begin
  HandleText := Trim(JsonString(AArguments, 'handle', ''));
  if HandleText = '' then
    raise Exception.Create('handle is required');
  if not TryStrToQWord(HandleText, HandleValue) then
    raise Exception.Create('handle must be an unsigned integer string');
  Result := HWND(PtrUInt(HandleValue));
  if (Result = 0) or (not WinBool(IsWindow(Result))) then
    raise Exception.Create('handle does not identify a current Windows window');
end;

function GetClassNameUtf8(AWindow: HWND): string;
var
  Buffer: array[0..255] of WideChar;
  WideText: UnicodeString;
  N: Integer;
begin
  FillChar(Buffer, SizeOf(Buffer), 0);
  N := GetClassNameW(AWindow, @Buffer[0], Length(Buffer));
  if N <= 0 then
    Exit('');
  SetString(WideText, PWideChar(@Buffer[0]), N);
  Result := string(UTF8Encode(WideText));
end;

function EnumChildCallback(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  Context: TControlEnumContext;
begin
  Context := TControlEnumContext(Pointer(PtrUInt(AParam)));
  Context.Add(AWindow);
  Result := True;
end;

function SendBoundedMessage(AWindow: HWND; AMsg: UINT; AWParam: WPARAM;
  ALParam: LPARAM; out AResult: PtrUInt): Boolean;
var
  CallResult: LRESULT;
begin
  AResult := 0;
  SetLastError(0);
  CallResult := McpSendMessageTimeoutW(AWindow, AMsg, AWParam, ALParam,
    SMTO_BLOCK_VALUE or SMTO_ABORTIFHUNG_VALUE, NATIVE_MESSAGE_TIMEOUT_MS,
    @AResult);
  Result := CallResult <> 0;
end;

function QueryTargetPointerSize(AProcess: THandle): Integer;
var
  CurrentWow64, TargetWow64: LongBool;
begin
  CurrentWow64 := False;
  TargetWow64 := False;
  if not WinBool(McpIsWow64Process(GetCurrentProcess, CurrentWow64)) then
    CurrentWow64 := False;
  if not WinBool(McpIsWow64Process(AProcess, TargetWow64)) then
    TargetWow64 := False;

  if SizeOf(Pointer) = 8 then
  begin
    if WinBool(TargetWow64) then
      Result := 4
    else
      Result := 8;
    Exit;
  end;

  { A 32-bit server can safely automate 32-bit targets. On 64-bit Windows a
    native 64-bit target cannot be addressed by a 32-bit pointer-sized LPARAM. }
  if WinBool(CurrentWow64) and (not WinBool(TargetWow64)) then
    raise Exception.Create(
      'native common-control fallback cannot cross from a 32-bit MCP server into a 64-bit target; use a 64-bit server build');
  Result := 4;
end;

procedure PutUInt32(var AData: TBytes; AOffset: Integer; AValue: Cardinal);
begin
  if (AOffset < 0) or (AOffset + 4 > Length(AData)) then
    raise Exception.Create('internal native-control buffer overflow (uint32)');
  AData[AOffset] := Byte(AValue and $FF);
  AData[AOffset + 1] := Byte((AValue shr 8) and $FF);
  AData[AOffset + 2] := Byte((AValue shr 16) and $FF);
  AData[AOffset + 3] := Byte((AValue shr 24) and $FF);
end;

procedure PutUInt64(var AData: TBytes; AOffset: Integer; AValue: QWord);
var
  I: Integer;
begin
  if (AOffset < 0) or (AOffset + 8 > Length(AData)) then
    raise Exception.Create('internal native-control buffer overflow (uint64)');
  for I := 0 to 7 do
    AData[AOffset + I] := Byte((AValue shr (I * 8)) and $FF);
end;

procedure PutTargetPointer(var AData: TBytes; AOffset, APointerSize: Integer;
  AValue: QWord);
begin
  if APointerSize = 8 then
    PutUInt64(AData, AOffset, AValue)
  else
    PutUInt32(AData, AOffset, Cardinal(AValue));
end;

function GetUInt32(const AData: TBytes; AOffset: Integer): Cardinal;
begin
  if (AOffset < 0) or (AOffset + 4 > Length(AData)) then
    Exit(0);
  Result := Cardinal(AData[AOffset]) or
    (Cardinal(AData[AOffset + 1]) shl 8) or
    (Cardinal(AData[AOffset + 2]) shl 16) or
    (Cardinal(AData[AOffset + 3]) shl 24);
end;

function DecodeWideBuffer(const AData: TBytes): string;
var
  W: UnicodeString;
  CharCount, I: Integer;
begin
  CharCount := Length(AData) div 2;
  SetLength(W, CharCount);
  if CharCount > 0 then
    Move(AData[0], W[1], CharCount * SizeOf(WideChar));
  for I := 1 to Length(W) do
    if W[I] = #0 then
    begin
      SetLength(W, I - 1);
      Break;
    end;
  Result := string(UTF8Encode(W));
end;

function OpenControlProcess(AControl: HWND; out AProcess: THandle;
  out APointerSize: Integer): Boolean;
var
  ProcessId: DWORD;
begin
  Result := False;
  AProcess := 0;
  APointerSize := SizeOf(Pointer);
  ProcessId := 0;
  GetWindowThreadProcessId(AControl, @ProcessId);
  if ProcessId = 0 then
    Exit;
  AProcess := OpenProcess(PROCESS_VM_OPERATION_VALUE or PROCESS_VM_READ_VALUE or
    PROCESS_VM_WRITE_VALUE or PROCESS_QUERY_INFORMATION_VALUE, False, ProcessId);
  if AProcess = 0 then
    Exit;
  try
    APointerSize := QueryTargetPointerSize(AProcess);
    Result := True;
  except
    CloseHandle(AProcess);
    AProcess := 0;
    raise;
  end;
end;

function AllocRemote(AProcess: THandle; ASize: SizeUInt): Pointer;
begin
  Result := McpVirtualAllocEx(AProcess, nil, ASize,
    MEM_COMMIT_VALUE or MEM_RESERVE_VALUE, PAGE_READWRITE_VALUE);
  if Result = nil then
    RaiseLastOSError;
end;

procedure FreeRemote(AProcess: THandle; ARemote: Pointer);
begin
  if ARemote <> nil then
    McpVirtualFreeEx(AProcess, ARemote, 0, MEM_RELEASE_VALUE);
end;

procedure WriteRemote(AProcess: THandle; ARemote: Pointer;
  const AData: TBytes);
var
  Written: SizeUInt;
begin
  if Length(AData) = 0 then
    Exit;
  Written := 0;
  if (not WinBool(McpWriteProcessMemory(AProcess, ARemote, @AData[0], Length(AData), @Written))) or
     (Written <> SizeUInt(Length(AData))) then
    RaiseLastOSError;
end;

procedure ReadRemote(AProcess: THandle; ARemote: Pointer; var AData: TBytes);
var
  ReadCount: SizeUInt;
begin
  if Length(AData) = 0 then
    Exit;
  ReadCount := 0;
  if (not WinBool(McpReadProcessMemory(AProcess, ARemote, @AData[0], Length(AData), @ReadCount))) or
     (ReadCount <> SizeUInt(Length(AData))) then
    RaiseLastOSError;
end;

function TreeGetNextItem(AControl: HWND; ARelation: WPARAM;
  AItem: QWord): QWord;
var
  MessageResult: PtrUInt;
begin
  Result := 0;
  if SendBoundedMessage(AControl, TVM_GETNEXTITEM, ARelation,
    LPARAM(PtrUInt(AItem)), MessageResult) then
    Result := QWord(MessageResult);
end;

function TreeReadItem(AControl: HWND; AProcess: THandle; APointerSize: Integer;
  AItem: QWord; out AText: string; out AHasChildren, AExpanded: Boolean): Boolean;
var
  StructSize, TextOffset, TextPointerOffset, TextMaxOffset, StateOffset,
    ChildrenOffset: Integer;
  TotalSize, TextBytes: SizeUInt;
  RemoteBase: Pointer;
  Buffer, TextBuffer: TBytes;
  RemoteTextAddress: QWord;
  MessageResult: PtrUInt;
  StateValue, ChildrenValue: Cardinal;
begin
  Result := False;
  AText := '';
  AHasChildren := False;
  AExpanded := False;

  if APointerSize = 8 then
  begin
    StructSize := 56;
    TextPointerOffset := 24;
    TextMaxOffset := 32;
    StateOffset := 16;
    ChildrenOffset := 44;
  end
  else
  begin
    StructSize := 40;
    TextPointerOffset := 16;
    TextMaxOffset := 20;
    StateOffset := 8;
    ChildrenOffset := 32;
  end;
  TextOffset := StructSize;
  TextBytes := TEXT_CAPACITY_CHARS * SizeOf(WideChar);
  TotalSize := SizeUInt(StructSize) + TextBytes;
  RemoteBase := AllocRemote(AProcess, TotalSize);
  try
    SetLength(Buffer, TotalSize);
    FillChar(Buffer[0], Length(Buffer), 0);
    PutUInt32(Buffer, 0, TVIF_TEXT or TVIF_STATE or TVIF_CHILDREN);
    if APointerSize = 8 then
      PutTargetPointer(Buffer, 8, APointerSize, AItem)
    else
      PutTargetPointer(Buffer, 4, APointerSize, AItem);
    PutUInt32(Buffer, StateOffset + 4, TVIS_EXPANDED); { stateMask }
    RemoteTextAddress := QWord(PtrUInt(RemoteBase)) + QWord(TextOffset);
    PutTargetPointer(Buffer, TextPointerOffset, APointerSize, RemoteTextAddress);
    PutUInt32(Buffer, TextMaxOffset, TEXT_CAPACITY_CHARS);
    WriteRemote(AProcess, RemoteBase, Buffer);

    if not SendBoundedMessage(AControl, TVM_GETITEMW, 0,
      LPARAM(PtrUInt(RemoteBase)), MessageResult) then
      Exit;
    if MessageResult = 0 then
      Exit;

    SetLength(Buffer, StructSize);
    ReadRemote(AProcess, RemoteBase, Buffer);
    StateValue := GetUInt32(Buffer, StateOffset);
    ChildrenValue := GetUInt32(Buffer, ChildrenOffset);
    AExpanded := (StateValue and TVIS_EXPANDED) <> 0;
    AHasChildren := ChildrenValue <> 0;

    SetLength(TextBuffer, TextBytes);
    ReadRemote(AProcess, Pointer(PtrUInt(RemoteBase) + PtrUInt(TextOffset)),
      TextBuffer);
    AText := DecodeWideBuffer(TextBuffer);
    Result := True;
  finally
    FreeRemote(AProcess, RemoteBase);
  end;
end;

function TreeGetItemRect(AControl: HWND; AProcess: THandle;
  APointerSize: Integer; AItem: QWord; out ARect: TRect): Boolean;
var
  RemoteRect: Pointer;
  Buffer: TBytes;
  MessageResult: PtrUInt;
  P1, P2: TPoint;
begin
  Result := False;
  FillChar(ARect, SizeOf(ARect), 0);
  RemoteRect := AllocRemote(AProcess, SizeOf(TRect));
  try
    SetLength(Buffer, SizeOf(TRect));
    FillChar(Buffer[0], Length(Buffer), 0);
    PutTargetPointer(Buffer, 0, APointerSize, AItem);
    WriteRemote(AProcess, RemoteRect, Buffer);
    if not SendBoundedMessage(AControl, TVM_GETITEMRECT, 0,
      LPARAM(PtrUInt(RemoteRect)), MessageResult) then
      Exit;
    if MessageResult = 0 then
      Exit;
    ReadRemote(AProcess, RemoteRect, Buffer);
    Move(Buffer[0], ARect, SizeOf(TRect));

    P1.X := ARect.Left;
    P1.Y := ARect.Top;
    P2.X := ARect.Right;
    P2.Y := ARect.Bottom;
    if not ClientToScreen(AControl, P1) then
      Exit;
    if not ClientToScreen(AControl, P2) then
      Exit;
    ARect.Left := P1.X;
    ARect.Top := P1.Y;
    ARect.Right := P2.X;
    ARect.Bottom := P2.Y;
    Result := (ARect.Right > ARect.Left) and (ARect.Bottom > ARect.Top);
  finally
    FreeRemote(AProcess, RemoteRect);
  end;
end;

function ListReadItemText(AControl: HWND; AProcess: THandle;
  APointerSize, AIndex: Integer; out AText: string): Boolean;
var
  StructSize, TextPointerOffset, TextMaxOffset, TextOffset: Integer;
  TotalSize, TextBytes: SizeUInt;
  RemoteBase: Pointer;
  Buffer, TextBuffer: TBytes;
  RemoteTextAddress: QWord;
  MessageResult: PtrUInt;
begin
  Result := False;
  AText := '';
  if APointerSize = 8 then
  begin
    StructSize := 88;
    TextPointerOffset := 24;
    TextMaxOffset := 32;
  end
  else
  begin
    StructSize := 60;
    TextPointerOffset := 20;
    TextMaxOffset := 24;
  end;
  TextOffset := StructSize;
  TextBytes := TEXT_CAPACITY_CHARS * SizeOf(WideChar);
  TotalSize := SizeUInt(StructSize) + TextBytes;
  RemoteBase := AllocRemote(AProcess, TotalSize);
  try
    SetLength(Buffer, TotalSize);
    FillChar(Buffer[0], Length(Buffer), 0);
    PutUInt32(Buffer, 8, 0); { iSubItem }
    RemoteTextAddress := QWord(PtrUInt(RemoteBase)) + QWord(TextOffset);
    PutTargetPointer(Buffer, TextPointerOffset, APointerSize, RemoteTextAddress);
    PutUInt32(Buffer, TextMaxOffset, TEXT_CAPACITY_CHARS);
    WriteRemote(AProcess, RemoteBase, Buffer);
    if not SendBoundedMessage(AControl, LVM_GETITEMTEXTW, WPARAM(AIndex),
      LPARAM(PtrUInt(RemoteBase)), MessageResult) then
      Exit;

    SetLength(TextBuffer, TextBytes);
    ReadRemote(AProcess, Pointer(PtrUInt(RemoteBase) + PtrUInt(TextOffset)),
      TextBuffer);
    AText := DecodeWideBuffer(TextBuffer);
    Result := True;
  finally
    FreeRemote(AProcess, RemoteBase);
  end;
end;

function ListGetItemRect(AControl: HWND; AProcess: THandle;
  AIndex: Integer; out ARect: TRect): Boolean;
var
  RemoteRect: Pointer;
  Buffer: TBytes;
  MessageResult: PtrUInt;
  P1, P2: TPoint;
begin
  Result := False;
  FillChar(ARect, SizeOf(ARect), 0);
  RemoteRect := AllocRemote(AProcess, SizeOf(TRect));
  try
    SetLength(Buffer, SizeOf(TRect));
    FillChar(Buffer[0], Length(Buffer), 0);
    PutUInt32(Buffer, 0, LVIR_BOUNDS);
    WriteRemote(AProcess, RemoteRect, Buffer);
    if not SendBoundedMessage(AControl, LVM_GETITEMRECT, WPARAM(AIndex),
      LPARAM(PtrUInt(RemoteRect)), MessageResult) then
      Exit;
    if MessageResult = 0 then
      Exit;
    ReadRemote(AProcess, RemoteRect, Buffer);
    Move(Buffer[0], ARect, SizeOf(TRect));
    P1.X := ARect.Left;
    P1.Y := ARect.Top;
    P2.X := ARect.Right;
    P2.Y := ARect.Bottom;
    if not ClientToScreen(AControl, P1) then
      Exit;
    if not ClientToScreen(AControl, P2) then
      Exit;
    ARect.Left := P1.X;
    ARect.Top := P1.Y;
    ARect.Right := P2.X;
    ARect.Bottom := P2.Y;
    Result := (ARect.Right > ARect.Left) and (ARect.Bottom > ARect.Top);
  finally
    FreeRemote(AProcess, RemoteRect);
  end;
end;

function HashText(const AText: string): Cardinal;
var
  I: Integer;
begin
  Result := $811C9DC5;
  for I := 1 to Length(AText) do
  begin
    Result := Result xor Byte(AText[I]);
    Result := Result * 16777619;
  end;
end;

function BuildNativeRef(const AElement: TNativeElement): string;
var
  KindChar: Char;
begin
  if AElement.Kind = nekTreeItem then
    KindChar := 't'
  else
    KindChar := 'l';
  Result := 'n' + KindChar + ':' + UIntToStr(QWord(PtrUInt(AElement.ControlHandle))) +
    ':' + UIntToStr(AElement.ItemValue) + ':' + UIntToStr(HashText(AElement.Name));
end;

function ParseNativeRef(const ARef: string; out AKind: TNativeElementKind;
  out AControl: HWND; out AItemValue: QWord; out AHash: Cardinal): Boolean;
var
  Parts: TStringList;
  ControlValue, HashValue: QWord;
begin
  Result := False;
  AControl := 0;
  AItemValue := 0;
  AHash := 0;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ':';
    Parts.DelimitedText := ARef;
    if Parts.Count <> 4 then
      Exit;
    if Parts[0] = 'nt' then
      AKind := nekTreeItem
    else if Parts[0] = 'nl' then
      AKind := nekListItem
    else
      Exit;
    if not TryStrToQWord(Parts[1], ControlValue) then
      Exit;
    if not TryStrToQWord(Parts[2], AItemValue) then
      Exit;
    if not TryStrToQWord(Parts[3], HashValue) then
      Exit;
    if HashValue > High(Cardinal) then
      Exit;
    AControl := HWND(PtrUInt(ControlValue));
    AHash := Cardinal(HashValue);
    Result := (AControl <> 0) and WinBool(IsWindow(AControl));
  finally
    Parts.Free;
  end;
end;

procedure AppendElement(var AElements: TNativeElementArray;
  const AElement: TNativeElement);
var
  N: Integer;
begin
  N := Length(AElements);
  if N >= MAX_NATIVE_ITEMS then
    Exit;
  SetLength(AElements, N + 1);
  AElements[N] := AElement;
end;

procedure EnumerateTreeBranch(AControl: HWND; AProcess: THandle;
  APointerSize: Integer; AItem: QWord; const AParentPath: string;
  ADepth: Integer; var AElements: TNativeElementArray);
var
  Current, Child: QWord;
  E: TNativeElement;
  Text, CurrentPath: string;
begin
  Current := AItem;
  while (Current <> 0) and (Length(AElements) < MAX_NATIVE_ITEMS) do
  begin
    ResetNativeElement(E);
    Text := '';
    if TreeReadItem(AControl, AProcess, APointerSize, Current, Text,
      E.HasChildren, E.Expanded) then
    begin
      E.Kind := nekTreeItem;
      E.ControlHandle := AControl;
      E.ItemValue := Current;
      E.Name := Text;
      E.ClassName := 'SysTreeView32';
      E.Depth := ADepth;
      if AParentPath = '' then
        CurrentPath := Text
      else if Text = '' then
        CurrentPath := AParentPath
      else
        CurrentPath := AParentPath + ' > ' + Text;
      E.Path := CurrentPath;
      E.HasBounds := TreeGetItemRect(AControl, AProcess, APointerSize,
        Current, E.Bounds);
      AppendElement(AElements, E);

      Child := TreeGetNextItem(AControl, TVGN_CHILD, Current);
      if Child <> 0 then
        EnumerateTreeBranch(AControl, AProcess, APointerSize, Child,
          CurrentPath, ADepth + 1, AElements);
    end;
    Current := TreeGetNextItem(AControl, TVGN_NEXT, Current);
  end;
end;

procedure EnumerateTreeControl(AControl: HWND; var AElements: TNativeElementArray);
var
  ProcessHandle: THandle;
  PointerSize: Integer;
  RootItem: QWord;
begin
  ProcessHandle := 0;
  if not OpenControlProcess(AControl, ProcessHandle, PointerSize) then
    Exit;
  try
    RootItem := TreeGetNextItem(AControl, TVGN_ROOT, 0);
    if RootItem <> 0 then
      EnumerateTreeBranch(AControl, ProcessHandle, PointerSize, RootItem,
        '', 0, AElements);
  finally
    CloseHandle(ProcessHandle);
  end;
end;

procedure EnumerateListControl(AControl: HWND; var AElements: TNativeElementArray);
var
  ProcessHandle: THandle;
  PointerSize, Count, I: Integer;
  MessageResult: PtrUInt;
  E: TNativeElement;
  Text: string;
begin
  ProcessHandle := 0;
  if not OpenControlProcess(AControl, ProcessHandle, PointerSize) then
    Exit;
  try
    if not SendBoundedMessage(AControl, LVM_GETITEMCOUNT, 0, 0,
      MessageResult) then
      Exit;
    if MessageResult > MAX_NATIVE_ITEMS then
      Count := MAX_NATIVE_ITEMS
    else
      Count := Integer(MessageResult);
    for I := 0 to Count - 1 do
    begin
      if Length(AElements) >= MAX_NATIVE_ITEMS then
        Break;
      Text := '';
      if not ListReadItemText(AControl, ProcessHandle, PointerSize, I, Text) then
        Continue;
      ResetNativeElement(E);
      E.Kind := nekListItem;
      E.ControlHandle := AControl;
      E.ItemValue := QWord(I);
      E.Name := Text;
      E.Path := Text;
      E.ClassName := 'SysListView32';
      E.Depth := 0;
      E.HasBounds := ListGetItemRect(AControl, ProcessHandle, I, E.Bounds);
      AppendElement(AElements, E);
    end;
  finally
    CloseHandle(ProcessHandle);
  end;
end;

procedure EnumerateNativeElements(ARootWindow: HWND;
  out AElements: TNativeElementArray; out AControlsScanned: Integer);
var
  Context: TControlEnumContext;
  I: Integer;
  ClassName: string;
begin
  SetLength(AElements, 0);
  AControlsScanned := 0;
  Context := TControlEnumContext.Create;
  try
    if not EnumChildWindows(ARootWindow, @EnumChildCallback,
      LPARAM(PtrInt(Context))) then
    begin
      { EnumChildWindows returns zero when there are no child windows as well as
        on failure. GetLastError is not useful enough here to turn that into an
        exception. }
    end;
    for I := 0 to High(Context.Handles) do
    begin
      ClassName := GetClassNameUtf8(Context.Handles[I]);
      if SameText(ClassName, 'SysTreeView32') then
      begin
        Inc(AControlsScanned);
        EnumerateTreeControl(Context.Handles[I], AElements);
      end
      else if SameText(ClassName, 'SysListView32') then
      begin
        Inc(AControlsScanned);
        EnumerateListControl(Context.Handles[I], AElements);
      end;
    end;
  finally
    Context.Free;
  end;
end;

function TextMatches(const AActual, AExpected, AMatchMode: string): Boolean;
var
  ActualText, ExpectedText: string;
begin
  if Trim(AExpected) = '' then
    Exit(True);
  ActualText := LowerCase(Trim(AActual));
  ExpectedText := LowerCase(Trim(AExpected));
  if AMatchMode = 'contains' then
    Result := Pos(ExpectedText, ActualText) > 0
  else
    Result := ActualText = ExpectedText;
end;

function NativeControlType(const AElement: TNativeElement): string;
begin
  if AElement.Kind = nekTreeItem then
    Result := 'tree_item'
  else
    Result := 'list_item';
end;

function ElementMatches(const AElement: TNativeElement; const AName,
  AControlType, AQuery, AMatchMode: string): Boolean;
var
  QueryText, SearchText: string;
begin
  Result := TextMatches(AElement.Name, AName, AMatchMode) and
    TextMatches(NativeControlType(AElement), AControlType, AMatchMode);
  if not Result then
    Exit;
  QueryText := LowerCase(Trim(AQuery));
  if QueryText = '' then
    Exit(True);
  SearchText := LowerCase(AElement.Name + #10 + AElement.Path + #10 +
    NativeControlType(AElement) + #10 + AElement.ClassName);
  Result := Pos(QueryText, SearchText) > 0;
end;

function ElementToJson(const AElement: TNativeElement; ASourceIndex: Integer;
  ADetails: Boolean): TJSONObject;
var
  Bounds: TJSONObject;
  Actions: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.Add('ref', BuildNativeRef(AElement));
  Result.Add('source_index', ASourceIndex);
  Result.Add('view', 'native');
  Result.Add('source', 'win32_common_control');
  Result.Add('name', AElement.Name);
  Result.Add('path', AElement.Path);
  Result.Add('automation_id', '');
  Result.Add('control_type', NativeControlType(AElement));
  Result.Add('enabled', WinBool(IsWindowEnabled(AElement.ControlHandle)));
  Result.Add('offscreen', not AElement.HasBounds);
  if AElement.HasBounds then
  begin
    Bounds := TJSONObject.Create;
    Bounds.Add('x', AElement.Bounds.Left);
    Bounds.Add('y', AElement.Bounds.Top);
    Bounds.Add('width', AElement.Bounds.Right - AElement.Bounds.Left);
    Bounds.Add('height', AElement.Bounds.Bottom - AElement.Bounds.Top);
    Result.Add('bounds', Bounds);
  end;
  if AElement.Kind = nekTreeItem then
  begin
    Result.Add('has_children', AElement.HasChildren);
    Result.Add('expanded', AElement.Expanded);
    Result.Add('depth', AElement.Depth);
  end;
  if ADetails then
  begin
    Result.Add('class_name', AElement.ClassName);
    Result.Add('control_handle', UIntToStr(QWord(PtrUInt(AElement.ControlHandle))));
    Result.Add('native_item', UIntToStr(AElement.ItemValue));
  end;
  Actions := TJSONArray.Create;
  Actions.Add('activate');
  Actions.Add('select');
  if AElement.Kind = nekTreeItem then
  begin
    Actions.Add('scroll_into_view');
    if AElement.HasChildren then
    begin
      if AElement.Expanded then
        Actions.Add('collapse')
      else
        Actions.Add('expand');
    end;
  end;
  Result.Add('actions', Actions);
end;

function FindNativeMatch(const AElements: TNativeElementArray;
  const AName, AControlType, AQuery, AMatchMode: string; AMatchIndex: Integer;
  out AElement: TNativeElement; out ASourceIndex: Integer): Boolean;
var
  I, CurrentMatch: Integer;
begin
  Result := False;
  ASourceIndex := -1;
  CurrentMatch := 0;
  for I := 0 to High(AElements) do
    if ElementMatches(AElements[I], AName, AControlType, AQuery,
      AMatchMode) then
    begin
      if CurrentMatch = AMatchIndex then
      begin
        AElement := AElements[I];
        ASourceIndex := I;
        Exit(True);
      end;
      Inc(CurrentMatch);
    end;
end;

function ResolveNativeRef(ARootWindow: HWND; const ARef: string;
  out AElement: TNativeElement): Boolean;
var
  Kind: TNativeElementKind;
  Control: HWND;
  ItemValue: QWord;
  ExpectedHash: Cardinal;
  ProcessHandle: THandle;
  PointerSize: Integer;
  Text: string;
  MessageResult: PtrUInt;
  Count: Integer;
begin
  Result := False;
  ResetNativeElement(AElement);
  if not ParseNativeRef(ARef, Kind, Control, ItemValue, ExpectedHash) then
    raise Exception.Create('native ref is invalid or stale');
  if (Control <> ARootWindow) and (not WinBool(IsChild(ARootWindow, Control))) then
    raise Exception.Create('native ref does not belong to the requested window');

  ProcessHandle := 0;
  if not OpenControlProcess(Control, ProcessHandle, PointerSize) then
    raise Exception.Create('could not open the target process for native ref validation');
  try
    Text := '';
    if Kind = nekTreeItem then
    begin
      AElement.Kind := nekTreeItem;
      AElement.ControlHandle := Control;
      AElement.ItemValue := ItemValue;
      AElement.ClassName := 'SysTreeView32';
      if not TreeReadItem(Control, ProcessHandle, PointerSize, ItemValue, Text,
        AElement.HasChildren, AElement.Expanded) then
        raise Exception.Create('native tree ref is stale; list elements again');
      AElement.HasBounds := TreeGetItemRect(Control, ProcessHandle, PointerSize,
        ItemValue, AElement.Bounds);
    end
    else
    begin
      if not SendBoundedMessage(Control, LVM_GETITEMCOUNT, 0, 0,
        MessageResult) then
        raise Exception.Create('native list ref validation timed out');
      Count := Integer(MessageResult);
      if (ItemValue >= QWord(Count)) then
        raise Exception.Create('native list ref is stale; list elements again');
      AElement.Kind := nekListItem;
      AElement.ControlHandle := Control;
      AElement.ItemValue := ItemValue;
      AElement.ClassName := 'SysListView32';
      if not ListReadItemText(Control, ProcessHandle, PointerSize,
        Integer(ItemValue), Text) then
        raise Exception.Create('native list ref is stale; list elements again');
      AElement.HasBounds := ListGetItemRect(Control, ProcessHandle,
        Integer(ItemValue), AElement.Bounds);
    end;
    AElement.Name := Text;
    AElement.Path := Text;
    if HashText(AElement.Name) <> ExpectedHash then
      raise Exception.Create('native ref is stale because the item text changed; list elements again');
    Result := True;
  finally
    CloseHandle(ProcessHandle);
  end;
end;

procedure SelectTreeItem(const AElement: TNativeElement;
  const AAction: string; out AResolvedAction: string);
var
  MessageResult: PtrUInt;
  ExpandFlag: WPARAM;
begin
  if (AAction = 'expand') or (AAction = 'collapse') then
  begin
    if not SendBoundedMessage(AElement.ControlHandle, TVM_ENSUREVISIBLE, 0,
      LPARAM(PtrUInt(AElement.ItemValue)), MessageResult) then
      raise Exception.Create('native tree ensure-visible timed out');
  end;

  if AAction = 'expand' then
  begin
    ExpandFlag := TVE_EXPAND;
    if (not SendBoundedMessage(AElement.ControlHandle, TVM_EXPAND, ExpandFlag,
      LPARAM(PtrUInt(AElement.ItemValue)), MessageResult)) or
      (MessageResult = 0) then
      raise Exception.Create('native tree expand failed or timed out');
    AResolvedAction := 'native_tree_expand';
    Exit;
  end;
  if AAction = 'collapse' then
  begin
    ExpandFlag := TVE_COLLAPSE;
    if (not SendBoundedMessage(AElement.ControlHandle, TVM_EXPAND, ExpandFlag,
      LPARAM(PtrUInt(AElement.ItemValue)), MessageResult)) or
      (MessageResult = 0) then
      raise Exception.Create('native tree collapse failed or timed out');
    AResolvedAction := 'native_tree_collapse';
    Exit;
  end;

  if (not SendBoundedMessage(AElement.ControlHandle, TVM_ENSUREVISIBLE, 0,
    LPARAM(PtrUInt(AElement.ItemValue)), MessageResult)) then
    raise Exception.Create('native tree ensure-visible timed out');
  if AAction = 'scroll_into_view' then
  begin
    AResolvedAction := 'native_tree_ensure_visible';
    Exit;
  end;

  if (not SendBoundedMessage(AElement.ControlHandle, TVM_SELECTITEM,
    TVGN_CARET, LPARAM(PtrUInt(AElement.ItemValue)), MessageResult)) or
    (MessageResult = 0) then
    raise Exception.Create('native tree selection failed or timed out');
  AResolvedAction := 'native_tree_select';
end;

procedure SelectListItem(const AElement: TNativeElement;
  out AResolvedAction: string);
var
  ProcessHandle: THandle;
  PointerSize, StructSize: Integer;
  RemoteItem: Pointer;
  Buffer: TBytes;
  MessageResult: PtrUInt;
begin
  ProcessHandle := 0;
  if not OpenControlProcess(AElement.ControlHandle, ProcessHandle, PointerSize) then
    raise Exception.Create('could not open target list-view process');
  try
    if PointerSize = 8 then
      StructSize := 88
    else
      StructSize := 60;
    RemoteItem := AllocRemote(ProcessHandle, StructSize);
    try
      SetLength(Buffer, StructSize);
      FillChar(Buffer[0], Length(Buffer), 0);
      PutUInt32(Buffer, 12, LVIS_FOCUSED or LVIS_SELECTED); { state }
      PutUInt32(Buffer, 16, LVIS_FOCUSED or LVIS_SELECTED); { stateMask }
      WriteRemote(ProcessHandle, RemoteItem, Buffer);
      if (not SendBoundedMessage(AElement.ControlHandle, LVM_ENSUREVISIBLE,
        WPARAM(AElement.ItemValue), 0, MessageResult)) then
        raise Exception.Create('native list ensure-visible timed out');
      if (not SendBoundedMessage(AElement.ControlHandle, LVM_SETITEMSTATE,
        WPARAM(AElement.ItemValue), LPARAM(PtrUInt(RemoteItem)), MessageResult)) or
        (MessageResult = 0) then
        raise Exception.Create('native list selection failed or timed out');
    finally
      FreeRemote(ProcessHandle, RemoteItem);
    end;
  finally
    CloseHandle(ProcessHandle);
  end;
  AResolvedAction := 'native_list_select';
end;

class function TWindowsNativeControls.GetStatus: TJSONObject;
var
  Adapters: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.Add('available', True);
  Result.Add('backend', 'win32_common_controls');
  Result.Add('coordinate_guessing', False);
  Result.Add('cross_process_item_enumeration', True);
  Adapters := TJSONArray.Create;
  Adapters.Add('SysTreeView32');
  Adapters.Add('SysListView32');
  Result.Add('adapters', Adapters);
end;

class function TWindowsNativeControls.IsNativeRef(const ARef: string): Boolean;
begin
  Result := (Copy(ARef, 1, 3) = 'nt:') or (Copy(ARef, 1, 3) = 'nl:');
end;

class function TWindowsNativeControls.ListElements(
  AArguments: TJSONObject): TJSONObject;
var
  WindowHandle: HWND;
  Elements: TNativeElementArray;
  Items: TJSONArray;
  QueryText, NameText, AutomationIdText, ControlTypeText, MatchMode: string;
  LimitValue, ControlsScanned, Matched, I, ReturnedCount: Integer;
  Details, IncludeOffscreen: Boolean;
begin
  WindowHandle := ReadWindowHandle(AArguments);
  QueryText := JsonString(AArguments, 'query', '');
  NameText := JsonString(AArguments, 'name', '');
  AutomationIdText := Trim(JsonString(AArguments, 'automation_id', ''));
  if AutomationIdText <> '' then
  begin
    Result := TJSONObject.Create;
    Result.Add('elements', TJSONArray.Create);
    Result.Add('count', 0);
    Result.Add('matched', 0);
    Result.Add('scanned', 0);
    Result.Add('controls_scanned', 0);
    Result.Add('limit', JsonInteger(AArguments, 'limit', 100));
    Result.Add('requested_view', 'native');
    Result.Add('view_used', 'native');
    Result.Add('native_fallback', True);
    Result.Add('reason', 'native common-control items do not have UI Automation AutomationIds');
    Exit;
  end;
  ControlTypeText := JsonString(AArguments, 'control_type', '');
  MatchMode := LowerCase(Trim(JsonString(AArguments, 'match_mode', 'contains')));
  if (MatchMode <> 'exact') and (MatchMode <> 'contains') then
    raise Exception.Create('match_mode must be exact or contains');
  LimitValue := JsonInteger(AArguments, 'limit', 100);
  if (LimitValue < 1) or (LimitValue > 500) then
    raise Exception.Create('limit must be between 1 and 500');
  Details := JsonBoolean(AArguments, 'details', False);
  IncludeOffscreen := JsonBoolean(AArguments, 'include_offscreen', False);

  EnumerateNativeElements(WindowHandle, Elements, ControlsScanned);
  Items := TJSONArray.Create;
  try
    Matched := 0;
    for I := 0 to High(Elements) do
    begin
      { Tree descendants are intentionally retained even while collapsed:
        TVM_ENSUREVISIBLE can expand their parents deterministically during an
        action. For very large list views, keep the old visible-only default
        when the caller supplied no selector. }
      if (not IncludeOffscreen) and (not Elements[I].HasBounds) and
         (Elements[I].Kind = nekListItem) and
         (Trim(QueryText) = '') and (Trim(NameText) = '') then
        Continue;
      if not ElementMatches(Elements[I], NameText, ControlTypeText, QueryText,
        MatchMode) then
        Continue;
      Inc(Matched);
      if Items.Count < LimitValue then
        Items.Add(ElementToJson(Elements[I], I, Details));
    end;

    ReturnedCount := Items.Count;
    Result := TJSONObject.Create;
    Result.Add('elements', Items);
    Items := nil;
    Result.Add('count', ReturnedCount);
    Result.Add('matched', Matched);
    Result.Add('scanned', Length(Elements));
    Result.Add('controls_scanned', ControlsScanned);
    Result.Add('limit', LimitValue);
    Result.Add('details', Details);
    Result.Add('requested_view', 'native');
    Result.Add('view_used', 'native');
    Result.Add('native_fallback', True);
    Result.Add('truncated', Matched > LimitValue);
    Result.Add('selector_advice',
      'These are exact Win32 common-control items, not guessed screenshot regions. Use the returned ref immediately with desktop_ui_action.');
    Result.Add('coordinate_advice',
      'No model coordinates are required. Tree/list selection is performed with native control messages using the item handle/index.');
  finally
    Items.Free;
  end;
end;

class function TWindowsNativeControls.PerformAction(
  AArguments: TJSONObject): TJSONObject;
var
  WindowHandle: HWND;
  Elements: TNativeElementArray;
  Element: TNativeElement;
  ElementRef, ActionName, ResolvedAction, QueryText, NameText,
    ControlTypeText, MatchMode: string;
  MatchIndex, SourceIndex, ControlsScanned: Integer;
  Found, UsedRef: Boolean;
begin
  WindowHandle := ReadWindowHandle(AArguments);
  ElementRef := Trim(JsonString(AArguments, 'ref', ''));
  ActionName := LowerCase(Trim(JsonString(AArguments, 'action', 'activate')));
  if (ActionName <> 'activate') and (ActionName <> 'select') and
     (ActionName <> 'expand') and (ActionName <> 'collapse') and
     (ActionName <> 'scroll_into_view') then
    raise Exception.Create(
      'native common-control action must be activate, select, expand, collapse, or scroll_into_view');

  UsedRef := ElementRef <> '';
  SourceIndex := -1;
  if UsedRef then
    Found := ResolveNativeRef(WindowHandle, ElementRef, Element)
  else
  begin
    QueryText := JsonString(AArguments, 'query', '');
    NameText := JsonString(AArguments, 'name', '');
    ControlTypeText := JsonString(AArguments, 'control_type', '');
    if (Trim(QueryText) = '') and (Trim(NameText) = '') and
       (Trim(ControlTypeText) = '') then
      raise Exception.Create('native action requires ref, name, control_type, or query');
    MatchMode := LowerCase(Trim(JsonString(AArguments, 'match_mode', 'exact')));
    if (MatchMode <> 'exact') and (MatchMode <> 'contains') then
      raise Exception.Create('match_mode must be exact or contains');
    MatchIndex := JsonInteger(AArguments, 'match_index', 0);
    if MatchIndex < 0 then
      raise Exception.Create('match_index must be zero or positive');
    EnumerateNativeElements(WindowHandle, Elements, ControlsScanned);
    Found := FindNativeMatch(Elements, NameText, ControlTypeText, QueryText,
      MatchMode, MatchIndex, Element, SourceIndex);
  end;
  if not Found then
    raise Exception.Create('No native Win32 tree/list item matched the selector');
  if not WinBool(IsWindowEnabled(Element.ControlHandle)) then
    raise Exception.Create('The matched native control is disabled');

  if Element.Kind = nekTreeItem then
  begin
    if (ActionName = 'activate') or (ActionName = 'select') or
       (ActionName = 'expand') or (ActionName = 'collapse') or
       (ActionName = 'scroll_into_view') then
      SelectTreeItem(Element, ActionName, ResolvedAction);
  end
  else
  begin
    if (ActionName = 'expand') or (ActionName = 'collapse') or
       (ActionName = 'scroll_into_view') then
      raise Exception.Create('list items do not support expand/collapse/scroll_into_view through this adapter');
    SelectListItem(Element, ResolvedAction);
  end;

  Result := TJSONObject.Create;
  Result.Add('success', True);
  Result.Add('action', ActionName);
  Result.Add('resolved_action', ResolvedAction);
  Result.Add('used_ref', UsedRef);
  Result.Add('view_used', 'native');
  Result.Add('element', ElementToJson(Element, SourceIndex, False));
  Result.Add('physical_click', False);
  Result.Add('verification',
    'The target was resolved as an actual SysTreeView32/SysListView32 item and acted on with native common-control messages. No screenshot coordinates and no mouse click were used.');
end;

end.
