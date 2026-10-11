unit TerminalInput;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ Builds the exact byte sequence passed to the PTY.  APressEnter deliberately
  appends a carriage return instead of asking MCP clients/LLMs to encode a
  newline escape correctly inside a JSON string.  CR is the canonical Enter
  key representation expected by ConPTY and is translated to NL by ordinary
  Unix terminal input modes (ICRNL).  Existing callers may still place actual
  CR/LF bytes in AData; they are preserved byte-for-byte. Control, navigation and function keys belong to TerminalKeyEncoder/terminal_key instead of being encoded as text escapes here. }
function BuildTerminalInput(const AData: UTF8String;
  APressEnter: Boolean): RawByteString;

implementation

function BuildTerminalInput(const AData: UTF8String;
  APressEnter: Boolean): RawByteString;
begin
  Result := RawByteString(AData);
  if APressEnter then
    Result := Result + #13;
end;

end.
