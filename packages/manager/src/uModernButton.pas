unit uModernButton;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, Types, Controls, Graphics;

type
  // Used by the manager only on Windows. Linux keeps its native TButton.
  // A windowed control is intentional: keyboard focus and tab navigation work.
  TModernButton = class(TCustomControl)
  private
    FHover: Boolean;
    FPressed: Boolean;
    FKeyPressed: Boolean;
    FPrimary: Boolean;
    procedure SetPrimary(const AValue: Boolean);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Primary: Boolean read FPrimary write SetPrimary;
  published
    property Anchors;
    property Caption;
    property Enabled;
    property Font;
    property ParentFont;
    property TabOrder;
    property TabStop;
    property Visible;
    property OnClick;
  end;

implementation

uses
  LCLType;

constructor TModernButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Keep the standard LCL mouse click dispatch (avoid double-firing OnClick).
  ControlStyle := ControlStyle + [csClickEvents, csCaptureMouse, csOpaque];
  Width := 110;
  Height := 36;
  TabStop := True;
  DoubleBuffered := True;
  Cursor := crHandPoint;
end;

procedure TModernButton.SetPrimary(const AValue: Boolean);
begin
  if FPrimary = AValue then Exit;
  FPrimary := AValue;
  Invalidate;
end;

procedure TModernButton.Paint;
var
  FillColor, LineColor, TextColor: TColor;
  TextX, TextY: Integer;
  IsDown: Boolean;
begin
  // Neutral controls with a clearly visible silhouette. The dark action
  // button uses the black/white LLC palette instead of unrelated blue.
  Canvas.Brush.Style := bsSolid;
  if Parent <> nil then
    Canvas.Brush.Color := Parent.Color
  else
    Canvas.Brush.Color := clWhite;
  Canvas.FillRect(ClientRect);

  IsDown := FPressed or FKeyPressed;
  if not Enabled then
  begin
    FillColor := RGBToColor(238, 239, 241);
    LineColor := RGBToColor(208, 211, 216);
    TextColor := RGBToColor(150, 153, 160);
  end
  else if FPrimary then
  begin
    if IsDown then FillColor := RGBToColor(12, 14, 17)
    else if FHover then FillColor := RGBToColor(55, 58, 63)
    else FillColor := RGBToColor(30, 32, 36);
    LineColor := RGBToColor(24, 25, 28);
    TextColor := clWhite;
  end
  else
  begin
    if IsDown then FillColor := RGBToColor(207, 209, 211)
    else if FHover then FillColor := RGBToColor(222, 224, 226)
    else FillColor := RGBToColor(234, 235, 237);
    if Focused then LineColor := RGBToColor(118, 103, 77)
    else if FHover then LineColor := RGBToColor(132, 136, 142)
    else LineColor := RGBToColor(160, 163, 169);
    TextColor := RGBToColor(26, 28, 32);
  end;

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := LineColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FillColor;
  Canvas.RoundRect(1, 1, Width - 1, Height - 1, 12, 12);

  Canvas.Font.Assign(Font);
  Canvas.Font.Color := TextColor;
  Canvas.Brush.Style := bsClear;
  TextX := (Width - Canvas.TextWidth(Caption)) div 2;
  TextY := (Height - Canvas.TextHeight(Caption)) div 2;
  Canvas.TextOut(TextX, TextY, Caption);

  // Visible keyboard focus without a sharp classic Windows button frame.
  if Focused and Enabled then
  begin
    // Muted warm focus indication, never the Windows-blue double outline.
    Canvas.Pen.Color := RGBToColor(165, 134, 81);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Canvas.RoundRect(4, 4, Width - 4, Height - 4, 8, 8);
  end;
end;

procedure TModernButton.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TModernButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TModernButton.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if (Button = mbLeft) and Enabled then
  begin
    if CanFocus then SetFocus;
    FPressed := True;
    Invalidate;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TModernButton.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
  // Inherited LCL mouse dispatch fires OnClick exactly once on release.
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TModernButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Enabled and (Key in [VK_SPACE, VK_RETURN]) then
  begin
    FKeyPressed := True;
    Invalidate;
    Key := 0;
  end
  else
    inherited KeyDown(Key, Shift);
end;

procedure TModernButton.KeyUp(var Key: Word; Shift: TShiftState);
begin
  if FKeyPressed and (Key in [VK_SPACE, VK_RETURN]) then
  begin
    FKeyPressed := False;
    Invalidate;
    Key := 0;
    if Enabled then Click;
  end
  else
    inherited KeyUp(Key, Shift);
end;

procedure TModernButton.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TModernButton.DoExit;
begin
  FPressed := False;
  FKeyPressed := False;
  inherited DoExit;
  Invalidate;
end;

end.
