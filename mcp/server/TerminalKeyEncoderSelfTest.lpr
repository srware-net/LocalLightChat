program TerminalKeyEncoderSelfTest;

{$mode objfpc}{$H+}

uses
  SysUtils, TerminalKeyEncoder;

procedure AssertBytes(const AName, AExpected, AActual: RawByteString);
begin
  if AExpected <> AActual then
    raise Exception.CreateFmt('%s failed: expected %d bytes, got %d bytes',
      [AName, Length(AExpected), Length(AActual)]);
end;

var
  K: TTerminalKeyEncoding;
begin
  K := EncodeTerminalKey('o', True, False, False, False);
  AssertBytes('Ctrl+O', #15, K.Bytes);

  K := EncodeTerminalKey('^X', False, False, False, False);
  AssertBytes('^X shorthand', #24, K.Bytes);

  K := EncodeTerminalKey('enter', False, False, False, False);
  AssertBytes('Enter', #13, K.Bytes);

  K := EncodeTerminalKey('up', False, False, False, False);
  AssertBytes('normal cursor up', #27'[A', K.Bytes);

  K := EncodeTerminalKey('up', False, False, False, True);
  AssertBytes('application cursor up', #27'OA', K.Bytes);

  K := EncodeTerminalKey('left', True, False, False, False);
  AssertBytes('Ctrl+Left', #27'[1;5D', K.Bytes);

  K := EncodeTerminalKey('tab', False, False, True, False);
  AssertBytes('Shift+Tab', #27'[Z', K.Bytes);

  K := EncodeTerminalKey('x', False, True, False, False);
  AssertBytes('Alt+X', #27'x', K.Bytes);

  WriteLn('TerminalKeyEncoder self-test OK');
end.
