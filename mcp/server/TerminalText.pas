unit TerminalText;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function TerminalOutputForMcpText(const AText: RawByteString): string;
function TerminalInputForMcpText(const AText: RawByteString): string;

implementation

type
  TAnsiState = (asText, asEscape, asCsi, asOsc, asOscEscape,
    asEscapeIntermediate);

function NormalizeNewLines(const AText: string): string;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function StripAnsi(const AText: RawByteString): RawByteString;
var
  I: SizeInt;
  B: Byte;
  State: TAnsiState;
begin
  Result := '';
  State := asText;
  I := 1;
  while I <= Length(AText) do
  begin
    B := Byte(AText[I]);
    case State of
      asText:
        begin
          if B = $1B then
            State := asEscape
          else if (B = $09) or (B = $0A) or (B = $0D) or (B >= $20) then
            Result := Result + AText[I];
        end;
      asEscape:
        begin
          case Char(B) of
            '[': State := asCsi;
            ']': State := asOsc;
            '(', ')', '*', '+', '-', '.', '/', '#':
              State := asEscapeIntermediate;
          else
            { Most two-byte ESC sequences end here. }
            State := asText;
          end;
        end;
      asEscapeIntermediate:
        State := asText;
      asCsi:
        begin
          { ECMA-48 CSI final bytes are 0x40..0x7e. }
          if (B >= $40) and (B <= $7E) then
            State := asText;
        end;
      asOsc:
        begin
          if B = $07 then
            State := asText
          else if B = $1B then
            State := asOscEscape;
        end;
      asOscEscape:
        begin
          if Char(B) = '\' then
            State := asText
          else if B <> $1B then
            State := asOsc;
        end;
    end;
    Inc(I);
  end;
end;

function TerminalOutputForMcpText(const AText: RawByteString): string;
begin
  Result := NormalizeNewLines(string(StripAnsi(AText)));
end;

function TerminalInputForMcpText(const AText: RawByteString): string;
begin
  Result := NormalizeNewLines(string(AText));
end;

end.
