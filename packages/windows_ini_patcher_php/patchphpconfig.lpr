program PatchPHPConfig;

{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, IniFiles, Classes;

const
  CERT_RELATIVE_PATH = 'cert\cert.pem';

function GetExecutablePath: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function NormalizePath(const APath: string): string;
begin
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
  if (Length(Result) > 0) and (Result[Length(Result)] = '\') then
    SetLength(Result, Length(Result) - 1);
end;

function CopyFileSimple(const Source, Dest: string): Boolean;
var
  SourceStream, DestStream: TFileStream;
begin
  Result := False;
  try
    SourceStream := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
    try
      DestStream := TFileStream.Create(Dest, fmCreate);
      try
        DestStream.CopyFrom(SourceStream, SourceStream.Size);
        Result := True;
      finally
        DestStream.Free;
      end;
    finally
      SourceStream.Free;
    end;
  except
    Result := False;
  end;
end;

procedure PatchPHPIni(const IniPath, CertPath: string);
var
  Ini: TIniFile;
  CertDir: string;
  NormalizedCertPath: string;
begin
  if not FileExists(IniPath) then
  begin
    WriteLn('[WARN] php.ini not found: ', IniPath);
    Exit;
  end;

  // Ensure cert directory exists
  CertDir := ExtractFilePath(CertPath);
  if not DirectoryExists(CertDir) then
  begin
    if not ForceDirectories(CertDir) then
    begin
      WriteLn('[ERROR] Cannot create cert directory: ', CertDir);
      Exit;
    end;
  end;

  // Normalize path (forward slashes to backslashes)
  NormalizedCertPath := NormalizePath(CertPath);

  try
    // Backup original ini
    if not FileExists(IniPath + '.bak') then
      CopyFileSimple(IniPath, IniPath + '.bak');

    Ini := TIniFile.Create(IniPath);
    try
      Ini.WriteString('curl', 'curl.cainfo', NormalizedCertPath);
      Ini.WriteString('openssl', 'openssl.cafile', NormalizedCertPath);
      Ini.UpdateFile;
      WriteLn('[OK] Patched php.ini with cert path: ', NormalizedCertPath);
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      WriteLn('[ERROR] Failed to patch php.ini: ', E.Message);
  end;
end;

var
  PhpDir, IniPath, CertPath: string;

begin
  PhpDir := GetExecutablePath;
  IniPath := PhpDir + 'php.ini';
  CertPath := PhpDir + CERT_RELATIVE_PATH;

  WriteLn('PHP Config Patcher v1.0');
  WriteLn('========================');
  WriteLn('PHP Directory: ', PhpDir);
  WriteLn('INI File:      ', IniPath);
  WriteLn('Cert Path:     ', CertPath);
  WriteLn;

  PatchPHPIni(IniPath, CertPath);
end.
