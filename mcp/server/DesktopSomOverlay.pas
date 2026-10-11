unit DesktopSomOverlay;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson;

function RenderSomOverlay(const AImageData: TBytes; ATargets: TJSONArray): TBytes;

implementation

uses
  FPImage, FPReadPNG, FPWritePNG, McpJson;

const
  DigitRows: array[0..9,0..4] of Byte = (
    (7,5,5,5,7), (2,6,2,2,7), (7,1,7,4,7), (7,1,7,1,7), (5,5,7,1,1),
    (7,4,7,1,7), (7,4,7,5,7), (7,1,1,1,1), (7,5,7,5,7), (7,5,7,1,7)
  );

function MakeColor(R,G,B: Byte): TFPColor;
begin
  Result.Red := R * 257;
  Result.Green := G * 257;
  Result.Blue := B * 257;
  Result.Alpha := $FFFF;
end;

procedure PutPixelSafe(AImage: TFPMemoryImage; X,Y: Integer; const C: TFPColor);
begin
  if (X >= 0) and (Y >= 0) and (X < AImage.Width) and (Y < AImage.Height) then
    AImage.Colors[X,Y] := C;
end;

procedure FillRect(AImage: TFPMemoryImage; X,Y,W,H: Integer; const C: TFPColor);
var
  I,J: Integer;
begin
  for J := Y to Y+H-1 do
    for I := X to X+W-1 do
      PutPixelSafe(AImage,I,J,C);
end;

procedure DrawRect(AImage: TFPMemoryImage; X,Y,W,H,Thickness: Integer; const C: TFPColor);
var
  T,I: Integer;
begin
  if (W < 1) or (H < 1) then Exit;
  for T := 0 to Thickness-1 do
  begin
    for I := X+T to X+W-1-T do
    begin
      PutPixelSafe(AImage,I,Y+T,C);
      PutPixelSafe(AImage,I,Y+H-1-T,C);
    end;
    for I := Y+T to Y+H-1-T do
    begin
      PutPixelSafe(AImage,X+T,I,C);
      PutPixelSafe(AImage,X+W-1-T,I,C);
    end;
  end;
end;

procedure DrawDigit(AImage: TFPMemoryImage; D,X,Y,Scale: Integer; const C: TFPColor);
var
  Row, Col, XX, YY: Integer;
begin
  if (D < 0) or (D > 9) then Exit;
  for Row := 0 to 4 do
    for Col := 0 to 2 do
      if (DigitRows[D,Row] and (1 shl (2-Col))) <> 0 then
        for YY := 0 to Scale-1 do
          for XX := 0 to Scale-1 do
            PutPixelSafe(AImage, X + Col*Scale + XX, Y + Row*Scale + YY, C);
end;

procedure DrawNumberLabel(AImage: TFPMemoryImage; N,X,Y: Integer);
var
  S: string;
  I, Scale, LabelW, LabelH: Integer;
  BG, FG: TFPColor;
begin
  S := IntToStr(N);
  Scale := 2;
  LabelW := Length(S) * (3*Scale + Scale) + 4;
  LabelH := 5*Scale + 4;
  { Prefer placing the mark immediately left of the target, then above it.
    Only fall back to covering the target's top-left corner at an image edge. }
  if X >= LabelW + 2 then
    X := X - LabelW - 2
  else if Y >= LabelH + 2 then
    Y := Y - LabelH - 2;
  if X + LabelW >= AImage.Width then X := AImage.Width - LabelW - 1;
  if Y + LabelH >= AImage.Height then Y := AImage.Height - LabelH - 1;
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  BG := MakeColor(230,35,35);
  FG := MakeColor(255,255,255);
  FillRect(AImage,X,Y,LabelW,LabelH,BG);
  for I := 1 to Length(S) do
    DrawDigit(AImage, Ord(S[I])-Ord('0'), X+2+(I-1)*(4*Scale), Y+2, Scale, FG);
end;

function RenderSomOverlay(const AImageData: TBytes; ATargets: TJSONArray): TBytes;
var
  InputStream, OutputStream: TMemoryStream;
  Reader: TFPReaderPNG;
  Writer: TFPWriterPNG;
  Image: TFPMemoryImage;
  I,X,Y,W,H,Mark: Integer;
  Target, Bounds: TJSONObject;
  BoundsData: TJSONData;
  Border: TFPColor;
begin
  Result := AImageData;
  if (Length(AImageData)=0) or (ATargets=nil) or (ATargets.Count=0) then Exit;
  InputStream := TMemoryStream.Create;
  OutputStream := TMemoryStream.Create;
  Reader := TFPReaderPNG.Create;
  Writer := TFPWriterPNG.Create;
  Image := TFPMemoryImage.Create(0,0);
  try
    InputStream.WriteBuffer(AImageData[0],Length(AImageData));
    InputStream.Position := 0;
    Image.LoadFromStream(InputStream,Reader);
    Border := MakeColor(230,35,35);
    for I := 0 to ATargets.Count-1 do
    begin
      if ATargets.Items[I].JSONType <> jtObject then Continue;
      Target := TJSONObject(ATargets.Items[I]);
      BoundsData := Target.Find('bounds');
      if (BoundsData=nil) or (BoundsData.JSONType<>jtObject) then Continue;
      Bounds := TJSONObject(BoundsData);
      X := JsonInteger(Bounds,'x',-1); Y := JsonInteger(Bounds,'y',-1);
      W := JsonInteger(Bounds,'width',0); H := JsonInteger(Bounds,'height',0);
      if (W<2) or (H<2) then Continue;
      DrawRect(Image,X,Y,W,H,2,Border);
      Mark := JsonInteger(Target,'target',I+1);
      DrawNumberLabel(Image,Mark,X,Y);
    end;
    Image.SaveToStream(OutputStream,Writer);
    SetLength(Result,OutputStream.Size);
    if OutputStream.Size>0 then
    begin
      OutputStream.Position := 0;
      OutputStream.ReadBuffer(Result[0],OutputStream.Size);
    end;
  except
    on E: Exception do
      Result := AImageData;
  end;
  Image.Free;
  Writer.Free;
  Reader.Free;
  OutputStream.Free;
  InputStream.Free;
end;

end.
