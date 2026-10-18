unit uPrerequisites;

{$mode objfpc}{$H+}

interface

function RequiredVCRuntimePresent(out FoundVersion: string): Boolean;
procedure EnsureVCRuntime(const PackageRoot: string);

implementation

uses SysUtils
  {$IFDEF WINDOWS}, Windows, Registry, ShellApi{$ENDIF};

{$IFDEF WINDOWS}
function VersionAtLeast(const Parts: array of Integer): Boolean;
const
  MinParts: array[0..3] of Integer = (14, 40, 0, 0);
var
  I: Integer;
begin
  for I := 0 to 3 do
  begin
    if Parts[I] > MinParts[I] then Exit(True);
    if Parts[I] < MinParts[I] then Exit(False);
  end;
  Result := True;
end;

function CheckView(const View: LongWord; out Version: string): Boolean;
const
  RegPath = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
  Names: array[0..3] of string = ('Major', 'Minor', 'Bld', 'Rbld');
var
  R: TRegistry;
  V: array[0..3] of Integer;
  I: Integer;
begin
  Result := False;
  Version := 'not found';
  R := TRegistry.Create;
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    R.Access := KEY_READ or View;
    if not R.OpenKey(RegPath, False) then Exit;
    if (not R.ValueExists('Installed')) or (R.ReadInteger('Installed') <> 1) then Exit;
    for I := 0 to 3 do
    begin
      if not R.ValueExists(Names[I]) then Exit;
      V[I] := R.ReadInteger(Names[I]);
    end;
    Version := Format('%d.%d.%d.%d', [V[0], V[1], V[2], V[3]]);
    Result := VersionAtLeast(V);
  finally
    R.Free;
  end;
end;

procedure RunRedistInstaller(const InstallerFile: string);
var
  Info: TShellExecuteInfoW;
  VerbW, FileW, ArgsW: WideString;
  ExitCode: DWORD;
begin
  VerbW := 'runas';
  FileW := UTF8Decode(InstallerFile);
  ArgsW := '/install /passive /norestart';
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SEE_MASK_NOCLOSEPROCESS;
  Info.lpVerb := PWideChar(VerbW);
  Info.lpFile := PWideChar(FileW);
  Info.lpParameters := PWideChar(ArgsW);
  Info.nShow := SW_SHOWNORMAL;
  if not ShellExecuteExW(@Info) then
    raise Exception.CreateFmt('Could not start VC++ installation (Windows error %d).',
      [GetLastError]);
  if Info.hProcess = 0 then
    raise Exception.Create('VC++ installer returned no process.');
  try
    if WaitForSingleObject(Info.hProcess, INFINITE) <> WAIT_OBJECT_0 then
      raise Exception.Create('Waiting for VC++ installation failed.');
    if not GetExitCodeProcess(Info.hProcess, ExitCode) then
      raise Exception.Create('Could not read VC++ installer exit code.');
    // 3010 means success with restart required. We still re-check the registry.
    if (ExitCode <> 0) and (ExitCode <> 3010) and (ExitCode <> 1638) then
      raise Exception.CreateFmt('VC++ installation failed (Code %d).',
        [ExitCode]);
  finally
    CloseHandle(Info.hProcess);
  end;
end;
{$ENDIF}

function RequiredVCRuntimePresent(out FoundVersion: string): Boolean;
{$IFDEF WINDOWS}
var
  ThisVersion: string;
  Good: Boolean;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  FoundVersion := 'not found';
  try
    Good := CheckView(KEY_WOW64_64KEY, ThisVersion);
    if ThisVersion <> 'not found' then FoundVersion := ThisVersion;
    if Good then Exit(True);
    Good := CheckView(KEY_WOW64_32KEY, ThisVersion);
    if ThisVersion <> 'not found' then FoundVersion := ThisVersion;
    Result := Good;
  except
    on E: Exception do
    begin
      FoundVersion := 'Registry error: ' + E.Message;
      Result := False;
    end;
  end;
  {$ELSE}
  FoundVersion := 'Not required (Linux)';
  Result := True;
  {$ENDIF}
end;

procedure EnsureVCRuntime(const PackageRoot: string);
{$IFDEF WINDOWS}
var
  Found, Installer: string;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if RequiredVCRuntimePresent(Found) then Exit;
  // Distribution requirement: bundle the official Microsoft installer here.
  // No manual download link, button or runtime option in the user interface.
  Installer := IncludeTrailingPathDelimiter(PackageRoot) +
    'prerequisites' + PathDelim + 'VC_redist.x64.exe';
  if not FileExists(Installer) then
    raise Exception.Create('The required VC++ runtime (x64, at least 14.40) is missing. ' +
      'The LocalLightChat package also lacks prerequisites\VC_redist.x64.exe.');
  RunRedistInstaller(Installer);
  if not RequiredVCRuntimePresent(Found) then
    raise Exception.Create('The VC++ runtime is still unavailable after attempted installation ' +
      'at the required version. Found: ' + Found);
  {$ENDIF}
end;

end.
