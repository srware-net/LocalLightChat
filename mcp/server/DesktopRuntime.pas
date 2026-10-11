unit DesktopRuntime;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, DesktopBackend;

type
  TDesktopRuntime = class
  private
    FBackend: TDesktopBackend;
    FLock: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    function ListWindows(AArguments: TJSONObject): TJSONObject;
    function PerformWindowAction(AArguments: TJSONObject): TJSONObject;
    function Capture(AArguments: TJSONObject;
      AMaximumImageBytes: Cardinal): TDesktopCaptureResult;
    function SendInput(AArguments: TJSONObject): TJSONObject;
  end;

implementation

constructor TDesktopRuntime.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FBackend := CreateDesktopBackend;
end;

destructor TDesktopRuntime.Destroy;
begin
  FBackend.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TDesktopRuntime.ListWindows(AArguments: TJSONObject): TJSONObject;
begin
  EnterCriticalSection(FLock);
  try
    Result := FBackend.ListWindows(AArguments);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDesktopRuntime.PerformWindowAction(
  AArguments: TJSONObject): TJSONObject;
begin
  EnterCriticalSection(FLock);
  try
    Result := FBackend.PerformWindowAction(AArguments);
  finally
    LeaveCriticalSection(FLock);
  end;
end;


function TDesktopRuntime.Capture(AArguments: TJSONObject;
  AMaximumImageBytes: Cardinal): TDesktopCaptureResult;
begin
  EnterCriticalSection(FLock);
  try
    Result := FBackend.Capture(AArguments, AMaximumImageBytes);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDesktopRuntime.SendInput(AArguments: TJSONObject): TJSONObject;
begin
  EnterCriticalSection(FLock);
  try
    Result := FBackend.SendInput(AArguments);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
