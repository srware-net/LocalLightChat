unit uNetworkConfig;

{$mode objfpc}{$H+}

interface

// Reads/writes the two IPv4 nginx listeners used by LocalLightChat.
// Only the 8081 and 8082 listen directives are ever rewritten.
function GetNetworkAccess(const ConfigFile: string): Boolean;
procedure SetNetworkAccess(const ConfigFile: string; EnableLAN: Boolean);

implementation

uses
  Classes, SysUtils;

type
  TListenMode = (lmLocal, lmNetwork);

function LoadBytes(const FileName: string): string;
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if S.Size > MaxInt then
      raise Exception.Create('nginx.conf is too large');
    SetLength(Result, Integer(S.Size));
    if Length(Result) > 0 then S.ReadBuffer(Result[1], Length(Result));
  finally
    S.Free;
  end;
end;

procedure SaveBytes(const FileName, Content: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Content) > 0 then S.WriteBuffer(Content[1], Length(Content));
  finally
    S.Free;
  end;
end;

// Return the two expected listeners only. Other nginx directives and comments
// are intentionally not parsed or changed. Preserve the original suffix.
function ParseListener(const Line: string; out Port: Integer;
  out CurrentMode: TListenMode; out Prefix, Suffix: string): Boolean;
var
  S, Directive, AddressToken, Rest: string;
  I, SemiPos, TokenEnd, Indent: Integer;
begin
  Result := False;
  Port := 0;
  S := TrimLeft(Line);
  if Length(S) < 7 then Exit;
  if (Copy(S, 1, 6) <> 'listen') or
    not (S[7] in [' ', #9]) then Exit;

  Indent := Length(Line) - Length(S);
  Rest := TrimLeft(Copy(S, 7, MaxInt));
  SemiPos := Pos(';', Rest);
  if SemiPos < 2 then Exit;

  Directive := Copy(Rest, 1, SemiPos - 1);
  TokenEnd := Length(Directive) + 1;
  for I := 1 to Length(Directive) do
    if Directive[I] in [' ', #9] then
    begin
      TokenEnd := I;
      Break;
    end;
  AddressToken := Copy(Directive, 1, TokenEnd - 1);

  if (AddressToken = '127.0.0.1:8081') or
     (AddressToken = '0.0.0.0:8081') or (AddressToken = '8081') then
    Port := 8081
  else if (AddressToken = '127.0.0.1:8082') or
          (AddressToken = '0.0.0.0:8082') or (AddressToken = '8082') then
    Port := 8082
  else
    Exit;

  if Copy(AddressToken, 1, 10) = '127.0.0.1:' then
    CurrentMode := lmLocal
  else
    CurrentMode := lmNetwork;

  // Include indentation and preserve all spacing/options after the address,
  // including ' ssl' on port 8082 and any trailing comment.
  Prefix := Copy(Line, 1, Indent);
  Suffix := Copy(Rest, TokenEnd, MaxInt);
  if (Port = 8082) and
     (Pos('ssl', LowerCase(Copy(Directive, TokenEnd, MaxInt))) = 0) then
    raise Exception.Create('nginx port 8082 must retain its SSL option');
  Result := True;
end;

procedure CheckModeAndRewrite(const Source: string; EnableLAN: Boolean;
  out ConfiguredLAN: Boolean; out Updated: string);
var
  PosStart, PosEnd, CRLen, Port, N8081, N8082: Integer;
  Line, Prefix, Suffix, NewLine: string;
  ActualMode, FirstMode: TListenMode;
  Found: Boolean;
  IP: string;
begin
  if EnableLAN then IP := '0.0.0.0' else IP := '127.0.0.1';
  Updated := '';
  PosStart := 1;
  N8081 := 0;
  N8082 := 0;
  FirstMode := lmLocal;
  Found := False;
  while PosStart <= Length(Source) do
  begin
    PosEnd := PosStart;
    while (PosEnd <= Length(Source)) and
      not (Source[PosEnd] in [#10, #13]) do Inc(PosEnd);
    Line := Copy(Source, PosStart, PosEnd - PosStart);
    CRLen := 0;
    if PosEnd <= Length(Source) then
    begin
      CRLen := 1;
      if (Source[PosEnd] = #13) and (PosEnd < Length(Source)) and
         (Source[PosEnd + 1] = #10) then CRLen := 2;
    end;

    if ParseListener(Line, Port, ActualMode, Prefix, Suffix) then
    begin
      if Port = 8081 then Inc(N8081) else Inc(N8082);
      if not Found then
      begin
        Found := True;
        FirstMode := ActualMode;
      end
      else if FirstMode <> ActualMode then
        raise Exception.Create('nginx listener modes differ (8081 versus 8082)');
      // Preserve directive options and comments, including the semicolon.
      // The address is always the first token in our known nginx.conf format.
      if ((EnableLAN and (ActualMode = lmNetwork)) or
          ((not EnableLAN) and (ActualMode = lmLocal))) then
        NewLine := Line
      else
        NewLine := Prefix + 'listen       ' + IP + ':' + IntToStr(Port) + Suffix;
      Updated := Updated + NewLine;
    end
    else
      Updated := Updated + Line;

    if CRLen <> 0 then
      Updated := Updated + Copy(Source, PosEnd, CRLen);
    PosStart := PosEnd + CRLen;
  end;
  if (N8081 <> 1) or (N8082 <> 1) then
    raise Exception.CreateFmt('Expected one nginx listen directive for each port 8081/8082 (found %d/%d)',
      [N8081, N8082]);
  ConfiguredLAN := FirstMode = lmNetwork;
end;

function GetNetworkAccess(const ConfigFile: string): Boolean;
var
  Ignored: string;
begin
  CheckModeAndRewrite(LoadBytes(ConfigFile), False, Result, Ignored);
end;

procedure SetNetworkAccess(const ConfigFile: string; EnableLAN: Boolean);
var
  Original, Updated, TmpFile, BackupFile: string;
  OldLAN: Boolean;
begin
  Original := LoadBytes(ConfigFile);
  CheckModeAndRewrite(Original, EnableLAN, OldLAN, Updated);
  if OldLAN = EnableLAN then Exit;
  TmpFile := ConfigFile + '.llc.tmp';
  BackupFile := ConfigFile + '.llc.bak';
  // Back up the last valid configuration. The tmp file is written fully
  // before the live config is touched.
  SaveBytes(TmpFile, Updated);
  if FileExists(BackupFile) and (not DeleteFile(BackupFile)) then
    raise Exception.Create('Could not replace nginx.conf backup');
  if not RenameFile(ConfigFile, BackupFile) then
    raise Exception.Create('Could not back up nginx.conf (check permissions)');
  if not RenameFile(TmpFile, ConfigFile) then
  begin
    if not RenameFile(BackupFile, ConfigFile) then
      raise Exception.Create('Could not update or restore nginx.conf! Backup: ' + BackupFile);
    raise Exception.Create('Could not update nginx.conf; previous configuration restored');
  end;
end;

end.
