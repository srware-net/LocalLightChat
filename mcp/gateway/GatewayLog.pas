unit GatewayLog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  TGatewayLogLevel = (gllNone, gllInfo, gllDebug);

  TGatewayLogger = class
  private
    FLevel: TGatewayLogLevel;
    FLock: TCriticalSection;
    FLogFileName: string;
    FLogStream: TFileStream;
    procedure WriteLine(const APrefix, AMessage: string);
  public
    constructor Create(ALevel: TGatewayLogLevel; const ALogFileName: string = '');
    destructor Destroy; override;
    procedure Info(const AMessage: string);
    procedure Debug(const AMessage: string);
    procedure Error(const AMessage: string);
    property Level: TGatewayLogLevel read FLevel write FLevel;
  end;

function ParseGatewayLogLevel(const AValue: string): TGatewayLogLevel;
function GatewayLogLevelName(AValue: TGatewayLogLevel): string;

implementation

function ParseGatewayLogLevel(const AValue: string): TGatewayLogLevel;
begin
  if SameText(Trim(AValue), 'none') or SameText(Trim(AValue), 'quiet') then
    Exit(gllNone);
  if SameText(Trim(AValue), 'debug') then
    Exit(gllDebug);
  Result := gllInfo;
end;

function GatewayLogLevelName(AValue: TGatewayLogLevel): string;
begin
  case AValue of
    gllNone: Result := 'none';
    gllDebug: Result := 'debug';
  else
    Result := 'info';
  end;
end;

constructor TGatewayLogger.Create(ALevel: TGatewayLogLevel;
  const ALogFileName: string);
begin
  inherited Create;
  FLevel := ALevel;
  FLock := TCriticalSection.Create;
  FLogFileName := Trim(ALogFileName);
  FLogStream := nil;
  if FLogFileName <> '' then
  begin
    ForceDirectories(ExtractFileDir(ExpandFileName(FLogFileName)));
    if FileExists(FLogFileName) then
      FLogStream := TFileStream.Create(FLogFileName, fmOpenReadWrite or fmShareDenyNone)
    else
      FLogStream := TFileStream.Create(FLogFileName, fmCreate or fmShareDenyNone);
    FLogStream.Position := FLogStream.Size;
  end;
end;

destructor TGatewayLogger.Destroy;
begin
  FLogStream.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TGatewayLogger.WriteLine(const APrefix, AMessage: string);
var
  Line: UTF8String;
begin
  Line := UTF8Encode(FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
    ' [' + APrefix + '] ' + AMessage + LineEnding);
  FLock.Acquire;
  try
    Write(UTF8Decode(Line));
    Flush(Output);
    if FLogStream <> nil then
      FLogStream.WriteBuffer(Line[1], Length(Line));
  finally
    FLock.Release;
  end;
end;

procedure TGatewayLogger.Info(const AMessage: string);
begin
  if FLevel >= gllInfo then
    WriteLine('info', AMessage);
end;

procedure TGatewayLogger.Debug(const AMessage: string);
begin
  if FLevel >= gllDebug then
    WriteLine('debug', AMessage);
end;

procedure TGatewayLogger.Error(const AMessage: string);
begin
  if FLevel <> gllNone then
    WriteLine('error', AMessage);
end;

end.
