unit uSingleInstance;

{$mode objfpc}{$H+}

interface

// Returns False only when another manager instance holds the OS lock.
// Unexpected OS errors raise an exception so the manager never starts
// unprotected and launches a second set of services.
function AcquireSingleInstance: Boolean;
procedure ReleaseSingleInstance;

implementation

uses
  SysUtils
  {$IFDEF WINDOWS}, Windows{$ENDIF}
  {$IFDEF UNIX}, BaseUnix, Unix{$ENDIF};

{$IFDEF WINDOWS}
var
  InstanceMutex: THandle = 0;
{$ENDIF}

{$IFDEF UNIX}
var
  InstanceLockFD: cint = -1;
{$ENDIF}

function AcquireSingleInstance: Boolean;
{$IFDEF WINDOWS}
var
  MutexName: UnicodeString;
  WinError: DWORD;
{$ENDIF}
{$IFDEF UNIX}
var
  LockDir, LockName: string;
  LockError: cint;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if InstanceMutex <> 0 then Exit(True);
  // Local\ is session-scoped. The name is independent of the EXE filename
  // and installation path, so two copies cannot start in the same session.
  MutexName := 'Local\LocalLightChat.Instance';
  InstanceMutex := CreateMutexW(nil, False, PWideChar(MutexName));
  if InstanceMutex = 0 then
    raise Exception.CreateFmt('Unable to create the instance mutex (Windows error %d).',
      [GetLastError]);

  WinError := GetLastError;
  if WinError = ERROR_ALREADY_EXISTS then
  begin
    CloseHandle(InstanceMutex);
    InstanceMutex := 0;
    Exit(False);
  end;
  Result := True;
  {$ELSE}
  if InstanceLockFD >= 0 then Exit(True);

  // The config directory is private to the user. Never delete the lock file:
  // removing it while another process has it open would allow two owners.
  LockDir := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
  if not ForceDirectories(LockDir) then
    raise Exception.Create('Unable to create the LocalLightChat configuration directory.');
  LockName := LockDir + 'LocalLightChat.instance.lock';
  InstanceLockFD := fpOpen(PChar(LockName), O_RDWR or O_CREAT or O_NOFOLLOW, &600);
  if InstanceLockFD < 0 then
    raise Exception.CreateFmt('Unable to open the instance lock (Linux error %d).',
      [fpGetErrno]);

  // Do not let xdg-open, the browser, nginx or PHP inherit our lock on exec.
  if fpFcntl(InstanceLockFD, F_SETFD, 1) <> 0 then  // 1 = FD_CLOEXEC
  begin
    LockError := fpGetErrno;
    fpClose(InstanceLockFD);
    InstanceLockFD := -1;
    raise Exception.CreateFmt('Unable to protect the instance lock (Linux error %d).',
      [LockError]);
  end;

  if fpFlock(InstanceLockFD, LOCK_EX or LOCK_NB) <> 0 then
  begin
    LockError := fpGetErrno;
    fpClose(InstanceLockFD);
    InstanceLockFD := -1;
    // EWOULDBLOCK/EAGAIN = 11 on Linux, EACCES = 13.
    // EACCES can also be reported for an existing advisory lock.
    if (LockError = 11) or (LockError = 13) then Exit(False);
    raise Exception.CreateFmt('Unable to acquire the instance lock (Linux error %d).',
      [LockError]);
  end;
  Result := True;
  {$ENDIF}
end;

procedure ReleaseSingleInstance;
begin
  {$IFDEF WINDOWS}
  if InstanceMutex <> 0 then
  begin
    CloseHandle(InstanceMutex);
    InstanceMutex := 0;
  end;
  {$ELSE}
  if InstanceLockFD >= 0 then
  begin
    fpFlock(InstanceLockFD, LOCK_UN);
    fpClose(InstanceLockFD);
    InstanceLockFD := -1;
  end;
  {$ENDIF}
end;

finalization
  ReleaseSingleInstance;

end.
