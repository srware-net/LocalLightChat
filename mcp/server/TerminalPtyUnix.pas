unit TerminalPtyUnix;

{$mode objfpc}{$H+}
{$pointermath on}

interface

{$IFNDEF LINUX}
  {$ERROR TerminalPtyUnix currently supports Linux only}
{$ENDIF}

uses
  Classes, SysUtils, BaseUnix, Unix, ctypes, TerminalPtyBackend;

type
  TUnixTerminalPtyBackend = class(TTerminalPtyBackend)
  private
    FMasterFd: cint;
    FTerminationGraceMs: Cardinal;
    procedure UpdateExitStatus(AStatus: cint);
    procedure WaitForExit(AMilliseconds: Cardinal);
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
  PUnixWinSize = ^TUnixWinSize;
  TUnixWinSize = packed record
    ws_row: cushort;
    ws_col: cushort;
    ws_xpixel: cushort;
    ws_ypixel: cushort;
  end;

  TPCharVector = array[0..0] of PChar;
  PPCharVector = ^TPCharVector;

const
  { Linux asm-generic/ioctls.h }
  LINUX_TIOCSWINSZ = $5414;

function forkpty(amaster: pcint; name: PChar; termp: Pointer;
  winp: PUnixWinSize): TPid; cdecl; external 'util' name 'forkpty';

procedure FreeArgVector(AVector: PPCharVector; ACount: Integer);
var
  I: Integer;
begin
  if AVector = nil then
    Exit;
  for I := 0 to ACount - 1 do
    if AVector^[I] <> nil then
      StrDispose(AVector^[I]);
  FreeMem(AVector);
end;

function BuildArgVector(const AExecutable: string;
  AArguments: TStrings; out ACount: Integer): PPCharVector;
var
  I: Integer;
begin
  if AArguments <> nil then
    ACount := AArguments.Count + 1
  else
    ACount := 1;
  GetMem(Result, (ACount + 1) * SizeOf(PChar));
  FillChar(Result^, (ACount + 1) * SizeOf(PChar), 0);
  Result^[0] := StrNew(PChar(AExecutable));
  if AArguments <> nil then
    for I := 0 to AArguments.Count - 1 do
      Result^[I + 1] := StrNew(PChar(AArguments[I]));
  Result^[ACount] := nil;
end;

constructor TUnixTerminalPtyBackend.Create(ATerminationGraceMs: Cardinal);
begin
  inherited Create;
  FMasterFd := -1;
  FTerminationGraceMs := ATerminationGraceMs;
end;

destructor TUnixTerminalPtyBackend.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TUnixTerminalPtyBackend.Start(const AExecutable: string;
  AArguments: TStrings; const AWorkingDirectory: string;
  AColumns, ARows: Word);
var
  MasterFd, Flags: cint;
  ChildPid: TPid;
  WinSize: TUnixWinSize;
  ArgVector: PPCharVector;
  ArgCount: Integer;
begin
  if FProcessId <> 0 then
    raise Exception.Create('Terminal PTY backend has already been started');
  if Trim(AExecutable) = '' then
    raise Exception.Create('Executable must not be empty');

  FillChar(WinSize, SizeOf(WinSize), 0);
  WinSize.ws_col := AColumns;
  WinSize.ws_row := ARows;
  ArgVector := BuildArgVector(AExecutable, AArguments, ArgCount);
  MasterFd := -1;
  ChildPid := forkpty(@MasterFd, nil, nil, @WinSize);
  if ChildPid < 0 then
  begin
    FreeArgVector(ArgVector, ArgCount);
    raise Exception.CreateFmt('forkpty failed (errno=%d)', [fpGetErrNo]);
  end;

  if ChildPid = 0 then
  begin
    { forkpty has already made the slave PTY the controlling terminal and
      connected it to stdin/stdout/stderr. Keep the post-fork path tiny. }
    if (AWorkingDirectory <> '') and
      (fpChDir(PChar(AWorkingDirectory)) <> 0) then
      fpExit(126);
    FpExecVP(RawByteString(AExecutable), PPChar(ArgVector));
    fpExit(127);
  end;

  FreeArgVector(ArgVector, ArgCount);
  FMasterFd := MasterFd;
  FProcessId := ChildPid;
  FExited := False;
  FExitCode := 0;

  Flags := fpFcntl(FMasterFd, F_GETFL, 0);
  if Flags >= 0 then
    fpFcntl(FMasterFd, F_SETFL, Flags or O_NONBLOCK);
end;

procedure TUnixTerminalPtyBackend.UpdateExitStatus(AStatus: cint);
begin
  FExited := True;
  if wifexited(AStatus) then
    FExitCode := wexitstatus(AStatus)
  else if wifsignaled(AStatus) then
    FExitCode := 128 + wtermsig(AStatus)
  else
    FExitCode := 1;
end;

function TUnixTerminalPtyBackend.PollRunning: Boolean;
var
  Status: cint;
  WaitResult: TPid;
begin
  if FExited then
    Exit(False);
  if FProcessId <= 0 then
    Exit(False);

  Status := 0;
  WaitResult := fpWaitPid(FProcessId, @Status, WNOHANG);
  if WaitResult = 0 then
    Exit(True);
  if WaitResult = FProcessId then
  begin
    UpdateExitStatus(Status);
    Exit(False);
  end;

  if (WaitResult < 0) and (fpGetErrNo = ESysECHILD) then
  begin
    FExited := True;
    if FExitCode = 0 then
      FExitCode := 1;
    Exit(False);
  end;
  Result := True;
end;

function TUnixTerminalPtyBackend.ReadAvailable(out AData: RawByteString;
  AMaximumBytes: Cardinal): Integer;
var
  Buffer: array[0..8191] of Byte;
  Requested: SizeInt;
  ReadCount: ssize_t;
  ErrNo: cint;
begin
  AData := '';
  Result := 0;
  if FMasterFd < 0 then
    Exit;

  Requested := SizeOf(Buffer);
  if (AMaximumBytes > 0) and (AMaximumBytes < Cardinal(Requested)) then
    Requested := AMaximumBytes;
  if Requested <= 0 then
    Exit;

  ReadCount := fpRead(FMasterFd, Buffer, Requested);
  if ReadCount > 0 then
  begin
    SetLength(AData, ReadCount);
    Move(Buffer[0], AData[1], ReadCount);
    Exit(ReadCount);
  end;

  if ReadCount < 0 then
  begin
    ErrNo := fpGetErrNo;
    { EIO is the normal Linux PTY-master result once the slave side has gone. }
    if (ErrNo <> ESysEAGAIN) and (ErrNo <> ESysEINTR) and
      (ErrNo <> ESysEIO) then
      raise Exception.CreateFmt('PTY read failed (errno=%d)', [ErrNo]);
  end;
end;

function TUnixTerminalPtyBackend.WriteData(
  const AData: RawByteString): Integer;
var
  Offset: SizeInt;
  Written: ssize_t;
  ErrNo: cint;
  RetryCount: Integer;
begin
  Result := 0;
  if AData = '' then
    Exit;
  if FMasterFd < 0 then
    raise Exception.Create('Terminal session is closed');

  Offset := 1;
  RetryCount := 0;
  while Offset <= Length(AData) do
  begin
    Written := fpWrite(FMasterFd, AData[Offset], Length(AData) - Offset + 1);
    if Written > 0 then
    begin
      Inc(Offset, Written);
      Inc(Result, Written);
      RetryCount := 0;
      Continue;
    end;

    ErrNo := fpGetErrNo;
    if ErrNo = ESysEINTR then
      Continue;
    if ErrNo = ESysEAGAIN then
    begin
      Inc(RetryCount);
      if RetryCount >= 500 then
        raise Exception.Create('PTY input remained blocked for too long');
      Sleep(10);
      Continue;
    end;
    raise Exception.CreateFmt('PTY write failed (errno=%d)', [ErrNo]);
  end;
end;

procedure TUnixTerminalPtyBackend.Resize(AColumns, ARows: Word);
var
  WinSize: TUnixWinSize;
begin
  if FMasterFd < 0 then
    raise Exception.Create('Terminal session is closed');
  FillChar(WinSize, SizeOf(WinSize), 0);
  WinSize.ws_col := AColumns;
  WinSize.ws_row := ARows;
  if fpIOCtl(FMasterFd, TIOCtlRequest(LINUX_TIOCSWINSZ), @WinSize) <> 0 then
    raise Exception.CreateFmt('PTY resize failed (errno=%d)', [fpGetErrNo]);
end;

procedure TUnixTerminalPtyBackend.SendSignal(ASignal: TTerminalSignal);
begin
  case ASignal of
    tsInterrupt:
      WriteData(RawByteString(#3));
    tsEof:
      WriteData(RawByteString(#4));
    tsTerminate:
      if (FProcessId > 0) and not FExited then
        fpKill(-FProcessId, SIGTERM);
    tsKill:
      if (FProcessId > 0) and not FExited then
        fpKill(-FProcessId, SIGKILL);
  end;
end;

procedure TUnixTerminalPtyBackend.WaitForExit(AMilliseconds: Cardinal);
var
  StartedAt: QWord;
begin
  StartedAt := GetTickCount64;
  while PollRunning do
  begin
    if (AMilliseconds = 0) or
      (GetTickCount64 - StartedAt >= AMilliseconds) then
      Break;
    Sleep(10);
  end;
end;

procedure TUnixTerminalPtyBackend.Close;
begin
  if (FProcessId > 0) and not FExited then
  begin
    fpKill(-FProcessId, SIGTERM);
    WaitForExit(FTerminationGraceMs);
    if not FExited then
    begin
      fpKill(-FProcessId, SIGKILL);
      WaitForExit(1000);
    end;
  end;

  if FMasterFd >= 0 then
  begin
    fpClose(FMasterFd);
    FMasterFd := -1;
  end;
end;

end.
