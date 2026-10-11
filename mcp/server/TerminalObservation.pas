unit TerminalObservation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TerminalScreen;

type
  TTerminalObservationCapture = record
    Text: UTF8String;
    Changed: Boolean;
    AlternateScreen: Boolean;
    RawBytesProcessed: QWord;
    RawBytesSinceLast: QWord;
    ScrollbackFromSeq: QWord;
    ScrollbackNextSeq: QWord;
    ScrollbackMissed: Boolean;
    RenderedBytes: Cardinal;
    OmittedBytes: Cardinal;
    ScreenVersion: QWord;
  end;

  { Per-session agent observation cursor. Unlike the raw transcript cursor,
    this cursor advances to the newest rendered state on every capture. If an
    observation is truncated, omitted old screen history is intentionally not
    queued for later delivery. This prevents an LLM from draining stale VT
    repaint history minutes after the terminal has already become idle. }
  TTerminalObservationState = class
  private
    FScrollbackSeq: QWord;
    FLastScreen: UTF8String;
    FLastRawSeq: QWord;
    FLastScreenVersion: QWord;
    function LimitTail(const AText: UTF8String; AMaximumBytes: Cardinal;
      out AOmittedBytes: Cardinal): UTF8String;
  public
    constructor Create;
    function HasVisibleChanges(AScreen: TTerminalScreen): Boolean;
    function Capture(AScreen: TTerminalScreen; ARawEndSeq: QWord;
      AMaximumBytes: Cardinal): TTerminalObservationCapture;
    property LastScreenVersion: QWord read FLastScreenVersion;
  end;

implementation

constructor TTerminalObservationState.Create;
begin
  inherited Create;
  FScrollbackSeq := 0;
  FLastScreen := '';
  FLastRawSeq := 0;
  FLastScreenVersion := 0;
end;

function TTerminalObservationState.HasVisibleChanges(
  AScreen: TTerminalScreen): Boolean;
begin
  Result := (AScreen <> nil) and (AScreen.Version <> FLastScreenVersion);
end;

function TTerminalObservationState.LimitTail(const AText: UTF8String;
  AMaximumBytes: Cardinal; out AOmittedBytes: Cardinal): UTF8String;
var
  StartAt: SizeInt;
  Prefix: UTF8String;
begin
  AOmittedBytes := 0;
  if (AMaximumBytes = 0) or (Length(AText) <= SizeInt(AMaximumBytes)) then
    Exit(AText);

  AOmittedBytes := Cardinal(Length(AText) - SizeInt(AMaximumBytes));
  StartAt := Length(AText) - SizeInt(AMaximumBytes) + 1;
  { Do not begin in the middle of a UTF-8 continuation byte. }
  while (StartAt <= Length(AText)) and
    ((Byte(AText[StartAt]) and $C0) = $80) do
  begin
    Inc(StartAt);
    Inc(AOmittedBytes);
  end;
  Result := Copy(AText, StartAt, MaxInt);
  Prefix := UTF8String(Format(
    '[earlier rendered terminal content omitted: %d bytes]%s',
    [AOmittedBytes, LineEnding]));
  if Length(Prefix) + Length(Result) > SizeInt(AMaximumBytes) then
  begin
    if Length(Prefix) >= SizeInt(AMaximumBytes) then
      Result := Copy(Prefix, 1, AMaximumBytes)
    else
      Result := Prefix + Copy(Result,
        Length(Result) - (SizeInt(AMaximumBytes) - Length(Prefix)) + 1,
        MaxInt);
  end
  else
    Result := Prefix + Result;
end;

function TTerminalObservationState.Capture(AScreen: TTerminalScreen;
  ARawEndSeq: QWord; AMaximumBytes: Cardinal): TTerminalObservationCapture;
var
  History, Current: TStringList;
  ActualFrom, NextSeq: QWord;
  Missed: Boolean;
  Combined, CurrentText: UTF8String;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if AScreen = nil then Exit;

  Result.AlternateScreen := AScreen.AlternateActive;
  Result.RawBytesProcessed := ARawEndSeq;
  if ARawEndSeq >= FLastRawSeq then
    Result.RawBytesSinceLast := ARawEndSeq - FLastRawSeq
  else
    Result.RawBytesSinceLast := ARawEndSeq;
  Result.ScreenVersion := AScreen.Version;
  Result.Changed := AScreen.Version <> FLastScreenVersion;

  History := TStringList.Create;
  Current := TStringList.Create;
  try
    AScreen.GetCurrentLines(Current);
    CurrentText := UTF8String(Current.Text);
    while (Length(CurrentText) > 0) and
      ((CurrentText[Length(CurrentText)] = #10) or
       (CurrentText[Length(CurrentText)] = #13)) do
      Delete(CurrentText, Length(CurrentText), 1);

    Combined := '';
    if AScreen.AlternateActive then
    begin
      { Full-screen TUIs (top/htop/vim/less/etc.) are a current-state problem,
        not a transcript problem. Return the latest rendered screen snapshot. }
      if Result.Changed then
        Combined := CurrentText;
      Result.ScrollbackFromSeq := FScrollbackSeq;
      Result.ScrollbackNextSeq := AScreen.ScrollbackNextSeq;
    end
    else
    begin
      AScreen.GetScrollbackFrom(FScrollbackSeq, History,
        ActualFrom, NextSeq, Missed);
      Result.ScrollbackFromSeq := ActualFrom;
      Result.ScrollbackNextSeq := NextSeq;
      Result.ScrollbackMissed := Missed;

      for I := 0 to History.Count - 1 do
      begin
        if Combined <> '' then Combined := Combined + UTF8String(LineEnding);
        Combined := Combined + UTF8String(History[I]);
      end;

      { The current screen is appended only when it changed or new committed
        scrollback exists. This represents what a user can actually see now,
        while cursor-addressed repaints have already overwritten old cells. }
      if Result.Changed or (History.Count > 0) then
      begin
        if (Combined <> '') and (CurrentText <> '') then
          Combined := Combined + UTF8String(LineEnding);
        Combined := Combined + CurrentText;
      end;
    end;

    Result.Text := LimitTail(Combined, AMaximumBytes, Result.OmittedBytes);
    Result.RenderedBytes := Cardinal(Length(Result.Text));

    { Always coalesce to newest rendered state, even when the text returned
      above was size-limited. This is intentionally unlike raw terminal_read. }
    FScrollbackSeq := AScreen.ScrollbackNextSeq;
    FLastScreen := CurrentText;
    FLastRawSeq := ARawEndSeq;
    FLastScreenVersion := AScreen.Version;
  finally
    Current.Free;
    History.Free;
  end;
end;

end.
