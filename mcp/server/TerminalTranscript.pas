unit TerminalTranscript;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ServerLog;

type
  { Keeps terminal diagnostics separate from PTY/session management.  A
    transcript instance belongs to exactly one terminal session and may be
    called concurrently by the PTY output worker and MCP control calls. }
  TTerminalTranscript = class
  private
    FLock: TRTLCriticalSection;
    FLogger: TServerLogger;
    FSessionId: string;
    FCorrelationId: string;
    FLogOutput: Boolean;
    FLogInput: Boolean;
    FMirrorOutputToConsole: Boolean;
    FMirrorInputToConsole: Boolean;
    FConsoleOutputMode: string;
    FConsoleAtLineStart: Boolean;
    FConsoleStream: string;
    procedure MirrorPrefixed(const AStreamName: string;
      const AChunk: RawByteString);
    procedure MirrorRaw(const AChunk: RawByteString);
    function PrefixFor(const AStreamName: string): RawByteString;
    function NormalizeForPrefixedConsole(
      const AChunk: RawByteString): RawByteString;
  public
    constructor Create(ALogger: TServerLogger; const ASessionId,
      ACorrelationId: string; ALogOutput, ALogInput,
      AMirrorOutputToConsole, AMirrorInputToConsole: Boolean;
      const AConsoleOutputMode: string);
    destructor Destroy; override;
    procedure OutputChunk(const AChunk: RawByteString);
    procedure InputChunk(const AChunk: RawByteString; ASensitive: Boolean);
    procedure InputKey(const ADescription: string; AByteCount: Integer);
    procedure Event(const AMessage: string);
  end;

implementation

constructor TTerminalTranscript.Create(ALogger: TServerLogger;
  const ASessionId, ACorrelationId: string; ALogOutput, ALogInput,
  AMirrorOutputToConsole, AMirrorInputToConsole: Boolean;
  const AConsoleOutputMode: string);
begin
  inherited Create;
  InitCriticalSection(FLock);
  FLogger := ALogger;
  FSessionId := ASessionId;
  FCorrelationId := ACorrelationId;
  FLogOutput := ALogOutput;
  FLogInput := ALogInput;
  FMirrorOutputToConsole := AMirrorOutputToConsole;
  FMirrorInputToConsole := AMirrorInputToConsole;
  FConsoleOutputMode := LowerCase(Trim(AConsoleOutputMode));
  if (FConsoleOutputMode <> 'raw') and
    (FConsoleOutputMode <> 'prefixed') then
    FConsoleOutputMode := 'prefixed';
  FConsoleAtLineStart := True;
  FConsoleStream := '';
end;

destructor TTerminalTranscript.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TTerminalTranscript.PrefixFor(
  const AStreamName: string): RawByteString;
begin
  Result := RawByteString('[' + FSessionId + ' terminal ' + AStreamName + '] ');
end;

function TTerminalTranscript.NormalizeForPrefixedConsole(
  const AChunk: RawByteString): RawByteString;
begin
  Result := AChunk;
  { A prefixed diagnostic console is line oriented.  Treat carriage-return
    progress updates as line boundaries so they cannot overwrite MCP log
    lines.  Raw mode remains byte-for-byte. }
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

procedure TTerminalTranscript.MirrorRaw(const AChunk: RawByteString);
begin
  if (FLogger <> nil) and (AChunk <> '') then
    FLogger.WriteConsoleRaw(AChunk);
end;

procedure TTerminalTranscript.MirrorPrefixed(const AStreamName: string;
  const AChunk: RawByteString);
var
  Data, OutBlock, Prefix: RawByteString;
  I, SegmentStart: SizeInt;
begin
  if (FLogger = nil) or (AChunk = '') then
    Exit;

  Data := NormalizeForPrefixedConsole(AChunk);
  Prefix := PrefixFor(AStreamName);
  OutBlock := '';

  { Switching from an unterminated PTY prompt to an input event should remain
    readable in the server console rather than producing
    "Password:[session IN] ..." on one line. }
  if (FConsoleStream <> '') and (FConsoleStream <> AStreamName) and
    (not FConsoleAtLineStart) then
  begin
    OutBlock := OutBlock + RawByteString(LineEnding);
    FConsoleAtLineStart := True;
  end;
  FConsoleStream := AStreamName;

  SegmentStart := 1;
  I := 1;
  while I <= Length(Data) do
  begin
    if FConsoleAtLineStart then
    begin
      OutBlock := OutBlock + Prefix;
      FConsoleAtLineStart := False;
    end;

    if Data[I] = #10 then
    begin
      if I >= SegmentStart then
        OutBlock := OutBlock + Copy(Data, SegmentStart, I - SegmentStart + 1);
      FConsoleAtLineStart := True;
      SegmentStart := I + 1;
    end;
    Inc(I);
  end;

  if SegmentStart <= Length(Data) then
  begin
    if FConsoleAtLineStart then
    begin
      OutBlock := OutBlock + Prefix;
      FConsoleAtLineStart := False;
    end;
    OutBlock := OutBlock + Copy(Data, SegmentStart,
      Length(Data) - SegmentStart + 1);
  end;

  if OutBlock <> '' then
    FLogger.WriteConsoleRaw(OutBlock);
end;

procedure TTerminalTranscript.OutputChunk(const AChunk: RawByteString);
begin
  if AChunk = '' then
    Exit;
  EnterCriticalSection(FLock);
  try
    if FLogOutput and (FLogger <> nil) then
      FLogger.WriteFileBlock(FCorrelationId + ' terminal ' + FSessionId +
        ' OUT: ', string(AChunk));
    if FMirrorOutputToConsole then
    begin
      if FConsoleOutputMode = 'raw' then
        MirrorRaw(AChunk)
      else
        MirrorPrefixed('OUT', AChunk);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TTerminalTranscript.InputChunk(const AChunk: RawByteString;
  ASensitive: Boolean);
var
  DisplayChunk: RawByteString;
begin
  if ASensitive then
    DisplayChunk := RawByteString(Format('<sensitive input: %d bytes>',
      [Length(AChunk)]))
  else
    DisplayChunk := AChunk;

  EnterCriticalSection(FLock);
  try
    if FLogInput and (FLogger <> nil) then
      FLogger.WriteFileBlock(FCorrelationId + ' terminal ' + FSessionId +
        ' IN: ', string(DisplayChunk));
    if FMirrorInputToConsole then
    begin
      if FConsoleOutputMode = 'raw' then
      begin
        if ASensitive then
          MirrorRaw(DisplayChunk + RawByteString(LineEnding))
        else
          MirrorRaw(DisplayChunk);
      end
      else
      begin
        MirrorPrefixed('IN', DisplayChunk);
        { A write without Enter (passwords, individual key presses, REPL input)
          is still one visible MCP action. End the diagnostic line so later
          PTY output does not get glued to it. }
        if not FConsoleAtLineStart then
        begin
          if FLogger <> nil then
            FLogger.WriteConsoleRaw(RawByteString(LineEnding));
          FConsoleAtLineStart := True;
        end;
      end;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TTerminalTranscript.InputKey(const ADescription: string;
  AByteCount: Integer);
var
  DisplayChunk: RawByteString;
begin
  DisplayChunk := RawByteString(Format('<key: %s; %d bytes>',
    [ADescription, AByteCount]));
  EnterCriticalSection(FLock);
  try
    if FLogInput and (FLogger <> nil) then
      FLogger.WriteFileBlock(FCorrelationId + ' terminal ' + FSessionId +
        ' KEY: ', ADescription + Format(' (%d bytes)', [AByteCount]));
    if FMirrorInputToConsole then
    begin
      { Never mirror the encoded control bytes themselves: Ctrl+O, Ctrl+L,
        ESC and friends could alter the MCP server console. The transcript is
        diagnostic, so show a semantic key label instead. }
      if FConsoleOutputMode = 'raw' then
        MirrorRaw(DisplayChunk + RawByteString(LineEnding))
      else
      begin
        MirrorPrefixed('KEY', DisplayChunk);
        if not FConsoleAtLineStart then
        begin
          if FLogger <> nil then
            FLogger.WriteConsoleRaw(RawByteString(LineEnding));
          FConsoleAtLineStart := True;
        end;
      end;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TTerminalTranscript.Event(const AMessage: string);
begin
  if (FLogger = nil) or (AMessage = '') then
    Exit;
  if FCorrelationId <> '' then
    FLogger.Write(FCorrelationId + ' terminal ' + FSessionId + ': ' + AMessage)
  else
    FLogger.Write('terminal ' + FSessionId + ': ' + AMessage);
end;

end.
