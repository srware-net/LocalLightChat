unit TerminalPtyWindows;

{$mode objfpc}{$H+}

interface

{$IFNDEF WINDOWS}
  {$ERROR TerminalPtyWindows is Windows-only}
{$ENDIF}

uses
  Classes, SysUtils, Windows, TerminalPtyBackend;

type
  TWindowsTerminalPtyBackend = class(TTerminalPtyBackend)
  private
    FKernel32: HMODULE;
    FConPty: THandle;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FConPtyInputRead: THandle;
    FConPtyOutputWrite: THandle;
    FProcessHandle: THandle;
    FTerminationGraceMs: Cardinal;
    procedure LoadConPtyApi;
    procedure CloseHandleIfOpen(var AHandle: THandle);
    function ErrorText(const APrefix: string): string;
  public
    constructor Create(ATerminationGraceMs: Cardinal); reintroduce;
    destructor Destroy; override;
    procedure Start(const AExecutable: string; AArguments: TStrings;
      const AWorkingDirectory: string; AColumns, ARows: Word); override;
    function ReadAvailable(out AData: RawByteString;
      AMaximumBytes: Cardinal): Integer; override;
    function WriteData(const AData: RawByteString): Integer; override;
    procedure Resize(AColumns, ARows: Word); override;
    procedure SendSignal(ASignal: TTerminalSignal); override;
    function PollRunning: Boolean; override;
    procedure Close; override;
  end;

implementation

type
  PSizeUInt = ^SizeUInt;

  TStartupInfoExWLocal = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: Pointer;
  end;

  TCreatePseudoConsoleFunc = function(Size: TCoord; hInput, hOutput: THandle;
    dwFlags: DWORD; out phPC: THandle): HRESULT; stdcall;
  TResizePseudoConsoleFunc = function(hPC: THandle; Size: TCoord): HRESULT; stdcall;
  TClosePseudoConsoleProc = procedure(hPC: THandle); stdcall;
  TInitializeProcThreadAttributeListFunc = function(lpAttributeList: Pointer;
    dwAttributeCount, dwFlags: DWORD; var lpSize: SizeUInt): BOOL; stdcall;
  TUpdateProcThreadAttributeFunc = function(lpAttributeList: Pointer;
    dwFlags: DWORD; Attribute: PtrUInt; lpValue: Pointer; cbSize: SizeUInt;
    lpPreviousValue: Pointer; lpReturnSize: PSizeUInt): BOOL; stdcall;
  TDeleteProcThreadAttributeListProc = procedure(lpAttributeList: Pointer); stdcall;

const
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = PtrUInt($00020016);
  EXTENDED_STARTUPINFO_PRESENT_LOCAL = DWORD($00080000);
  STILL_ACTIVE_LOCAL = DWORD(259);
  ERROR_BROKEN_PIPE_LOCAL = DWORD(109);

var
  GConPtyApiLock: TRTLCriticalSection;
  GCreatePseudoConsole: TCreatePseudoConsoleFunc = nil;
  GResizePseudoConsole: TResizePseudoConsoleFunc = nil;
  GClosePseudoConsole: TClosePseudoConsoleProc = nil;
  GInitializeProcThreadAttributeList: TInitializeProcThreadAttributeListFunc = nil;
  GUpdateProcThreadAttribute: TUpdateProcThreadAttributeFunc = nil;
  GDeleteProcThreadAttributeList: TDeleteProcThreadAttributeListProc = nil;

function QuoteWindowsArgument(const AValue: string): string;
var
  I, Backslashes: Integer;
  NeedsQuotes: Boolean;
begin
  if AValue = '' then
    Exit('""');

  NeedsQuotes := False;
  for I := 1 to Length(AValue) do
    if AValue[I] in [' ', #9, '"'] then
    begin
      NeedsQuotes := True;
      Break;
    end;
  if not NeedsQuotes then
    Exit(AValue);

  Result := '"';
  Backslashes := 0;
  for I := 1 to Length(AValue) do
  begin
    if AValue[I] = '\' then
    begin
      Inc(Backslashes);
      Continue;
    end;

    if AValue[I] = '"' then
    begin
      Result := Result + StringOfChar('\', Backslashes * 2 + 1) + '"';
      Backslashes := 0;
      Continue;
    end;

    if Backslashes > 0 then
    begin
      Result := Result + StringOfChar('\', Backslashes);
      Backslashes := 0;
    end;
    Result := Result + AValue[I];
  end;

  if Backslashes > 0 then
    Result := Result + StringOfChar('\', Backslashes * 2);
  Result := Result + '"';
end;

function BuildWindowsCommandLine(const AExecutable: string;
  AArguments: TStrings): string;
var
  I: Integer;
begin
  Result := QuoteWindowsArgument(AExecutable);
  if AArguments <> nil then
    for I := 0 to AArguments.Count - 1 do
      Result := Result + ' ' + QuoteWindowsArgument(AArguments[I]);
end;

constructor TWindowsTerminalPtyBackend.Create(ATerminationGraceMs: Cardinal);
begin
  inherited Create;
  FKernel32 := 0;
  FConPty := 0;
  FInputWrite := 0;
  FOutputRead := 0;
  FConPtyInputRead := 0;
  FConPtyOutputWrite := 0;
  FProcessHandle := 0;
  FTerminationGraceMs := ATerminationGraceMs;
end;

destructor TWindowsTerminalPtyBackend.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TWindowsTerminalPtyBackend.LoadConPtyApi;
var
  LocalCreate: TCreatePseudoConsoleFunc;
  LocalResize: TResizePseudoConsoleFunc;
  LocalClose: TClosePseudoConsoleProc;
  LocalInitAttributes: TInitializeProcThreadAttributeListFunc;
  LocalUpdateAttributes: TUpdateProcThreadAttributeFunc;
  LocalDeleteAttributes: TDeleteProcThreadAttributeListProc;

  function RequireProc(const AName: PChar): Pointer;
  begin
    Result := GetProcAddress(FKernel32, AName);
    if Result = nil then
      raise Exception.CreateFmt(
        'Windows ConPTY API %s is unavailable; Windows 10 1809 or newer is required',
        [string(AName)]);
  end;

begin
  EnterCriticalSection(GConPtyApiLock);
  try
    if Assigned(GCreatePseudoConsole) and Assigned(GResizePseudoConsole) and
      Assigned(GClosePseudoConsole) and
      Assigned(GInitializeProcThreadAttributeList) and
      Assigned(GUpdateProcThreadAttribute) and
      Assigned(GDeleteProcThreadAttributeList) then
      Exit;

    FKernel32 := GetModuleHandle(PChar('kernel32.dll'));
    if FKernel32 = 0 then
      raise Exception.Create('Unable to access kernel32.dll');

    { Resolve everything into local variables first. A failed lookup must not
      leave a half-initialized global API table visible to another session. }
    Pointer(LocalCreate) := RequireProc('CreatePseudoConsole');
    Pointer(LocalResize) := RequireProc('ResizePseudoConsole');
    Pointer(LocalClose) := RequireProc('ClosePseudoConsole');
    Pointer(LocalInitAttributes) :=
      RequireProc('InitializeProcThreadAttributeList');
    Pointer(LocalUpdateAttributes) := RequireProc('UpdateProcThreadAttribute');
    Pointer(LocalDeleteAttributes) :=
      RequireProc('DeleteProcThreadAttributeList');

    GCreatePseudoConsole := LocalCreate;
    GResizePseudoConsole := LocalResize;
    GClosePseudoConsole := LocalClose;
    GInitializeProcThreadAttributeList := LocalInitAttributes;
    GUpdateProcThreadAttribute := LocalUpdateAttributes;
    GDeleteProcThreadAttributeList := LocalDeleteAttributes;
  finally
    LeaveCriticalSection(GConPtyApiLock);
  end;
end;

procedure TWindowsTerminalPtyBackend.CloseHandleIfOpen(var AHandle: THandle);
begin
  if (AHandle <> 0) and (AHandle <> INVALID_HANDLE_VALUE) then
    CloseHandle(AHandle);
  AHandle := 0;
end;

function TWindowsTerminalPtyBackend.ErrorText(const APrefix: string): string;
var
  Code: DWORD;
begin
  Code := GetLastError;
  Result := Format('%s (Win32 error %d: %s)',
    [APrefix, Code, SysErrorMessage(Code)]);
end;

procedure TWindowsTerminalPtyBackend.Start(const AExecutable: string;
  AArguments: TStrings; const AWorkingDirectory: string;
  AColumns, ARows: Word);
var
  Size: TCoord;
  HR: HRESULT;
  AttributeBytes: SizeUInt;
  StartupEx: TStartupInfoExWLocal;
  ProcessInfo: TProcessInformation;
  CommandLineUtf8: string;
  CommandLineWide, WorkingDirectoryWide: UnicodeString;
  CommandLineBuffer: PWideChar;
  WorkingDirectoryPtr: PWideChar;
  CommandLineChars: SizeInt;
begin
  if FProcessHandle <> 0 then
    raise Exception.Create('Windows terminal backend has already been started');
  if Trim(AExecutable) = '' then
    raise Exception.Create('Executable must not be empty');

  LoadConPtyApi;

  if not CreatePipe(FConPtyInputRead, FInputWrite, nil, 0) then
    raise Exception.Create(ErrorText('Unable to create ConPTY input pipe'));
  try
    if not CreatePipe(FOutputRead, FConPtyOutputWrite, nil, 0) then
      raise Exception.Create(ErrorText('Unable to create ConPTY output pipe'));

    Size.X := SmallInt(AColumns);
    Size.Y := SmallInt(ARows);
    HR := GCreatePseudoConsole(Size, FConPtyInputRead,
      FConPtyOutputWrite, 0, FConPty);
    if LongInt(HR) < 0 then
      raise Exception.CreateFmt('CreatePseudoConsole failed (HRESULT 0x%.8x)',
        [DWORD(HR)]);

    FillChar(StartupEx, SizeOf(StartupEx), 0);
    StartupEx.StartupInfo.cb := SizeOf(StartupEx);
    AttributeBytes := 0;
    GInitializeProcThreadAttributeList(nil, 1, 0, AttributeBytes);
    if AttributeBytes = 0 then
      raise Exception.Create(ErrorText(
        'Unable to determine ConPTY process attribute-list size'));
    GetMem(StartupEx.lpAttributeList, AttributeBytes);
    try
      FillChar(StartupEx.lpAttributeList^, AttributeBytes, 0);
      if not GInitializeProcThreadAttributeList(StartupEx.lpAttributeList,
        1, 0, AttributeBytes) then
        raise Exception.Create(ErrorText(
          'Unable to initialize ConPTY process attribute list'));

      if not GUpdateProcThreadAttribute(StartupEx.lpAttributeList, 0,
        PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, Pointer(PtrUInt(FConPty)),
        SizeOf(FConPty), nil, nil) then
        raise Exception.Create(ErrorText(
          'Unable to attach pseudoconsole process attribute'));

      FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
      CommandLineUtf8 := BuildWindowsCommandLine(AExecutable, AArguments);
      CommandLineWide := UTF8Decode(CommandLineUtf8);
      CommandLineChars := Length(CommandLineWide) + 1;
      GetMem(CommandLineBuffer, CommandLineChars * SizeOf(WideChar));
      try
        FillChar(CommandLineBuffer^, CommandLineChars * SizeOf(WideChar), 0);
        if Length(CommandLineWide) > 0 then
          Move(CommandLineWide[1], CommandLineBuffer^,
            Length(CommandLineWide) * SizeOf(WideChar));

        if AWorkingDirectory <> '' then
        begin
          WorkingDirectoryWide := UTF8Decode(AWorkingDirectory);
          WorkingDirectoryPtr := PWideChar(WorkingDirectoryWide);
        end
        else
          WorkingDirectoryPtr := nil;

        if not CreateProcessW(nil, CommandLineBuffer, nil, nil, False,
          EXTENDED_STARTUPINFO_PRESENT_LOCAL, nil, WorkingDirectoryPtr,
          StartupEx.StartupInfo, ProcessInfo) then
          raise Exception.Create(ErrorText('Unable to start ConPTY child process'));
      finally
        FreeMem(CommandLineBuffer);
      end;
    finally
      if StartupEx.lpAttributeList <> nil then
      begin
        GDeleteProcThreadAttributeList(StartupEx.lpAttributeList);
        FreeMem(StartupEx.lpAttributeList);
      end;
    end;

    FProcessHandle := ProcessInfo.hProcess;
    FProcessId := ProcessInfo.dwProcessId;
    FExited := False;
    FExitCode := 0;
    CloseHandleIfOpen(ProcessInfo.hThread);

    { These are the host's duplicate references to the two ConPTY-facing pipe
      ends. The pseudoconsole retains what it needs internally. Keeping them
      open would prevent broken-pipe detection during teardown. }
    CloseHandleIfOpen(FConPtyInputRead);
    CloseHandleIfOpen(FConPtyOutputWrite);
  except
    Close;
    raise;
  end;
end;

function TWindowsTerminalPtyBackend.PollRunning: Boolean;
var
  Code: DWORD;
begin
  if FExited then
    Exit(False);
  if FProcessHandle = 0 then
    Exit(False);
  if not GetExitCodeProcess(FProcessHandle, Code) then
    raise Exception.Create(ErrorText('Unable to query ConPTY child process'));
  if Code = STILL_ACTIVE_LOCAL then
    Exit(True);
  FExited := True;
  FExitCode := Integer(Code);
  Result := False;
end;

function TWindowsTerminalPtyBackend.ReadAvailable(out AData: RawByteString;
  AMaximumBytes: Cardinal): Integer;
var
  Available, ToRead, BytesRead: DWORD;
  Buffer: array[0..8191] of Byte;
  ErrorCode: DWORD;
begin
  AData := '';
  Result := 0;
  if FOutputRead = 0 then
    Exit;

  Available := 0;
  if not PeekNamedPipe(FOutputRead, nil, 0, nil, @Available, nil) then
  begin
    ErrorCode := GetLastError;
    if ErrorCode = ERROR_BROKEN_PIPE_LOCAL then
      Exit;
    raise Exception.CreateFmt('ConPTY output probe failed (Win32 error %d: %s)',
      [ErrorCode, SysErrorMessage(ErrorCode)]);
  end;
  if Available = 0 then
    Exit;

  ToRead := Available;
  if ToRead > SizeOf(Buffer) then
    ToRead := SizeOf(Buffer);
  if (AMaximumBytes > 0) and (ToRead > AMaximumBytes) then
    ToRead := AMaximumBytes;

  BytesRead := 0;
  if not ReadFile(FOutputRead, Buffer[0], ToRead, BytesRead, nil) then
  begin
    ErrorCode := GetLastError;
    if ErrorCode = ERROR_BROKEN_PIPE_LOCAL then
      Exit;
    raise Exception.CreateFmt('ConPTY output read failed (Win32 error %d: %s)',
      [ErrorCode, SysErrorMessage(ErrorCode)]);
  end;
  if BytesRead = 0 then
    Exit;

  SetLength(AData, BytesRead);
  Move(Buffer[0], AData[1], BytesRead);
  Result := BytesRead;
end;

function TWindowsTerminalPtyBackend.WriteData(
  const AData: RawByteString): Integer;
var
  Offset: SizeInt;
  ToWrite, BytesWritten: DWORD;
  ErrorCode: DWORD;
begin
  Result := 0;
  if AData = '' then
    Exit;
  if FInputWrite = 0 then
    raise Exception.Create('Terminal session is closed');

  Offset := 1;
  while Offset <= Length(AData) do
  begin
    ToWrite := Length(AData) - Offset + 1;
    if ToWrite > 65536 then
      ToWrite := 65536;
    BytesWritten := 0;
    if not WriteFile(FInputWrite, AData[Offset], ToWrite,
      BytesWritten, nil) then
    begin
      ErrorCode := GetLastError;
      if ErrorCode = ERROR_BROKEN_PIPE_LOCAL then
        raise Exception.Create('Terminal input pipe is closed');
      raise Exception.CreateFmt('ConPTY input write failed (Win32 error %d: %s)',
        [ErrorCode, SysErrorMessage(ErrorCode)]);
    end;
    if BytesWritten = 0 then
      Break;
    Inc(Offset, BytesWritten);
    Inc(Result, BytesWritten);
  end;
end;

procedure TWindowsTerminalPtyBackend.Resize(AColumns, ARows: Word);
var
  Size: TCoord;
  HR: HRESULT;
begin
  if FConPty = 0 then
    raise Exception.Create('Terminal session is closed');
  Size.X := SmallInt(AColumns);
  Size.Y := SmallInt(ARows);
  HR := GResizePseudoConsole(FConPty, Size);
  if LongInt(HR) < 0 then
    raise Exception.CreateFmt('ResizePseudoConsole failed (HRESULT 0x%.8x)',
      [DWORD(HR)]);
end;

procedure TWindowsTerminalPtyBackend.SendSignal(ASignal: TTerminalSignal);
begin
  case ASignal of
    tsInterrupt:
      WriteData(RawByteString(#3));
    tsEof:
      WriteData(RawByteString(#4));
    tsTerminate, tsKill:
      begin
        if (FProcessHandle <> 0) and not FExited then
          TerminateProcess(FProcessHandle, 1);
      end;
  end;
end;

procedure TWindowsTerminalPtyBackend.Close;
var
  StartedAt: QWord;
begin
  { Explicit teardown must stay bounded even though ClosePseudoConsole uses
    synchronous channels and can emit a final frame. Closing the host sides
    first turns any remaining channel activity into a broken-pipe condition.
    The session worker drains normal output before teardown; a final close-only
    frame is intentionally not guaranteed to be retained. }
  CloseHandleIfOpen(FOutputRead);
  CloseHandleIfOpen(FInputWrite);
  CloseHandleIfOpen(FConPtyInputRead);
  CloseHandleIfOpen(FConPtyOutputWrite);

  if FConPty <> 0 then
  begin
    GClosePseudoConsole(FConPty);
    FConPty := 0;
  end;

  if (FProcessHandle <> 0) and not FExited then
  begin
    StartedAt := GetTickCount64;
    while PollRunning and
      (GetTickCount64 - StartedAt < FTerminationGraceMs) do
      Sleep(10);
    if not FExited then
    begin
      TerminateProcess(FProcessHandle, 1);
      WaitForSingleObject(FProcessHandle, 1000);
      PollRunning;
    end;
  end;
  CloseHandleIfOpen(FProcessHandle);
end;

initialization
  InitCriticalSection(GConPtyApiLock);

finalization
  DoneCriticalSection(GConPtyApiLock);

end.
