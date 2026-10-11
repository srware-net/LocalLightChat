unit TerminalVTParser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TerminalScreen;

type
  TVTParserState = (vpsGround, vpsEscape, vpsEscapeIntermediate,
    vpsCsi, vpsOsc, vpsOscEscape);

  { Minimal general-purpose VT100/xterm parser for agent observation. It is
    intentionally independent of MCP and process semantics. Unsupported VT
    sequences are ignored rather than leaked as visible text. }
  TTerminalVTParser = class
  private
    FScreen: TTerminalScreen;
    FState: TVTParserState;
    FCsi: RawByteString;
    FOsc: RawByteString;
    FUtf8Pending: RawByteString;
    FUtf8Expected: Integer;
    procedure ProcessGroundByte(B: Byte);
    procedure ProcessPrintableByte(B: Byte);
    procedure FlushUtf8Pending(AForceReplacement: Boolean);
    procedure DispatchEscape(B: Byte);
    procedure DispatchCsi(AFinal: Char);
    function CsiPrivatePrefix(out AParams: string): Char;
    procedure ParseParams(const AText: string; AValues: TList);
    function Param(AValues: TList; AIndex, ADefault: Integer): Integer;
    procedure HandlePrivateMode(ASet: Boolean; AValues: TList);
  public
    constructor Create(AScreen: TTerminalScreen);
    procedure Reset;
    procedure Feed(const AData: RawByteString);
  end;

implementation

type
  PIntegerValue = ^Integer;

constructor TTerminalVTParser.Create(AScreen: TTerminalScreen);
begin
  inherited Create;
  FScreen := AScreen;
  Reset;
end;

procedure TTerminalVTParser.Reset;
begin
  FState := vpsGround;
  FCsi := '';
  FOsc := '';
  FUtf8Pending := '';
  FUtf8Expected := 0;
end;

procedure TTerminalVTParser.FlushUtf8Pending(AForceReplacement: Boolean);
var
  U: UnicodeString;
begin
  if FUtf8Pending = '' then Exit;
  if (Length(FUtf8Pending) >= FUtf8Expected) and (FUtf8Expected > 0) then
  begin
    U := UTF8Decode(UTF8String(FUtf8Pending));
    if Length(U) > 0 then
      FScreen.PutChar(U[1])
    else
      FScreen.PutChar('?');
  end
  else if AForceReplacement then
    FScreen.PutChar('?');
  FUtf8Pending := '';
  FUtf8Expected := 0;
end;

procedure TTerminalVTParser.ProcessPrintableByte(B: Byte);
begin
  if FUtf8Expected > 0 then
  begin
    if (B and $C0) = $80 then
    begin
      FUtf8Pending := FUtf8Pending + AnsiChar(B);
      if Length(FUtf8Pending) >= FUtf8Expected then
        FlushUtf8Pending(False);
      Exit;
    end;
    FlushUtf8Pending(True);
  end;

  if B < $80 then
  begin
    FScreen.PutChar(WideChar(B));
    Exit;
  end;

  if (B and $E0) = $C0 then FUtf8Expected := 2
  else if (B and $F0) = $E0 then FUtf8Expected := 3
  else if (B and $F8) = $F0 then FUtf8Expected := 4
  else
  begin
    FScreen.PutChar('?');
    Exit;
  end;
  FUtf8Pending := AnsiChar(B);
end;

procedure TTerminalVTParser.ProcessGroundByte(B: Byte);
begin
  case B of
    $00: ;
    $07: ; { BEL }
    $08: begin FlushUtf8Pending(True); FScreen.Backspace; end;
    $09: begin FlushUtf8Pending(True); FScreen.Tab; end;
    $0A, $0B, $0C: begin FlushUtf8Pending(True); FScreen.LineFeed; end;
    $0D: begin FlushUtf8Pending(True); FScreen.CarriageReturn; end;
    $1B:
      begin
        FlushUtf8Pending(True);
        FState := vpsEscape;
      end;
  else
    if B >= $20 then
      ProcessPrintableByte(B);
  end;
end;

procedure TTerminalVTParser.DispatchEscape(B: Byte);
begin
  case Char(B) of
    '[':
      begin
        FCsi := '';
        FState := vpsCsi;
      end;
    ']':
      begin
        FOsc := '';
        FState := vpsOsc;
      end;
    '7': begin FScreen.SaveCursor; FState := vpsGround; end;
    '8': begin FScreen.RestoreCursor; FState := vpsGround; end;
    'D': begin FScreen.LineFeed; FState := vpsGround; end; { IND }
    'E': begin FScreen.NextLine; FState := vpsGround; end; { NEL }
    'M': begin FScreen.ReverseIndex; FState := vpsGround; end; { RI }
    'c': begin FScreen.Reset; Reset; end; { RIS }
    '(', ')', '*', '+', '-', '.', '/', '#':
      FState := vpsEscapeIntermediate;
  else
    FState := vpsGround;
  end;
end;

function TTerminalVTParser.CsiPrivatePrefix(out AParams: string): Char;
begin
  Result := #0;
  AParams := string(FCsi);
  if (AParams <> '') and (AParams[1] in ['?', '>', '!', '=']) then
  begin
    Result := AParams[1];
    Delete(AParams, 1, 1);
  end;
end;

procedure TTerminalVTParser.ParseParams(const AText: string; AValues: TList);
var
  Parts: TStringList;
  I, V: Integer;
  P: PIntegerValue;
begin
  AValues.Clear;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ';';
    Parts.DelimitedText := AText;
    if AText = '' then
      Parts.Add('');
    for I := 0 to Parts.Count - 1 do
    begin
      New(P);
      if Parts[I] = '' then
        V := 0
      else if not TryStrToInt(Parts[I], V) then
        V := 0;
      P^ := V;
      AValues.Add(P);
    end;
  finally
    Parts.Free;
  end;
end;

function TTerminalVTParser.Param(AValues: TList; AIndex,
  ADefault: Integer): Integer;
var
  P: PIntegerValue;
begin
  if (AIndex < 0) or (AIndex >= AValues.Count) then Exit(ADefault);
  P := PIntegerValue(AValues[AIndex]);
  if (P = nil) or (P^ = 0) then Result := ADefault else Result := P^;
end;

procedure TTerminalVTParser.HandlePrivateMode(ASet: Boolean; AValues: TList);
var
  I, Mode: Integer;
  P: PIntegerValue;
begin
  for I := 0 to AValues.Count - 1 do
  begin
    P := PIntegerValue(AValues[I]);
    if P = nil then Continue;
    Mode := P^;
    case Mode of
      1:
        FScreen.SetApplicationCursorKeys(ASet);
      47, 1047:
        FScreen.SetAlternateScreen(ASet, ASet);
      1049:
        begin
          if ASet then FScreen.SaveCursor;
          FScreen.SetAlternateScreen(ASet, ASet);
          if not ASet then FScreen.RestoreCursor;
        end;
      { ?25 cursor visibility, ?2004 bracketed paste, mouse reporting and
        other private modes do not affect the textual screen model. DECCKM ?1
        is tracked because it changes the byte sequence expected for cursor
        key input. }
    end;
  end;
end;

procedure TTerminalVTParser.DispatchCsi(AFinal: Char);
var
  ParamsText: string;
  PrivatePrefix: Char;
  Values: TList;
  I: Integer;
  P: PIntegerValue;
begin
  Values := TList.Create;
  try
    PrivatePrefix := CsiPrivatePrefix(ParamsText);
    ParseParams(ParamsText, Values);
    case AFinal of
      'A': FScreen.CursorUp(Param(Values, 0, 1));
      'B': FScreen.CursorDown(Param(Values, 0, 1));
      'C': FScreen.CursorForward(Param(Values, 0, 1));
      'D': FScreen.CursorBackward(Param(Values, 0, 1));
      'E': FScreen.CursorNextLine(Param(Values, 0, 1));
      'F': FScreen.CursorPreviousLine(Param(Values, 0, 1));
      'G', '`': FScreen.CursorHorizontalAbsolute(Param(Values, 0, 1));
      'd': FScreen.CursorVerticalAbsolute(Param(Values, 0, 1));
      'H', 'f': FScreen.CursorPosition(Param(Values, 0, 1), Param(Values, 1, 1));
      'J': FScreen.EraseInDisplay(Param(Values, 0, 0));
      'K': FScreen.EraseInLine(Param(Values, 0, 0));
      'X': FScreen.EraseCharacters(Param(Values, 0, 1));
      '@': FScreen.InsertCharacters(Param(Values, 0, 1));
      'P': FScreen.DeleteCharacters(Param(Values, 0, 1));
      'L': FScreen.InsertLines(Param(Values, 0, 1));
      'M': FScreen.DeleteLines(Param(Values, 0, 1));
      'S': FScreen.ScrollUp(Param(Values, 0, 1));
      'T': FScreen.ScrollDown(Param(Values, 0, 1));
      'r': FScreen.SetScrollRegion(Param(Values, 0, 1), Param(Values, 1, FScreen.Rows));
      's': FScreen.SaveCursor;
      'u': FScreen.RestoreCursor;
      'h': if PrivatePrefix = '?' then HandlePrivateMode(True, Values);
      'l': if PrivatePrefix = '?' then HandlePrivateMode(False, Values);
      'm': ; { SGR attributes do not change textual content. }
      { Device status reports, terminal parameters and mouse modes are output
        protocol details; they are intentionally ignored by the screen model. }
    end;
  finally
    for I := 0 to Values.Count - 1 do
    begin
      P := PIntegerValue(Values[I]);
      Dispose(P);
    end;
    Values.Free;
  end;
end;

procedure TTerminalVTParser.Feed(const AData: RawByteString);
var
  I: SizeInt;
  B: Byte;
begin
  for I := 1 to Length(AData) do
  begin
    B := Byte(AData[I]);
    case FState of
      vpsGround:
        ProcessGroundByte(B);
      vpsEscape:
        DispatchEscape(B);
      vpsEscapeIntermediate:
        FState := vpsGround;
      vpsCsi:
        begin
          if (B >= $40) and (B <= $7E) then
          begin
            DispatchCsi(Char(B));
            FCsi := '';
            FState := vpsGround;
          end
          else if B = $1B then
          begin
            FCsi := '';
            FState := vpsEscape;
          end
          else if Length(FCsi) < 512 then
            FCsi := FCsi + AnsiChar(B);
        end;
      vpsOsc:
        begin
          if B = $07 then
          begin
            FOsc := '';
            FState := vpsGround;
          end
          else if B = $1B then
            FState := vpsOscEscape
          else if Length(FOsc) < 4096 then
            FOsc := FOsc + AnsiChar(B);
        end;
      vpsOscEscape:
        begin
          if Char(B) = '\' then
          begin
            FOsc := '';
            FState := vpsGround;
          end
          else if B = $1B then
            FState := vpsOscEscape
          else
            FState := vpsOsc;
        end;
    end;
  end;
end;

end.
