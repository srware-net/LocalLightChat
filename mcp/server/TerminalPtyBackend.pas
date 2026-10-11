unit TerminalPtyBackend;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TTerminalSignal = (tsInterrupt, tsEof, tsTerminate, tsKill);

  { Platform-neutral PTY/ConPTY contract. The higher-level terminal session
    manager deliberately does not know whether it is talking to a Unix PTY
    master or a Windows pseudoconsole. }
  TTerminalPtyBackend = class
  protected
    FProcessId: Integer;
    FExitCode: Integer;
    FExited: Boolean;
  public
    constructor Create; virtual;
    procedure Start(const AExecutable: string; AArguments: TStrings;
      const AWorkingDirectory: string; AColumns, ARows: Word); virtual; abstract;
    function ReadAvailable(out AData: RawByteString;
      AMaximumBytes: Cardinal): Integer; virtual; abstract;
    function WriteData(const AData: RawByteString): Integer; virtual; abstract;
    procedure Resize(AColumns, ARows: Word); virtual; abstract;
    procedure SendSignal(ASignal: TTerminalSignal); virtual; abstract;
    function PollRunning: Boolean; virtual; abstract;
    procedure Close; virtual; abstract;
    property ProcessId: Integer read FProcessId;
    property ExitCode: Integer read FExitCode;
    property Exited: Boolean read FExited;
  end;

implementation

constructor TTerminalPtyBackend.Create;
begin
  inherited Create;
  FProcessId := 0;
  FExitCode := 0;
  FExited := False;
end;

end.
