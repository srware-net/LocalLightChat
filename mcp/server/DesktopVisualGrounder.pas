unit DesktopVisualGrounder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, ServerConfig;

type
  TDesktopVisualGrounder = class
  private
    FConfig: TServerConfig;
    function FindBundledHelper: string;
    function ReplaceImagePlaceholder(const AValue, AImagePath: string): string;
    function RunGrounder(const AImagePath: string; out AOutput, AError: string): Boolean;
  public
    constructor Create(AConfig: TServerConfig);
    function Ground(const AImageData: TBytes; const AMimeType: string;
      out AStatus: TJSONObject): TJSONArray;
  end;

implementation

uses
  Process, Pipes, jsonparser, McpJson;

function BytesToFile(const AFileName: string; const AData: TBytes): Boolean;
var
  S: TFileStream;
begin
  Result := False;
  S := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(AData) > 0 then
      S.WriteBuffer(AData[0], Length(AData));
    Result := True;
  finally
    S.Free;
  end;
end;

function ReadAvailable(AStream: TInputPipeStream): string;
var
  Buffer: array[0..4095] of Byte;
  N: LongInt;
  Chunk: string;
begin
  Result := '';
  while AStream.NumBytesAvailable > 0 do
  begin
    N := AStream.Read(Buffer[0], SizeOf(Buffer));
    if N <= 0 then Break;
    SetString(Chunk, PChar(@Buffer[0]), N);
    Result := Result + Chunk;
  end;
end;

constructor TDesktopVisualGrounder.Create(AConfig: TServerConfig);
begin
  inherited Create;
  FConfig := AConfig;
end;

function TDesktopVisualGrounder.FindBundledHelper: string;
var
  Base: string;
  Candidates: array[0..3] of string;
  I: Integer;
begin
  Result := '';
  Base := ExtractFilePath(ParamStr(0));
  Candidates[0] := ExpandFileName(Base + 'helpers' + DirectorySeparator +
    'windows_ocr_grounder.ps1');
  Candidates[1] := ExpandFileName(Base + '..' + DirectorySeparator + 'helpers' +
    DirectorySeparator + 'windows_ocr_grounder.ps1');
  Candidates[2] := ExpandFileName(Base + '..' + DirectorySeparator + '..' +
    DirectorySeparator + 'server' + DirectorySeparator + 'helpers' +
    DirectorySeparator + 'windows_ocr_grounder.ps1');
  Candidates[3] := ExpandFileName('server' + DirectorySeparator + 'helpers' +
    DirectorySeparator + 'windows_ocr_grounder.ps1');
  for I := Low(Candidates) to High(Candidates) do
    if FileExists(Candidates[I]) then
      Exit(Candidates[I]);
end;

function TDesktopVisualGrounder.ReplaceImagePlaceholder(const AValue,
  AImagePath: string): string;
begin
  Result := StringReplace(AValue, '{image}', AImagePath, [rfReplaceAll]);
end;

function TDesktopVisualGrounder.RunGrounder(const AImagePath: string;
  out AOutput, AError: string): Boolean;
var
  P: TProcess;
  Command, Helper, Chunk: string;
  I: Integer;
  StartedAt: QWord;
begin
  Result := False;
  AOutput := '';
  AError := '';
  P := TProcess.Create(nil);
  try
    Command := Trim(FConfig.DesktopGrounderCommand);
    if Command = '' then
    begin
      Helper := FindBundledHelper;
      if Helper = '' then
      begin
        AError := 'Bundled OCR helper windows_ocr_grounder.ps1 was not found';
        Exit;
      end;
      P.Executable := 'powershell.exe';
      P.Parameters.Add('-NoLogo');
      P.Parameters.Add('-NoProfile');
      P.Parameters.Add('-NonInteractive');
      P.Parameters.Add('-ExecutionPolicy');
      P.Parameters.Add('Bypass');
      P.Parameters.Add('-File');
      P.Parameters.Add(Helper);
      P.Parameters.Add('-ImagePath');
      P.Parameters.Add(AImagePath);
      P.Parameters.Add('-MinimumConfidence');
      P.Parameters.Add(IntToStr(FConfig.DesktopGrounderMinimumConfidence));
      P.Parameters.Add('-MaxTargets');
      P.Parameters.Add(IntToStr(FConfig.DesktopGrounderMaxTargets));
    end
    else
    begin
      P.Executable := Command;
      for I := 0 to FConfig.DesktopGrounderArguments.Count - 1 do
        P.Parameters.Add(ReplaceImagePlaceholder(
          FConfig.DesktopGrounderArguments[I], AImagePath));
      if FConfig.DesktopGrounderArguments.Count = 0 then
        P.Parameters.Add(AImagePath);
    end;
    P.Options := [poUsePipes, poNoConsole];
    P.Execute;
    StartedAt := GetTickCount64;
    repeat
      Chunk := ReadAvailable(P.Output);
      if Chunk <> '' then AOutput := AOutput + Chunk;
      Chunk := ReadAvailable(P.Stderr);
      if Chunk <> '' then AError := AError + Chunk;
      if not P.Running then Break;
      if (GetTickCount64 - StartedAt) > FConfig.DesktopGrounderTimeoutMs then
      begin
        P.Terminate(1);
        AError := Trim(AError + LineEnding + 'visual grounder timed out');
        Exit;
      end;
      Sleep(10);
    until False;
    AOutput := AOutput + ReadAvailable(P.Output);
    AError := AError + ReadAvailable(P.Stderr);
    Result := P.ExitStatus = 0;
    if (not Result) and (Trim(AError) = '') then
      AError := 'visual grounder exited with code ' + IntToStr(P.ExitStatus);
  finally
    P.Free;
  end;
end;

function TDesktopVisualGrounder.Ground(const AImageData: TBytes;
  const AMimeType: string; out AStatus: TJSONObject): TJSONArray;
var
  TempPath, ExtensionText, OutputText, ErrorText: string;
  Root, FailureRoot: TJSONData;
  Obj: TJSONObject;
  TargetsData: TJSONData;
  FailureReason: string;
begin
  Result := TJSONArray.Create;
  AStatus := TJSONObject.Create;
  AStatus.Add('enabled', FConfig.DesktopVisualGroundingEnabled);
  if not FConfig.DesktopVisualGroundingEnabled then
  begin
    AStatus.Add('available', False);
    AStatus.Add('reason', 'disabled');
    Exit;
  end;

  if SameText(AMimeType, 'image/jpeg') then ExtensionText := '.jpg'
  else ExtensionText := '.png';
  TempPath := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    'lazarus-mcp-ground-' + IntToHex(GetTickCount64, 16) + '-' +
    IntToHex(PtrUInt(Pointer(Self)), SizeOf(Pointer) * 2) + ExtensionText;
  Root := nil;
  try
    try
      BytesToFile(TempPath, AImageData);
      if not RunGrounder(TempPath, OutputText, ErrorText) then
      begin
        FailureReason := Trim(ErrorText);
        FailureRoot := nil;
        try
          if Trim(OutputText) <> '' then
          begin
            try
              FailureRoot := GetJSON(Trim(OutputText));
              if (FailureRoot <> nil) and (FailureRoot.JSONType = jtObject) and
                 (Trim(JsonString(TJSONObject(FailureRoot), 'error', '')) <> '') then
                FailureReason := JsonString(TJSONObject(FailureRoot), 'error', FailureReason);
            except
              on E: Exception do
              begin
                { Keep the process-level failure reason when stdout is not JSON. }
              end;
            end;
          end;
        finally
          FailureRoot.Free;
        end;
        if FailureReason = '' then FailureReason := 'visual grounder failed';
        AStatus.Add('available', False);
        AStatus.Add('reason', FailureReason);
        Exit;
      end;
    except
      on E: Exception do
      begin
        AStatus.Add('available', False);
        AStatus.Add('reason', 'visual grounder unavailable: ' + E.Message);
        Exit;
      end;
    end;
    try
      Root := GetJSON(Trim(OutputText));
    except
      on E: Exception do
      begin
        AStatus.Add('available', False);
        AStatus.Add('reason', 'grounder returned invalid JSON: ' + E.Message);
        AStatus.Add('raw_output', Copy(Trim(OutputText), 1, 1000));
        Exit;
      end;
    end;
    if (Root = nil) or (Root.JSONType <> jtObject) then
    begin
      AStatus.Add('available', False);
      AStatus.Add('reason', 'grounder JSON root must be an object');
      Exit;
    end;
    Obj := TJSONObject(Root);
    AStatus.Add('available', JsonBoolean(Obj, 'ok', True));
    AStatus.Add('provider', JsonString(Obj, 'provider', 'external'));
    if Obj.Find('warning') <> nil then
      AStatus.Add('warning', JsonString(Obj, 'warning'));
    TargetsData := Obj.Find('targets');
    if (TargetsData <> nil) and (TargetsData.JSONType = jtArray) then
    begin
      Result.Free;
      Result := TJSONArray(TargetsData.Clone);
    end;
    AStatus.Add('count', Result.Count);
  finally
    Root.Free;
    if FileExists(TempPath) then DeleteFile(TempPath);
  end;
end;

end.
