unit uBranding;

{$mode objfpc}{$H+}

interface

uses ExtCtrls;

procedure LoadEmbeddedLLCLogo(AImage: TImage);

implementation

uses Classes, SysUtils, LCLType;

const
  LogoSizes: array[0..7] of Integer = (52, 65, 78, 91, 104, 117, 130, 156);

procedure LoadEmbeddedLLCLogo(AImage: TImage);
var
  I, Nearest, Desired: Integer;
  Stream: TResourceStream;
  ResourceName: string;
begin
  // Resource sizes are pre-rendered with Lanczos filtering. Pick nearest
  // native resolution for the actual display size: no jagged runtime shrink
  // from a giant 256/1024 pixel PNG to the control's 52 pixel bounds.
  Desired := AImage.Width;
  Nearest := 0;
  for I := Low(LogoSizes) to High(LogoSizes) do
    if Abs(LogoSizes[I] - Desired) < Abs(LogoSizes[Nearest] - Desired) then
      Nearest := I;

  ResourceName := 'LLC_LOGO_' + IntToStr(LogoSizes[Nearest]);
  Stream := TResourceStream.Create(HInstance, ResourceName, RT_RCDATA);
  try
    AImage.Picture.PNG.LoadFromStream(Stream);
    AImage.Stretch := LogoSizes[Nearest] <> Desired;
    AImage.Center := True;
    AImage.Proportional := True;
  finally
    Stream.Free;
  end;
end;

end.
