unit DesktopBackend;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

type
  TDesktopCaptureResult = record
    MimeType: string;
    Data: TBytes;
    Width: Integer;
    Height: Integer;
    SourceX: Integer;
    SourceY: Integer;
    SourceWidth: Integer;
    SourceHeight: Integer;
    Quality: Integer;
    WindowHandle: QWord;
    WindowTitle: string;
    CaptureMethod: string;
  end;

  TDesktopBackend = class
  public
    function ListWindows(AArguments: TJSONObject): TJSONObject; virtual; abstract;
    function PerformWindowAction(AArguments: TJSONObject): TJSONObject; virtual; abstract;
    function Capture(AArguments: TJSONObject;
      AMaximumImageBytes: Cardinal): TDesktopCaptureResult; virtual; abstract;
    function SendInput(AArguments: TJSONObject): TJSONObject; virtual; abstract;
  end;

function CreateDesktopBackend: TDesktopBackend;

implementation

{$IFDEF WINDOWS}
uses
  WindowsDesktopBackend;
{$ENDIF}

type
  TUnavailableDesktopBackend = class(TDesktopBackend)
  public
    function ListWindows(AArguments: TJSONObject): TJSONObject; override;
    function PerformWindowAction(AArguments: TJSONObject): TJSONObject; override;
    function Capture(AArguments: TJSONObject;
      AMaximumImageBytes: Cardinal): TDesktopCaptureResult; override;
    function SendInput(AArguments: TJSONObject): TJSONObject; override;
  end;

function TUnavailableDesktopBackend.ListWindows(
  AArguments: TJSONObject): TJSONObject;
begin
  Result := nil;
  raise Exception.Create('Desktop window control is not implemented on this platform yet');
end;

function TUnavailableDesktopBackend.PerformWindowAction(
  AArguments: TJSONObject): TJSONObject;
begin
  Result := nil;
  raise Exception.Create('Desktop window control is not implemented on this platform yet');
end;


function TUnavailableDesktopBackend.Capture(AArguments: TJSONObject;
  AMaximumImageBytes: Cardinal): TDesktopCaptureResult;
begin
  Result.MimeType := '';
  SetLength(Result.Data, 0);
  Result.Width := 0;
  Result.Height := 0;
  Result.SourceX := 0;
  Result.SourceY := 0;
  Result.SourceWidth := 0;
  Result.SourceHeight := 0;
  Result.Quality := 0;
  Result.WindowHandle := 0;
  Result.WindowTitle := '';
  Result.CaptureMethod := '';
  raise Exception.Create('Desktop capture is not implemented on this platform yet');
end;

function TUnavailableDesktopBackend.SendInput(
  AArguments: TJSONObject): TJSONObject;
begin
  Result := nil;
  raise Exception.Create('Desktop input is not implemented on this platform yet');
end;

function CreateDesktopBackend: TDesktopBackend;
begin
  {$IFDEF WINDOWS}
  Result := TWindowsDesktopBackend.Create;
  {$ELSE}
  Result := TUnavailableDesktopBackend.Create;
  {$ENDIF}
end;

end.
