unit TerminalKeyEncoder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TTerminalKeyEncoding = record
    Bytes: RawByteString;
    CanonicalKey: string;
    DisplayName: string;
    Ctrl: Boolean;
    Alt: Boolean;
    Shift: Boolean;
  end;

{ Encode one semantic terminal key into the bytes a PTY/ConPTY application
  expects.  This is intentionally independent of MCP, process management and
  desktop keyboard events.  A PTY receives bytes, not key-down/key-up events.

  AKey may be a named key (enter, escape, tab, up, F1, ...), one printable
  ASCII character, or the convenient shorthands Ctrl+O / ^O / M-x.  Explicit
  modifier booleans are preferred by the MCP tool. }
function EncodeTerminalKey(const AKey: string; ACtrl, AAlt, AShift,
  AApplicationCursorKeys: Boolean): TTerminalKeyEncoding;

implementation

function EscSequence(const ATail: RawByteString): RawByteString;
begin
  Result := #27;
  Result := Result + ATail;
end;

function ByteString(AByte: Byte): RawByteString;
begin
  SetLength(Result, 1);
  Result[1] := AnsiChar(AByte);
end;

function ModifierParameter(AShift, AAlt, ACtrl: Boolean): Integer;
begin
  Result := 1;
  if AShift then Inc(Result, 1);
  if AAlt then Inc(Result, 2);
  if ACtrl then Inc(Result, 4);
end;

function ShiftedAscii(AChar: AnsiChar): AnsiChar;
begin
  case AChar of
    'a'..'z': Result := UpCase(AChar);
    '1': Result := '!';
    '2': Result := '@';
    '3': Result := '#';
    '4': Result := '$';
    '5': Result := '%';
    '6': Result := '^';
    '7': Result := '&';
    '8': Result := '*';
    '9': Result := '(';
    '0': Result := ')';
    '`': Result := '~';
    '-': Result := '_';
    '=': Result := '+';
    '[': Result := '{';
    ']': Result := '}';
    '\': Result := '|';
    ';': Result := ':';
    '''': Result := '"';
    ',': Result := '<';
    '.': Result := '>';
    '/': Result := '?';
  else
    Result := AChar;
  end;
end;

function ControlByte(AChar: AnsiChar; out AByte: Byte): Boolean;
var
  U: AnsiChar;
begin
  Result := True;
  U := UpCase(AChar);
  if U in ['A'..'Z'] then
  begin
    AByte := Ord(U) - Ord('A') + 1;
    Exit;
  end;

  case AChar of
    ' ', '@', '2': AByte := 0;
    '[', '3': AByte := 27;
    '\', '4': AByte := 28;
    ']', '5': AByte := 29;
    '^', '6': AByte := 30;
    '_', '7': AByte := 31;
    '?', '8': AByte := 127;
  else
    Result := False;
  end;
end;

procedure ParseEmbeddedModifiers(const AOriginal: string; var AKey: string;
  var ACtrl, AAlt, AShift: Boolean);
var
  Work, Token: string;
  Parts: TStringList;
  I: Integer;
begin
  Work := Trim(AOriginal);
  if Work = '' then
    raise Exception.Create('key must not be empty');

  { Nano and many other TUIs display control shortcuts as ^O and meta/alt
    shortcuts as M-U. Accept those notations because they are often literally
    visible on the rendered screen. }
  if (Length(Work) = 2) and (Work[1] = '^') then
  begin
    ACtrl := True;
    AKey := Work[2];
    Exit;
  end;
  if (Length(Work) >= 3) and (LowerCase(Copy(Work, 1, 2)) = 'm-') then
  begin
    AAlt := True;
    AKey := Copy(Work, 3, MaxInt);
    Exit;
  end;

  { Also accept Ctrl+O / Alt+X / Ctrl+Shift+Left. The explicit JSON boolean
    modifiers remain the canonical MCP form, but accepting this notation keeps
    terminal_key robust when an agent copies a shortcut as one string. }
  if (Work <> '+') and (Pos('+', Work) > 0) then
  begin
    Parts := TStringList.Create;
    try
      Parts.StrictDelimiter := True;
      Parts.Delimiter := '+';
      Parts.DelimitedText := Work;
      if Parts.Count < 2 then
      begin
        AKey := Work;
        Exit;
      end;
      for I := 0 to Parts.Count - 2 do
      begin
        Token := LowerCase(Trim(Parts[I]));
        if (Token = 'ctrl') or (Token = 'control') then
          ACtrl := True
        else if (Token = 'alt') or (Token = 'meta') then
          AAlt := True
        else if Token = 'shift' then
          AShift := True
        else
          raise Exception.CreateFmt('Unknown terminal key modifier: %s',
            [Parts[I]]);
      end;
      AKey := Trim(Parts[Parts.Count - 1]);
      if AKey = '' then
        raise Exception.Create('terminal key after modifiers must not be empty');
      Exit;
    finally
      Parts.Free;
    end;
  end;

  AKey := Work;
end;

function NormalizeNamedKey(const AKey: string): string;
var
  K: string;
begin
  K := LowerCase(Trim(AKey));
  if K = 'return' then K := 'enter'
  else if K = 'esc' then K := 'escape'
  else if K = 'spacebar' then K := 'space'
  else if K = 'bs' then K := 'backspace'
  else if K = 'del' then K := 'delete'
  else if K = 'ins' then K := 'insert'
  else if (K = 'pgup') or (K = 'page_up') or (K = 'page-up') then K := 'pageup'
  else if (K = 'pgdn') or (K = 'pagedown') or (K = 'page_down') or
          (K = 'page-down') then K := 'pagedown'
  else if (K = 'arrowup') or (K = 'arrow_up') then K := 'up'
  else if (K = 'arrowdown') or (K = 'arrow_down') then K := 'down'
  else if (K = 'arrowleft') or (K = 'arrow_left') then K := 'left'
  else if (K = 'arrowright') or (K = 'arrow_right') then K := 'right';
  Result := K;
end;

function DisplayKeyName(const ACanonical: string): string;
begin
  if Length(ACanonical) = 1 then
    Result := UpperCase(ACanonical)
  else if Copy(ACanonical, 1, 1) = 'f' then
    Result := UpperCase(ACanonical)
  else if ACanonical = 'pageup' then
    Result := 'PageUp'
  else if ACanonical = 'pagedown' then
    Result := 'PageDown'
  else
    Result := UpperCase(Copy(ACanonical, 1, 1)) +
      Copy(ACanonical, 2, MaxInt);
end;

function MakeDisplayName(const ACanonical: string; ACtrl, AAlt,
  AShift: Boolean): string;
begin
  Result := '';
  if ACtrl then Result := Result + 'Ctrl+';
  if AAlt then Result := Result + 'Alt+';
  if AShift then Result := Result + 'Shift+';
  Result := Result + DisplayKeyName(ACanonical);
end;

function EncodePrintable(const AKey: string; ACtrl, AAlt,
  AShift: Boolean): RawByteString;
var
  C: AnsiChar;
  B: Byte;
  Payload: RawByteString;
begin
  if AKey = 'space' then
    C := ' '
  else
  begin
    if Length(AKey) <> 1 then
      raise Exception.Create(
        'Printable terminal_key values must be one ASCII character; use terminal_write for text');
    C := AnsiChar(AKey[1]);
    if (Ord(C) < 32) or (Ord(C) > 126) then
      raise Exception.Create(
        'terminal_key supports printable ASCII characters; use terminal_write for UTF-8 text');
  end;

  if AShift and (not ACtrl) then
    C := ShiftedAscii(C)
  else if AShift and ACtrl then
    C := ShiftedAscii(C);

  if ACtrl then
  begin
    if not ControlByte(C, B) then
      raise Exception.CreateFmt('Ctrl+%s has no portable VT control-byte encoding',
        [AKey]);
    Payload := ByteString(B);
  end
  else
    Payload := ByteString(Ord(C));

  if AAlt then
    Result := EscSequence(Payload)
  else
    Result := Payload;
end;

function EncodeCursorKey(const AFinal: AnsiChar; ACtrl, AAlt, AShift,
  AApplicationCursorKeys: Boolean): RawByteString;
var
  M: Integer;
  FinalText: RawByteString;
begin
  FinalText := ByteString(Ord(AFinal));
  if not (ACtrl or AAlt or AShift) then
  begin
    if AApplicationCursorKeys then
      Result := EscSequence('O' + FinalText)
    else
      Result := EscSequence('[' + FinalText);
    Exit;
  end;
  M := ModifierParameter(AShift, AAlt, ACtrl);
  Result := EscSequence('[1;' + RawByteString(IntToStr(M)) + FinalText);
end;

function EncodeTildeKey(ANumber: Integer; ACtrl, AAlt,
  AShift: Boolean): RawByteString;
var
  M: Integer;
begin
  if not (ACtrl or AAlt or AShift) then
    Result := EscSequence('[' + RawByteString(IntToStr(ANumber)) + '~')
  else
  begin
    M := ModifierParameter(AShift, AAlt, ACtrl);
    Result := EscSequence('[' + RawByteString(IntToStr(ANumber)) + ';' +
      RawByteString(IntToStr(M)) + '~');
  end;
end;

function FunctionKeyNumber(AFunction: Integer): Integer;
begin
  case AFunction of
    5: Result := 15;
    6: Result := 17;
    7: Result := 18;
    8: Result := 19;
    9: Result := 20;
    10: Result := 21;
    11: Result := 23;
    12: Result := 24;
    13: Result := 25;
    14: Result := 26;
    15: Result := 28;
    16: Result := 29;
    17: Result := 31;
    18: Result := 32;
    19: Result := 33;
    20: Result := 34;
    21: Result := 42;
    22: Result := 43;
    23: Result := 44;
    24: Result := 45;
  else
    Result := 0;
  end;
end;

function EncodeFunctionKey(AFunction: Integer; ACtrl, AAlt,
  AShift: Boolean): RawByteString;
var
  Final: AnsiChar;
  FinalText: RawByteString;
  M, N: Integer;
begin
  if (AFunction >= 1) and (AFunction <= 4) then
  begin
    case AFunction of
      1: Final := 'P';
      2: Final := 'Q';
      3: Final := 'R';
    else
      Final := 'S';
    end;
    FinalText := ByteString(Ord(Final));
    if not (ACtrl or AAlt or AShift) then
      Result := EscSequence('O' + FinalText)
    else
    begin
      M := ModifierParameter(AShift, AAlt, ACtrl);
      Result := EscSequence('[1;' + RawByteString(IntToStr(M)) + FinalText);
    end;
    Exit;
  end;

  N := FunctionKeyNumber(AFunction);
  if N = 0 then
    raise Exception.Create('Function key must be F1 through F24');
  Result := EncodeTildeKey(N, ACtrl, AAlt, AShift);
end;

function EncodeTerminalKey(const AKey: string; ACtrl, AAlt, AShift,
  AApplicationCursorKeys: Boolean): TTerminalKeyEncoding;
var
  Key, Normalized: string;
  FunctionNumber: Integer;
  Tail: RawByteString;
begin
  Result.Bytes := '';
  Result.CanonicalKey := '';
  Result.DisplayName := '';
  Result.Ctrl := False;
  Result.Alt := False;
  Result.Shift := False;
  Key := AKey;
  ParseEmbeddedModifiers(AKey, Key, ACtrl, AAlt, AShift);
  Normalized := NormalizeNamedKey(Key);
  if Normalized = '' then
    raise Exception.Create('key must not be empty');

  if (Normalized = 'ctrl') or (Normalized = 'control') or
     (Normalized = 'alt') or (Normalized = 'meta') or
     (Normalized = 'shift') then
    raise Exception.Create(
      'PTY terminals do not expose modifier key-down/key-up events; combine the modifier with another key, e.g. key="o", ctrl=true');

  Result.CanonicalKey := Normalized;
  Result.Ctrl := ACtrl;
  Result.Alt := AAlt;
  Result.Shift := AShift;
  Result.DisplayName := MakeDisplayName(Normalized, ACtrl, AAlt, AShift);

  if (Length(Normalized) >= 2) and (Normalized[1] = 'f') and
     TryStrToInt(Copy(Normalized, 2, MaxInt), FunctionNumber) then
  begin
    if (FunctionNumber < 1) or (FunctionNumber > 24) then
      raise Exception.Create('Function key must be F1 through F24');
    Result.Bytes := EncodeFunctionKey(FunctionNumber, ACtrl, AAlt, AShift);
    Exit;
  end;

  if Normalized = 'enter' then
  begin
    if ACtrl or AShift then
      raise Exception.Create(
        'Ctrl/Shift+Enter is not portably distinguishable in a classic VT stream; use plain enter');
    Tail := #13;
    if AAlt then Result.Bytes := EscSequence(Tail) else Result.Bytes := Tail;
    Exit;
  end;

  if Normalized = 'escape' then
  begin
    if ACtrl or AShift then
      raise Exception.Create(
        'Ctrl/Shift+Escape is not portably distinguishable in a classic VT stream; use plain escape');
    Result.Bytes := #27;
    if AAlt then Result.Bytes := EscSequence(Result.Bytes);
    Exit;
  end;

  if Normalized = 'tab' then
  begin
    if ACtrl then
      raise Exception.Create(
        'Ctrl+Tab has no portable classic-VT encoding');
    if AShift then
      Tail := EscSequence('[Z')
    else
      Tail := #9;
    if AAlt then Result.Bytes := EscSequence(Tail) else Result.Bytes := Tail;
    Exit;
  end;

  if Normalized = 'backspace' then
  begin
    if ACtrl or AShift then
      raise Exception.Create(
        'Ctrl/Shift+Backspace has no portable classic-VT encoding');
    Tail := ByteString(127);
    if AAlt then Result.Bytes := EscSequence(Tail) else Result.Bytes := Tail;
    Exit;
  end;

  if Normalized = 'up' then
    Result.Bytes := EncodeCursorKey('A', ACtrl, AAlt, AShift,
      AApplicationCursorKeys)
  else if Normalized = 'down' then
    Result.Bytes := EncodeCursorKey('B', ACtrl, AAlt, AShift,
      AApplicationCursorKeys)
  else if Normalized = 'right' then
    Result.Bytes := EncodeCursorKey('C', ACtrl, AAlt, AShift,
      AApplicationCursorKeys)
  else if Normalized = 'left' then
    Result.Bytes := EncodeCursorKey('D', ACtrl, AAlt, AShift,
      AApplicationCursorKeys)
  else if Normalized = 'home' then
    Result.Bytes := EncodeCursorKey('H', ACtrl, AAlt, AShift,
      AApplicationCursorKeys)
  else if Normalized = 'end' then
    Result.Bytes := EncodeCursorKey('F', ACtrl, AAlt, AShift,
      AApplicationCursorKeys)
  else if Normalized = 'insert' then
    Result.Bytes := EncodeTildeKey(2, ACtrl, AAlt, AShift)
  else if Normalized = 'delete' then
    Result.Bytes := EncodeTildeKey(3, ACtrl, AAlt, AShift)
  else if Normalized = 'pageup' then
    Result.Bytes := EncodeTildeKey(5, ACtrl, AAlt, AShift)
  else if Normalized = 'pagedown' then
    Result.Bytes := EncodeTildeKey(6, ACtrl, AAlt, AShift)
  else
  begin
    { Printable ASCII, including space. }
    if Normalized = 'space' then
      Result.Bytes := EncodePrintable('space', ACtrl, AAlt, AShift)
    else if Length(Key) = 1 then
    begin
      { Preserve the caller's original printable character case. Named keys
        are normalized; literal characters are not. }
      Result.CanonicalKey := Key;
      Result.DisplayName := MakeDisplayName(Key, ACtrl, AAlt, AShift);
      Result.Bytes := EncodePrintable(Key, ACtrl, AAlt, AShift);
    end
    else
      raise Exception.CreateFmt('Unsupported terminal key: %s', [AKey]);
  end;

  if Result.Bytes = '' then
    raise Exception.CreateFmt('Could not encode terminal key %s', [AKey]);
end;

end.
