unit ServerLog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  TServerLogger = class
  private
    FLock: TCriticalSection;
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    procedure Write(const AMessage: string);
    procedure WriteBlock(const APrefix, AText: string);
    procedure WriteFileBlock(const APrefix, AText: string);
    procedure WriteConsoleRaw(const AText: RawByteString);
    procedure WriteConsoleLine(const AText: string);
  end;

implementation

constructor TServerLogger.Create(const AFileName: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFileName := AFileName;
end;

destructor TServerLogger.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TServerLogger.Write(const AMessage: string);
var
  Line: string;
  OutputFile: TextFile;
  IsOpen: Boolean;
begin
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + AMessage;
  FLock.Acquire;
  try
    WriteLn(Line);
    Flush(Output);
    if FFileName <> '' then
    begin
      if ExtractFileDir(FFileName) <> '' then
        ForceDirectories(ExtractFileDir(FFileName));
      AssignFile(OutputFile, FFileName);
      IsOpen := False;
      try
        if FileExists(FFileName) then
          Append(OutputFile)
        else
          Rewrite(OutputFile);
        IsOpen := True;
        WriteLn(OutputFile, Line);
      finally
        if IsOpen then
          CloseFile(OutputFile);
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TServerLogger.WriteBlock(const APrefix, AText: string);
var
  Normalized, Line: string;
  P: SizeInt;
begin
  Normalized := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #0, '\0', [rfReplaceAll]);
  while Normalized <> '' do
  begin
    P := Pos(#10, Normalized);
    if P > 0 then
    begin
      Line := Copy(Normalized, 1, P - 1);
      Delete(Normalized, 1, P);
    end
    else
    begin
      Line := Normalized;
      Normalized := '';
    end;
    Write(APrefix + Line);
  end;
end;

procedure TServerLogger.WriteFileBlock(const APrefix, AText: string);
var
  Normalized, Line, TimestampedLine: string;
  P: SizeInt;
  OutputFile: TextFile;
  IsOpen: Boolean;
begin
  if (FFileName = '') or (AText = '') then
    Exit;

  Normalized := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #0, '\0', [rfReplaceAll]);

  FLock.Acquire;
  try
    if ExtractFileDir(FFileName) <> '' then
      ForceDirectories(ExtractFileDir(FFileName));
    AssignFile(OutputFile, FFileName);
    IsOpen := False;
    try
      if FileExists(FFileName) then
        Append(OutputFile)
      else
        Rewrite(OutputFile);
      IsOpen := True;
      while Normalized <> '' do
      begin
        P := Pos(#10, Normalized);
        if P > 0 then
        begin
          Line := Copy(Normalized, 1, P - 1);
          Delete(Normalized, 1, P);
        end
        else
        begin
          Line := Normalized;
          Normalized := '';
        end;
        TimestampedLine := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
          ' ' + APrefix + Line;
        WriteLn(OutputFile, TimestampedLine);
      end;
    finally
      if IsOpen then
        CloseFile(OutputFile);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TServerLogger.WriteConsoleRaw(const AText: RawByteString);
begin
  if AText = '' then
    Exit;
  FLock.Acquire;
  try
    System.Write(Output, string(AText));
    Flush(Output);
  finally
    FLock.Release;
  end;
end;

procedure TServerLogger.WriteConsoleLine(const AText: string);
begin
  FLock.Acquire;
  try
    WriteLn(Output, AText);
    Flush(Output);
  finally
    FLock.Release;
  end;
end;

end.
