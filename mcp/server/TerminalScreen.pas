unit TerminalScreen;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TTerminalCellLine = array of WideChar;
  TTerminalGrid = array of TTerminalCellLine;
  PTerminalGrid = ^TTerminalGrid;

  { A deliberately presentation-only terminal model. It knows nothing about
    SSH, apt, shells, or MCP. VT input mutates cells; normal-screen lines that
    genuinely scroll off the top are retained as scrollback. Repaints and
    cursor-addressed rewrites therefore replace cells instead of becoming
    artificial transcript history. }
  TTerminalScreen = class
  private
    FColumns: Integer;
    FRows: Integer;
    FNormalGrid: TTerminalGrid;
    FAlternateGrid: TTerminalGrid;
    FAlternateActive: Boolean;
    FApplicationCursorKeys: Boolean;
    FCursorRow: Integer;
    FCursorCol: Integer;
    FSavedCursorRow: Integer;
    FSavedCursorCol: Integer;
    FNormalCursorRow: Integer;
    FNormalCursorCol: Integer;
    FScrollTop: Integer;
    FScrollBottom: Integer;
    FWrapPending: Boolean;
    FScrollback: TStringList;
    FMaximumScrollbackLines: Cardinal;
    FScrollbackStartSeq: QWord;
    FScrollbackNextSeq: QWord;
    FVersion: QWord;
    function ActiveGrid: PTerminalGrid;
    procedure AllocateGrid(var AGrid: TTerminalGrid; AColumns, ARows: Integer);
    procedure ClearGrid(var AGrid: TTerminalGrid);
    procedure ClearLine(var ALine: TTerminalCellLine);
    function LineToUtf8(const ALine: TTerminalCellLine): UTF8String;
    procedure AddScrollbackLine(const ALine: TTerminalCellLine);
    procedure Touch;
    procedure ClampCursor;
    procedure ScrollRegionUp(ACount: Integer; ACommitToScrollback: Boolean);
    procedure ScrollRegionDown(ACount: Integer);
    procedure SetCell(ARow, ACol: Integer; AValue: WideChar);
  public
    constructor Create(AColumns, ARows: Word; AMaximumScrollbackLines: Cardinal);
    destructor Destroy; override;
    procedure Reset;
    procedure Resize(AColumns, ARows: Word);
    procedure PutChar(AChar: WideChar);
    procedure CarriageReturn;
    procedure LineFeed;
    procedure NextLine;
    procedure Backspace;
    procedure Tab;
    procedure CursorUp(ACount: Integer);
    procedure CursorDown(ACount: Integer);
    procedure CursorForward(ACount: Integer);
    procedure CursorBackward(ACount: Integer);
    procedure CursorNextLine(ACount: Integer);
    procedure CursorPreviousLine(ACount: Integer);
    procedure CursorHorizontalAbsolute(AColumn: Integer);
    procedure CursorVerticalAbsolute(ARow: Integer);
    procedure CursorPosition(ARow, AColumn: Integer);
    procedure SaveCursor;
    procedure RestoreCursor;
    procedure EraseInDisplay(AMode: Integer);
    procedure EraseInLine(AMode: Integer);
    procedure EraseCharacters(ACount: Integer);
    procedure InsertCharacters(ACount: Integer);
    procedure DeleteCharacters(ACount: Integer);
    procedure InsertLines(ACount: Integer);
    procedure DeleteLines(ACount: Integer);
    procedure ScrollUp(ACount: Integer);
    procedure ScrollDown(ACount: Integer);
    procedure ReverseIndex;
    procedure SetScrollRegion(ATop, ABottom: Integer);
    procedure SetAlternateScreen(AEnabled, AClear: Boolean);
    procedure SetApplicationCursorKeys(AEnabled: Boolean);
    procedure GetCurrentLines(AList: TStrings);
    function RenderCurrentScreen: UTF8String;
    procedure GetScrollbackFrom(AFromSeq: QWord; AList: TStrings;
      out AActualFrom, ANextSeq: QWord; out AMissed: Boolean);
    property Columns: Integer read FColumns;
    property Rows: Integer read FRows;
    property AlternateActive: Boolean read FAlternateActive;
    property ApplicationCursorKeys: Boolean read FApplicationCursorKeys;
    property ScrollbackStartSeq: QWord read FScrollbackStartSeq;
    property ScrollbackNextSeq: QWord read FScrollbackNextSeq;
    property Version: QWord read FVersion;
  end;

implementation

function MaxI(A, B: Integer): Integer; inline;
begin
  if A > B then Result := A else Result := B;
end;

function MinI(A, B: Integer): Integer; inline;
begin
  if A < B then Result := A else Result := B;
end;

constructor TTerminalScreen.Create(AColumns, ARows: Word;
  AMaximumScrollbackLines: Cardinal);
begin
  inherited Create;
  FScrollback := TStringList.Create;
  FMaximumScrollbackLines := AMaximumScrollbackLines;
  FScrollbackStartSeq := 0;
  FScrollbackNextSeq := 0;
  FVersion := 0;
  FColumns := MaxI(1, Integer(AColumns));
  FRows := MaxI(1, Integer(ARows));
  AllocateGrid(FNormalGrid, FColumns, FRows);
  AllocateGrid(FAlternateGrid, FColumns, FRows);
  FAlternateActive := False;
  FApplicationCursorKeys := False;
  FCursorRow := 1;
  FCursorCol := 1;
  FSavedCursorRow := 1;
  FSavedCursorCol := 1;
  FNormalCursorRow := 1;
  FNormalCursorCol := 1;
  FScrollTop := 1;
  FScrollBottom := FRows;
  FWrapPending := False;
end;

destructor TTerminalScreen.Destroy;
begin
  FScrollback.Free;
  inherited Destroy;
end;

function TTerminalScreen.ActiveGrid: PTerminalGrid;
begin
  if FAlternateActive then
    Result := @FAlternateGrid
  else
    Result := @FNormalGrid;
end;

procedure TTerminalScreen.AllocateGrid(var AGrid: TTerminalGrid;
  AColumns, ARows: Integer);
var
  R: Integer;
begin
  SetLength(AGrid, ARows);
  for R := 0 to ARows - 1 do
  begin
    SetLength(AGrid[R], AColumns);
    ClearLine(AGrid[R]);
  end;
end;

procedure TTerminalScreen.ClearLine(var ALine: TTerminalCellLine);
var
  C: Integer;
begin
  for C := 0 to High(ALine) do
    ALine[C] := ' ';
end;

procedure TTerminalScreen.ClearGrid(var AGrid: TTerminalGrid);
var
  R: Integer;
begin
  for R := 0 to High(AGrid) do
    ClearLine(AGrid[R]);
end;

procedure TTerminalScreen.Touch;
begin
  Inc(FVersion);
end;

procedure TTerminalScreen.ClampCursor;
begin
  FCursorRow := MinI(MaxI(FCursorRow, 1), FRows);
  FCursorCol := MinI(MaxI(FCursorCol, 1), FColumns);
end;

function TTerminalScreen.LineToUtf8(const ALine: TTerminalCellLine): UTF8String;
var
  Last, I: Integer;
  U: UnicodeString;
begin
  Last := High(ALine);
  while (Last >= 0) and (ALine[Last] = ' ') do
    Dec(Last);
  if Last < 0 then
    Exit('');
  SetLength(U, Last + 1);
  for I := 0 to Last do
    U[I + 1] := ALine[I];
  Result := UTF8Encode(U);
end;

procedure TTerminalScreen.AddScrollbackLine(const ALine: TTerminalCellLine);
begin
  if FMaximumScrollbackLines = 0 then
    Exit;
  FScrollback.Add(string(LineToUtf8(ALine)));
  Inc(FScrollbackNextSeq);
  while Cardinal(FScrollback.Count) > FMaximumScrollbackLines do
  begin
    FScrollback.Delete(0);
    Inc(FScrollbackStartSeq);
  end;
end;

procedure TTerminalScreen.Reset;
begin
  ClearGrid(FNormalGrid);
  ClearGrid(FAlternateGrid);
  FScrollback.Clear;
  FScrollbackStartSeq := 0;
  FScrollbackNextSeq := 0;
  FAlternateActive := False;
  FApplicationCursorKeys := False;
  FCursorRow := 1;
  FCursorCol := 1;
  FSavedCursorRow := 1;
  FSavedCursorCol := 1;
  FNormalCursorRow := 1;
  FNormalCursorCol := 1;
  FScrollTop := 1;
  FScrollBottom := FRows;
  FWrapPending := False;
  Touch;
end;

procedure TTerminalScreen.Resize(AColumns, ARows: Word);
var
  NewNormal, NewAlternate: TTerminalGrid;
  R, C, NewCols, NewRows: Integer;
begin
  NewCols := MaxI(1, Integer(AColumns));
  NewRows := MaxI(1, Integer(ARows));
  if (NewCols = FColumns) and (NewRows = FRows) then
    Exit;

  AllocateGrid(NewNormal, NewCols, NewRows);
  AllocateGrid(NewAlternate, NewCols, NewRows);
  for R := 0 to MinI(FRows, NewRows) - 1 do
    for C := 0 to MinI(FColumns, NewCols) - 1 do
    begin
      NewNormal[R][C] := FNormalGrid[R][C];
      NewAlternate[R][C] := FAlternateGrid[R][C];
    end;
  FNormalGrid := NewNormal;
  FAlternateGrid := NewAlternate;
  FColumns := NewCols;
  FRows := NewRows;
  FScrollTop := 1;
  FScrollBottom := FRows;
  FWrapPending := False;
  ClampCursor;
  Touch;
end;

procedure TTerminalScreen.SetCell(ARow, ACol: Integer; AValue: WideChar);
var
  G: PTerminalGrid;
begin
  if (ARow < 1) or (ARow > FRows) or (ACol < 1) or (ACol > FColumns) then
    Exit;
  G := ActiveGrid;
  if G^[ARow - 1][ACol - 1] <> AValue then
  begin
    G^[ARow - 1][ACol - 1] := AValue;
    Touch;
  end;
end;

procedure TTerminalScreen.ScrollRegionUp(ACount: Integer;
  ACommitToScrollback: Boolean);
var
  G: PTerminalGrid;
  N, R, C: Integer;
begin
  if ACount <= 0 then ACount := 1;
  ACount := MinI(ACount, FScrollBottom - FScrollTop + 1);
  G := ActiveGrid;
  for N := 1 to ACount do
  begin
    if ACommitToScrollback and (not FAlternateActive) and
       (FScrollTop = 1) and (FScrollBottom = FRows) then
      AddScrollbackLine(G^[FScrollTop - 1]);

    for R := FScrollTop - 1 to FScrollBottom - 2 do
      for C := 0 to FColumns - 1 do
        G^[R][C] := G^[R + 1][C];
    for C := 0 to FColumns - 1 do
      G^[FScrollBottom - 1][C] := ' ';
  end;
  Touch;
end;

procedure TTerminalScreen.ScrollRegionDown(ACount: Integer);
var
  G: PTerminalGrid;
  N, R, C: Integer;
begin
  if ACount <= 0 then ACount := 1;
  ACount := MinI(ACount, FScrollBottom - FScrollTop + 1);
  G := ActiveGrid;
  for N := 1 to ACount do
  begin
    for R := FScrollBottom - 1 downto FScrollTop do
      for C := 0 to FColumns - 1 do
        G^[R][C] := G^[R - 1][C];
    for C := 0 to FColumns - 1 do
      G^[FScrollTop - 1][C] := ' ';
  end;
  Touch;
end;

procedure TTerminalScreen.PutChar(AChar: WideChar);
begin
  if FWrapPending then
  begin
    FCursorCol := 1;
    LineFeed;
    FWrapPending := False;
  end;
  SetCell(FCursorRow, FCursorCol, AChar);
  if FCursorCol >= FColumns then
    FWrapPending := True
  else
    Inc(FCursorCol);
end;

procedure TTerminalScreen.CarriageReturn;
begin
  FCursorCol := 1;
  FWrapPending := False;
end;

procedure TTerminalScreen.LineFeed;
begin
  FWrapPending := False;
  if (FCursorRow >= FScrollTop) and (FCursorRow <= FScrollBottom) then
  begin
    if FCursorRow = FScrollBottom then
      ScrollRegionUp(1, True)
    else
      Inc(FCursorRow);
  end
  else if FCursorRow < FRows then
    Inc(FCursorRow);
end;

procedure TTerminalScreen.NextLine;
begin
  CarriageReturn;
  LineFeed;
end;

procedure TTerminalScreen.Backspace;
begin
  if FCursorCol > 1 then Dec(FCursorCol);
  FWrapPending := False;
end;

procedure TTerminalScreen.Tab;
var
  NextTab: Integer;
begin
  NextTab := ((FCursorCol - 1) div 8 + 1) * 8 + 1;
  FCursorCol := MinI(NextTab, FColumns);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorUp(ACount: Integer);
begin
  if ACount <= 0 then ACount := 1;
  FCursorRow := MaxI(1, FCursorRow - ACount);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorDown(ACount: Integer);
begin
  if ACount <= 0 then ACount := 1;
  FCursorRow := MinI(FRows, FCursorRow + ACount);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorForward(ACount: Integer);
begin
  if ACount <= 0 then ACount := 1;
  FCursorCol := MinI(FColumns, FCursorCol + ACount);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorBackward(ACount: Integer);
begin
  if ACount <= 0 then ACount := 1;
  FCursorCol := MaxI(1, FCursorCol - ACount);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorNextLine(ACount: Integer);
begin
  CursorDown(ACount);
  FCursorCol := 1;
end;

procedure TTerminalScreen.CursorPreviousLine(ACount: Integer);
begin
  CursorUp(ACount);
  FCursorCol := 1;
end;

procedure TTerminalScreen.CursorHorizontalAbsolute(AColumn: Integer);
begin
  if AColumn <= 0 then AColumn := 1;
  FCursorCol := MinI(AColumn, FColumns);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorVerticalAbsolute(ARow: Integer);
begin
  if ARow <= 0 then ARow := 1;
  FCursorRow := MinI(ARow, FRows);
  FWrapPending := False;
end;

procedure TTerminalScreen.CursorPosition(ARow, AColumn: Integer);
begin
  if ARow <= 0 then ARow := 1;
  if AColumn <= 0 then AColumn := 1;
  FCursorRow := MinI(ARow, FRows);
  FCursorCol := MinI(AColumn, FColumns);
  FWrapPending := False;
end;

procedure TTerminalScreen.SaveCursor;
begin
  FSavedCursorRow := FCursorRow;
  FSavedCursorCol := FCursorCol;
end;

procedure TTerminalScreen.RestoreCursor;
begin
  FCursorRow := FSavedCursorRow;
  FCursorCol := FSavedCursorCol;
  ClampCursor;
  FWrapPending := False;
end;

procedure TTerminalScreen.EraseInLine(AMode: Integer);
var
  G: PTerminalGrid;
  C, StartC, EndC: Integer;
begin
  G := ActiveGrid;
  case AMode of
    1: begin StartC := 1; EndC := FCursorCol; end;
    2: begin StartC := 1; EndC := FColumns; end;
  else
    StartC := FCursorCol; EndC := FColumns;
  end;
  for C := StartC to EndC do
    G^[FCursorRow - 1][C - 1] := ' ';
  FWrapPending := False;
  Touch;
end;

procedure TTerminalScreen.EraseInDisplay(AMode: Integer);
var
  G: PTerminalGrid;
  R, C: Integer;
begin
  G := ActiveGrid;
  case AMode of
    1:
      begin
        for R := 1 to FCursorRow - 1 do
          ClearLine(G^[R - 1]);
        for C := 1 to FCursorCol do
          G^[FCursorRow - 1][C - 1] := ' ';
      end;
    2:
      ClearGrid(G^);
    3:
      begin
        if not FAlternateActive then
        begin
          FScrollback.Clear;
          FScrollbackStartSeq := FScrollbackNextSeq;
        end;
      end;
  else
    begin
      for C := FCursorCol to FColumns do
        G^[FCursorRow - 1][C - 1] := ' ';
      for R := FCursorRow + 1 to FRows do
        ClearLine(G^[R - 1]);
    end;
  end;
  FWrapPending := False;
  Touch;
end;

procedure TTerminalScreen.EraseCharacters(ACount: Integer);
var
  G: PTerminalGrid;
  C, EndC: Integer;
begin
  if ACount <= 0 then ACount := 1;
  G := ActiveGrid;
  EndC := MinI(FColumns, FCursorCol + ACount - 1);
  for C := FCursorCol to EndC do
    G^[FCursorRow - 1][C - 1] := ' ';
  Touch;
end;

procedure TTerminalScreen.InsertCharacters(ACount: Integer);
var
  G: PTerminalGrid;
  C, N: Integer;
begin
  if ACount <= 0 then ACount := 1;
  N := MinI(ACount, FColumns - FCursorCol + 1);
  G := ActiveGrid;
  for C := FColumns downto FCursorCol + N do
    G^[FCursorRow - 1][C - 1] := G^[FCursorRow - 1][C - N - 1];
  for C := FCursorCol to MinI(FColumns, FCursorCol + N - 1) do
    G^[FCursorRow - 1][C - 1] := ' ';
  Touch;
end;

procedure TTerminalScreen.DeleteCharacters(ACount: Integer);
var
  G: PTerminalGrid;
  C, N: Integer;
begin
  if ACount <= 0 then ACount := 1;
  N := MinI(ACount, FColumns - FCursorCol + 1);
  G := ActiveGrid;
  for C := FCursorCol to FColumns - N do
    G^[FCursorRow - 1][C - 1] := G^[FCursorRow - 1][C + N - 1];
  for C := FColumns - N + 1 to FColumns do
    G^[FCursorRow - 1][C - 1] := ' ';
  Touch;
end;

procedure TTerminalScreen.InsertLines(ACount: Integer);
var
  G: PTerminalGrid;
  N, R, C: Integer;
begin
  if (FCursorRow < FScrollTop) or (FCursorRow > FScrollBottom) then Exit;
  if ACount <= 0 then ACount := 1;
  ACount := MinI(ACount, FScrollBottom - FCursorRow + 1);
  G := ActiveGrid;
  for N := 1 to ACount do
  begin
    for R := FScrollBottom - 1 downto FCursorRow do
      for C := 0 to FColumns - 1 do
        G^[R][C] := G^[R - 1][C];
    for C := 0 to FColumns - 1 do G^[FCursorRow - 1][C] := ' ';
  end;
  Touch;
end;

procedure TTerminalScreen.DeleteLines(ACount: Integer);
var
  G: PTerminalGrid;
  N, R, C: Integer;
begin
  if (FCursorRow < FScrollTop) or (FCursorRow > FScrollBottom) then Exit;
  if ACount <= 0 then ACount := 1;
  ACount := MinI(ACount, FScrollBottom - FCursorRow + 1);
  G := ActiveGrid;
  for N := 1 to ACount do
  begin
    for R := FCursorRow - 1 to FScrollBottom - 2 do
      for C := 0 to FColumns - 1 do
        G^[R][C] := G^[R + 1][C];
    for C := 0 to FColumns - 1 do G^[FScrollBottom - 1][C] := ' ';
  end;
  Touch;
end;

procedure TTerminalScreen.ScrollUp(ACount: Integer);
begin
  ScrollRegionUp(ACount, False);
end;

procedure TTerminalScreen.ScrollDown(ACount: Integer);
begin
  ScrollRegionDown(ACount);
end;

procedure TTerminalScreen.ReverseIndex;
begin
  FWrapPending := False;
  if FCursorRow = FScrollTop then
    ScrollRegionDown(1)
  else if FCursorRow > 1 then
    Dec(FCursorRow);
end;

procedure TTerminalScreen.SetScrollRegion(ATop, ABottom: Integer);
begin
  if ATop <= 0 then ATop := 1;
  if ABottom <= 0 then ABottom := FRows;
  ATop := MinI(MaxI(ATop, 1), FRows);
  ABottom := MinI(MaxI(ABottom, 1), FRows);
  if ATop >= ABottom then
  begin
    FScrollTop := 1;
    FScrollBottom := FRows;
  end
  else
  begin
    FScrollTop := ATop;
    FScrollBottom := ABottom;
  end;
  CursorPosition(1, 1);
end;

procedure TTerminalScreen.SetAlternateScreen(AEnabled, AClear: Boolean);
begin
  if AEnabled = FAlternateActive then
  begin
    if AEnabled and AClear then
    begin
      ClearGrid(FAlternateGrid);
      CursorPosition(1, 1);
      Touch;
    end;
    Exit;
  end;

  if AEnabled then
  begin
    FNormalCursorRow := FCursorRow;
    FNormalCursorCol := FCursorCol;
    FAlternateActive := True;
    if AClear then ClearGrid(FAlternateGrid);
    FCursorRow := 1;
    FCursorCol := 1;
  end
  else
  begin
    FAlternateActive := False;
    FCursorRow := FNormalCursorRow;
    FCursorCol := FNormalCursorCol;
    ClampCursor;
  end;
  FScrollTop := 1;
  FScrollBottom := FRows;
  FWrapPending := False;
  Touch;
end;

procedure TTerminalScreen.SetApplicationCursorKeys(AEnabled: Boolean);
begin
  { DECCKM changes how the host must encode cursor keys but does not alter the
    visible screen, so it intentionally does not bump the screen version. }
  FApplicationCursorKeys := AEnabled;
end;

procedure TTerminalScreen.GetCurrentLines(AList: TStrings);
var
  G: PTerminalGrid;
  R, LastNonBlank: Integer;
  S: UTF8String;
begin
  AList.Clear;
  G := ActiveGrid;
  LastNonBlank := FRows;
  while LastNonBlank > 0 do
  begin
    S := LineToUtf8(G^[LastNonBlank - 1]);
    if S <> '' then Break;
    Dec(LastNonBlank);
  end;
  for R := 1 to LastNonBlank do
    AList.Add(string(LineToUtf8(G^[R - 1])));
end;

function TTerminalScreen.RenderCurrentScreen: UTF8String;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    GetCurrentLines(Lines);
    Result := UTF8String(Lines.Text);
    while (Length(Result) > 0) and
      ((Result[Length(Result)] = #10) or (Result[Length(Result)] = #13)) do
      Delete(Result, Length(Result), 1);
  finally
    Lines.Free;
  end;
end;

procedure TTerminalScreen.GetScrollbackFrom(AFromSeq: QWord;
  AList: TStrings; out AActualFrom, ANextSeq: QWord; out AMissed: Boolean);
var
  I, StartIndex: Integer;
begin
  AList.Clear;
  AMissed := AFromSeq < FScrollbackStartSeq;
  if AFromSeq < FScrollbackStartSeq then
    AActualFrom := FScrollbackStartSeq
  else if AFromSeq > FScrollbackNextSeq then
    AActualFrom := FScrollbackNextSeq
  else
    AActualFrom := AFromSeq;

  StartIndex := Integer(AActualFrom - FScrollbackStartSeq);
  for I := StartIndex to FScrollback.Count - 1 do
    AList.Add(FScrollback[I]);
  ANextSeq := FScrollbackNextSeq;
end;

end.
