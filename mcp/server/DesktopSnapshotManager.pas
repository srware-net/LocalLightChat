unit DesktopSnapshotManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpjson, Contnrs, DesktopRuntime, DesktopBackend,
  ServerConfig, DesktopVisualGrounder;

type
  TSnapshotTarget = class
  public
    Mark: Integer;
    Name: string;
    Path: string;
    Role: string;
    Provider: string;
    ProviderRef: string;
    Actions: TStringList;
    HasImageBounds: Boolean;
    ImageBounds: TRect;
    HasScreenBounds: Boolean;
    ScreenBounds: TRect;
    HasConfidence: Boolean;
    Confidence: Double;
    constructor Create;
    destructor Destroy; override;
    function ToJson: TJSONObject;
  end;

  TDesktopSnapshotState = class
  public
    Id: string;
    WindowHandle: QWord;
    WindowTitle: string;
    SourceX, SourceY, SourceWidth, SourceHeight: Integer;
    ImageWidth, ImageHeight: Integer;
    Consumed: Boolean;
    StateHash: string;
    Targets: TObjectList;
    constructor Create;
    destructor Destroy; override;
    function FindTarget(AMark: Integer): TSnapshotTarget;
  end;

  TDesktopSnapshotManager = class
  private
    FRuntime: TDesktopRuntime;
    FConfig: TServerConfig;
    FGrounder: TDesktopVisualGrounder;
    FSnapshots: TObjectList;
    FNextId: QWord;
    FLock: TRTLCriticalSection;
    function ResolveWindowHandle(AArguments: TJSONObject; out AResolution: string): string;
    function HashBytes(const AData: TBytes): string;
    procedure AddSemanticTargets(AState: TDesktopSnapshotState;
      APublicTargets: TJSONArray; AHandle: string; AMaxTargets: Integer);
    procedure AddVisualTargets(AState: TDesktopSnapshotState;
      APublicTargets, AGrounded: TJSONArray; AMaxTargets: Integer);
    procedure AddTarget(AState: TDesktopSnapshotState; APublicTargets: TJSONArray;
      ATarget: TSnapshotTarget);
    function VisualDuplicatesExisting(AState: TDesktopSnapshotState;
      const AText: string; const ABounds: TRect): Boolean;
    procedure PruneSnapshots;
    function FindSnapshot(const AId: string): TDesktopSnapshotState;
    function MostRecentSnapshot: TDesktopSnapshotState;
    function RevalidateVisualTargetCurrent(AState: TDesktopSnapshotState;
      ATarget: TSnapshotTarget): Boolean;
    function PhysicalClickTarget(AState: TDesktopSnapshotState;
      ATarget: TSnapshotTarget; AArguments: TJSONObject): TJSONObject;
  public
    constructor Create(ARuntime: TDesktopRuntime; AConfig: TServerConfig);
    destructor Destroy; override;
    function CreateSnapshot(AArguments: TJSONObject; AMaximumImageBytes: Cardinal;
      out ACapture: TDesktopCaptureResult): TJSONObject;
    function Act(AArguments: TJSONObject): TJSONObject;
    procedure InvalidateAll;
  end;

implementation

uses
  Math, McpJson, DesktopSomOverlay;

constructor TSnapshotTarget.Create;
begin
  inherited Create;
  Actions := TStringList.Create;
  Actions.CaseSensitive := False;
  Actions.Duplicates := dupIgnore;
  Actions.Sorted := True;
  HasImageBounds := False;
  HasScreenBounds := False;
  HasConfidence := False;
  Confidence := 0;
  FillChar(ImageBounds, SizeOf(ImageBounds), 0);
  FillChar(ScreenBounds, SizeOf(ScreenBounds), 0);
end;

destructor TSnapshotTarget.Destroy;
begin
  Actions.Free;
  inherited Destroy;
end;

function RectToJson(const R: TRect): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('x', R.Left);
  Result.Add('y', R.Top);
  Result.Add('width', R.Right - R.Left);
  Result.Add('height', R.Bottom - R.Top);
end;

function TSnapshotTarget.ToJson: TJSONObject;
var
  A: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('target', Mark);
  Result.Add('name', Name);
  if Path<>'' then Result.Add('path', Path);
  Result.Add('role', Role);
  Result.Add('source', Provider);
  if HasConfidence then Result.Add('confidence', Confidence);
  Result.Add('marked_in_image', HasImageBounds);
  A := TJSONArray.Create;
  for I := 0 to Actions.Count - 1 do A.Add(Actions[I]);
  Result.Add('actions', A);
end;

constructor TDesktopSnapshotState.Create;
begin
  inherited Create;
  Targets := TObjectList.Create(True);
end;

destructor TDesktopSnapshotState.Destroy;
begin
  Targets.Free;
  inherited Destroy;
end;

function TDesktopSnapshotState.FindTarget(AMark: Integer): TSnapshotTarget;
var
  I: Integer;
  T: TSnapshotTarget;
begin
  Result := nil;
  for I := 0 to Targets.Count - 1 do
  begin
    T := TSnapshotTarget(Targets[I]);
    if T.Mark = AMark then Exit(T);
  end;
end;

constructor TDesktopSnapshotManager.Create(ARuntime: TDesktopRuntime;
  AConfig: TServerConfig);
begin
  inherited Create;
  FRuntime := ARuntime;
  FConfig := AConfig;
  FGrounder := TDesktopVisualGrounder.Create(AConfig);
  FSnapshots := TObjectList.Create(True);
  FNextId := 1;
  InitCriticalSection(FLock);
end;

destructor TDesktopSnapshotManager.Destroy;
begin
  DoneCriticalSection(FLock);
  FSnapshots.Free;
  FGrounder.Free;
  inherited Destroy;
end;

function TDesktopSnapshotManager.HashBytes(const AData: TBytes): string;
var
  H: QWord;
  I: Integer;
begin
  H := QWord($CBF29CE484222325);
  for I := 0 to High(AData) do
  begin
    H := H xor AData[I];
    H := H * QWord($100000001B3);
  end;
  Result := LowerCase(IntToHex(H, 16));
end;

function TDesktopSnapshotManager.ResolveWindowHandle(AArguments: TJSONObject;
  out AResolution: string): string;
var
  AppText, ForegroundHandle, ForegroundPid: string;
  Args, Listed, Status: TJSONObject;
  WindowsData: TJSONData;
  WindowsArray: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  MatchingPids: TStringList;
begin
  AResolution := '';
  Result := Trim(JsonString(AArguments, 'handle', ''));
  if Result <> '' then
  begin
    AResolution := 'handle';
    Exit;
  end;

  AppText := Trim(JsonString(AArguments, 'app', ''));
  if AppText = '' then
  begin
    Status := FRuntime.GetStatus;
    try
      Result := Trim(JsonString(Status, 'foreground_window', ''));
    finally
      Status.Free;
    end;
    if Result = '' then
      raise Exception.Create('No foreground window is available');
    AResolution := 'foreground';
    Exit;
  end;

  MatchingPids := TStringList.Create;
  MatchingPids.Sorted := True;
  MatchingPids.Duplicates := dupIgnore;
  try
    Args := TJSONObject.Create;
    try
      Args.Add('query', AppText);
      Args.Add('details', True);
      Args.Add('limit', 200);
      Listed := FRuntime.ListWindows(Args);
      try
        WindowsData := Listed.Find('windows');
        if (WindowsData = nil) or (WindowsData.JSONType <> jtArray) or
           (TJSONArray(WindowsData).Count = 0) then
          raise Exception.Create('No current window matches app=' + AppText);
        WindowsArray := TJSONArray(WindowsData);
        for I := 0 to WindowsArray.Count - 1 do
          if WindowsArray.Items[I].JSONType = jtObject then
          begin
            Item := TJSONObject(WindowsArray.Items[I]);
            MatchingPids.Add(IntToStr(JsonInteger(Item, 'process_id', 0)));
            if JsonBoolean(Item, 'foreground', False) and (AResolution = '') then
            begin
              Result := JsonString(Item, 'handle');
              AResolution := 'app_foreground_match';
            end;
          end;
        if AResolution = '' then
          Result := JsonString(TJSONObject(WindowsArray.Items[0]), 'handle');
      finally
        Listed.Free;
      end;
    finally
      Args.Free;
    end;

    { Prefer a modal foreground dialog owned by the same process as the app. }
    if AResolution <> 'app_foreground_match' then
    begin
      Status := FRuntime.GetStatus;
      try
        ForegroundHandle := Trim(JsonString(Status, 'foreground_window', ''));
      finally
        Status.Free;
      end;
      if ForegroundHandle <> '' then
      begin
        Args := TJSONObject.Create;
        try
          Args.Add('details', True);
          Args.Add('limit', 200);
          Listed := FRuntime.ListWindows(Args);
          try
            WindowsData := Listed.Find('windows');
            if (WindowsData <> nil) and (WindowsData.JSONType = jtArray) then
              for I := 0 to TJSONArray(WindowsData).Count - 1 do
                if TJSONArray(WindowsData).Items[I].JSONType = jtObject then
                begin
                  Item := TJSONObject(TJSONArray(WindowsData).Items[I]);
                  if JsonString(Item, 'handle') = ForegroundHandle then
                  begin
                    ForegroundPid := IntToStr(JsonInteger(Item, 'process_id', 0));
                    if MatchingPids.IndexOf(ForegroundPid) >= 0 then
                    begin
                      Result := ForegroundHandle;
                      AResolution := 'app_foreground_same_process';
                    end;
                    Break;
                  end;
                end;
          finally
            Listed.Free;
          end;
        finally
          Args.Free;
        end;
      end;
    end;
  finally
    MatchingPids.Free;
  end;

  if AResolution = '' then
    AResolution := 'app_match';
end;

function ClipRectToImage(const R: TRect; W,H: Integer; out C: TRect): Boolean;
begin
  C.Left := Max(0,R.Left); C.Top := Max(0,R.Top);
  C.Right := Min(W,R.Right); C.Bottom := Min(H,R.Bottom);
  Result := (C.Right > C.Left) and (C.Bottom > C.Top);
end;

function MapScreenToImage(AState: TDesktopSnapshotState; const R: TRect;
  out M: TRect): Boolean;
var
  Raw: TRect;
begin
  if (AState.SourceWidth <= 0) or (AState.SourceHeight <= 0) then Exit(False);
  Raw.Left := Round((R.Left - AState.SourceX) * AState.ImageWidth / AState.SourceWidth);
  Raw.Top := Round((R.Top - AState.SourceY) * AState.ImageHeight / AState.SourceHeight);
  Raw.Right := Round((R.Right - AState.SourceX) * AState.ImageWidth / AState.SourceWidth);
  Raw.Bottom := Round((R.Bottom - AState.SourceY) * AState.ImageHeight / AState.SourceHeight);
  Result := ClipRectToImage(Raw,AState.ImageWidth,AState.ImageHeight,M);
end;

function MapImageToScreen(AState: TDesktopSnapshotState; const R: TRect): TRect;
begin
  Result.Left := AState.SourceX + Round(R.Left * AState.SourceWidth / AState.ImageWidth);
  Result.Top := AState.SourceY + Round(R.Top * AState.SourceHeight / AState.ImageHeight);
  Result.Right := AState.SourceX + Round(R.Right * AState.SourceWidth / AState.ImageWidth);
  Result.Bottom := AState.SourceY + Round(R.Bottom * AState.SourceHeight / AState.ImageHeight);
end;

procedure CopyActions(AData: TJSONData; ATarget: TSnapshotTarget);
var
  A: TJSONArray;
  I: Integer;
begin
  if (AData=nil) or (AData.JSONType<>jtArray) then Exit;
  A := TJSONArray(AData);
  for I := 0 to A.Count-1 do
    if A.Items[I].JSONType=jtString then ATarget.Actions.Add(A.Items[I].AsString);
end;

procedure TDesktopSnapshotManager.AddTarget(AState: TDesktopSnapshotState;
  APublicTargets: TJSONArray; ATarget: TSnapshotTarget);
begin
  ATarget.Mark := AState.Targets.Count + 1;
  AState.Targets.Add(ATarget);
  APublicTargets.Add(ATarget.ToJson);
end;

procedure TDesktopSnapshotManager.AddSemanticTargets(AState: TDesktopSnapshotState;
  APublicTargets: TJSONArray; AHandle: string; AMaxTargets: Integer);
var
  Args, R: TJSONObject;
  Data, BoundsData: TJSONData;
  A: TJSONArray;
  I: Integer;
  E, B: TJSONObject;
  T: TSnapshotTarget;
  SR, IR: TRect;
  NameText: string;
  Area, ImageArea: Int64;
begin
  if not FConfig.DesktopAccessibilityEnabled then Exit;
  Args := TJSONObject.Create;
  try
    Args.Add('handle', AHandle);
    Args.Add('view','auto');
    Args.Add('include_offscreen',False);
    Args.Add('actionable_only',False);
    Args.Add('details',True);
    Args.Add('limit',Min(500,AMaxTargets*3));
    R := FRuntime.ListUiElements(Args);
    try
      Data := R.Find('elements');
      if (Data=nil) or (Data.JSONType<>jtArray) then Exit;
      A := TJSONArray(Data);
      for I := 0 to A.Count-1 do
      begin
        if AState.Targets.Count >= AMaxTargets then Break;
        if A.Items[I].JSONType<>jtObject then Continue;
        E := TJSONObject(A.Items[I]);
        NameText := Trim(JsonString(E,'name',''));
        if NameText='' then NameText := Trim(JsonString(E,'automation_id',''));
        T := TSnapshotTarget.Create;
        T.Role := JsonString(E,'control_type','control');
        if Trim(T.Role) = '' then T.Role := 'control';
        if (NameText = '') and
           ((T.Role = 'window') or (T.Role = 'text') or (T.Role = 'menu_bar') or
            (T.Role = 'tool_bar') or (T.Role = 'status_bar') or
            (T.Role = 'separator') or (T.Role = 'title_bar')) then
        begin
          T.Free;
          Continue;
        end;
        if NameText <> '' then
          T.Name := NameText
        else
          T.Name := '[' + T.Role + ']';
        T.Path := Trim(JsonString(E,'path',''));
        T.ProviderRef := JsonString(E,'ref','');
        if JsonString(E,'source','')<>'' then T.Provider := JsonString(E,'source')
        else T.Provider := 'uia';
        CopyActions(E.Find('actions'),T);
        BoundsData := E.Find('bounds');
        if (BoundsData<>nil) and (BoundsData.JSONType=jtObject) then
        begin
          B := TJSONObject(BoundsData);
          SR.Left := JsonInteger(B,'x'); SR.Top := JsonInteger(B,'y');
          SR.Right := SR.Left + JsonInteger(B,'width');
          SR.Bottom := SR.Top + JsonInteger(B,'height');
          T.ScreenBounds := SR; T.HasScreenBounds := True;
          if MapScreenToImage(AState,SR,IR) then
          begin T.ImageBounds:=IR; T.HasImageBounds:=True; end;
        end;
        { The snapshot router accepts action=activate for any UIA element with a
          provider-backed click point, even when the low-level provider only
          advertises click. This keeps the agent-facing action vocabulary simple. }
        if (T.Actions.IndexOf('click')>=0) and (T.Actions.IndexOf('activate')<0) then
          T.Actions.Add('activate');

        { Keep medium-sized unnamed panes/groups as spatial semantic targets.
          This is useful for designer canvases and other blank drop surfaces that
          OCR cannot name, while avoiding tiny layout fragments and nearly-full
          window wrappers that would make the SoM unreadable. }
        if (NameText='') and ((T.Role='pane') or (T.Role='group')) then
        begin
          if T.HasImageBounds then
          begin
            Area := Int64(T.ImageBounds.Right-T.ImageBounds.Left) *
              Int64(T.ImageBounds.Bottom-T.ImageBounds.Top);
            ImageArea := Int64(AState.ImageWidth) * Int64(AState.ImageHeight);
          end
          else
          begin
            Area := 0;
            ImageArea := 1;
          end;
          if (not T.HasImageBounds) or (Area*400<ImageArea) or
             (Area*100>ImageArea*85) then
          begin
            T.Free;
            Continue;
          end;
        end;
        if (T.Actions.Count = 0) and (not T.HasImageBounds) then
        begin
          T.Free;
          Continue;
        end;
        AddTarget(AState,APublicTargets,T);
      end;
    finally
      R.Free;
    end;
  finally
    Args.Free;
  end;
end;

function NormalizeText(const S: string): string;
var
  I: Integer;
begin
  Result := LowerCase(Trim(S));
  for I := Length(Result) downto 1 do
    if Result[I] in [#9,#10,#13] then Result[I] := ' ';
  while Pos('  ',Result)>0 do Result := StringReplace(Result,'  ',' ',[rfReplaceAll]);
end;

function RectsOverlap(const A,B: TRect): Boolean;
begin
  Result := (Min(A.Right,B.Right)>Max(A.Left,B.Left)) and
    (Min(A.Bottom,B.Bottom)>Max(A.Top,B.Top));
end;

function TDesktopSnapshotManager.VisualDuplicatesExisting(
  AState: TDesktopSnapshotState; const AText: string; const ABounds: TRect): Boolean;
var
  I: Integer;
  T: TSnapshotTarget;
  Cx,Cy: Integer;
begin
  Result := False;
  Cx := (ABounds.Left+ABounds.Right) div 2;
  Cy := (ABounds.Top+ABounds.Bottom) div 2;
  for I := 0 to AState.Targets.Count-1 do
  begin
    T := TSnapshotTarget(AState.Targets[I]);
    if NormalizeText(T.Name) <> NormalizeText(AText) then Continue;
    if not T.HasImageBounds then Continue;
    if RectsOverlap(T.ImageBounds,ABounds) or
      ((Cx>=T.ImageBounds.Left) and (Cx<T.ImageBounds.Right) and
       (Cy>=T.ImageBounds.Top) and (Cy<T.ImageBounds.Bottom)) then Exit(True);
  end;
end;

procedure TDesktopSnapshotManager.AddVisualTargets(AState: TDesktopSnapshotState;
  APublicTargets, AGrounded: TJSONArray; AMaxTargets: Integer);
var
  I: Integer;
  G,B: TJSONObject;
  D: TJSONData;
  T: TSnapshotTarget;
  R, ClippedR: TRect;
  TextValue, RoleValue: string;
  ConfidenceData: TJSONData;
begin
  if AGrounded=nil then Exit;
  for I := 0 to AGrounded.Count-1 do
  begin
    if AState.Targets.Count >= AMaxTargets then Break;
    if AGrounded.Items[I].JSONType<>jtObject then Continue;
    G := TJSONObject(AGrounded.Items[I]);
    TextValue := Trim(JsonString(G,'text',
      JsonString(G,'name',JsonString(G,'label',''))));
    RoleValue := Trim(JsonString(G,'role','visual'));
    if RoleValue='' then RoleValue := 'visual';
    D := G.Find('bounds');
    if (D=nil) or (D.JSONType<>jtObject) then Continue;
    B := TJSONObject(D);
    R.Left := JsonInteger(B,'x',-1); R.Top := JsonInteger(B,'y',-1);
    R.Right := R.Left + JsonInteger(B,'width',0);
    R.Bottom := R.Top + JsonInteger(B,'height',0);
    if (R.Left<0) or (R.Top<0) or (R.Right<=R.Left) or (R.Bottom<=R.Top) then Continue;
    if not ClipRectToImage(R,AState.ImageWidth,AState.ImageHeight,ClippedR) then Continue;
    R := ClippedR;
    if (TextValue<>'') and VisualDuplicatesExisting(AState,TextValue,R) then Continue;
    T := TSnapshotTarget.Create;
    if TextValue<>'' then T.Name := TextValue
    else T.Name := '[' + RoleValue + ']';
    T.Role := RoleValue;
    T.Provider := 'vision';
    T.Actions.Add('activate'); T.Actions.Add('click');
    T.ImageBounds := R; T.HasImageBounds := True;
    T.ScreenBounds := MapImageToScreen(AState,R); T.HasScreenBounds := True;
    ConfidenceData := G.Find('confidence');
    if (ConfidenceData<>nil) and (ConfidenceData.JSONType=jtNumber) then
      try
        T.Confidence := ConfidenceData.AsFloat;
        T.HasConfidence := True;
      except
        T.HasConfidence := False;
      end;
    AddTarget(AState,APublicTargets,T);
  end;
end;

procedure TDesktopSnapshotManager.PruneSnapshots;
begin
  while FSnapshots.Count > 8 do FSnapshots.Delete(0);
end;

function TDesktopSnapshotManager.FindSnapshot(const AId: string): TDesktopSnapshotState;
var I: Integer; S: TDesktopSnapshotState;
begin
  Result := nil;
  for I := 0 to FSnapshots.Count-1 do
  begin
    S := TDesktopSnapshotState(FSnapshots[I]);
    if S.Id=AId then Exit(S);
  end;
end;

function TDesktopSnapshotManager.MostRecentSnapshot: TDesktopSnapshotState;
begin
  if FSnapshots.Count=0 then Exit(nil);
  Result := TDesktopSnapshotState(FSnapshots[FSnapshots.Count-1]);
end;

function TDesktopSnapshotManager.RevalidateVisualTargetCurrent(
  AState: TDesktopSnapshotState; ATarget: TSnapshotTarget): Boolean;
var
  CaptureArgs, Status, GroundStatus: TJSONObject;
  CurrentCapture: TDesktopCaptureResult;
  CurrentHash, ForegroundHandle, WantedText, CandidateText,
  WantedRole, CandidateRole: string;
  Grounded: TJSONArray;
  I, OldCx, OldCy, NewCx, NewCy, Dx, Dy, MaxDx, MaxDy: Integer;
  BestDistance, Distance: Int64;
  G, B: TJSONObject;
  D: TJSONData;
  R, ClippedR, BestRect: TRect;
  Found: Boolean;
begin
  Result := False;
  Status := FRuntime.GetStatus;
  try
    ForegroundHandle := Trim(JsonString(Status,'foreground_window',''));
  finally
    Status.Free;
  end;
  if ForegroundHandle<>UIntToStr(AState.WindowHandle) then
    raise Exception.Create(
      'visual target window is no longer foreground; activate it and take a new desktop_snapshot before clicking');

  CaptureArgs := TJSONObject.Create;
  Grounded := nil;
  GroundStatus := nil;
  try
    CaptureArgs.Add('target','window');
    CaptureArgs.Add('handle',UIntToStr(AState.WindowHandle));
    CaptureArgs.Add('format','png');
    CaptureArgs.Add('max_width',AState.ImageWidth);
    CaptureArgs.Add('max_height',AState.ImageHeight);
    CaptureArgs.Add('max_bytes',FConfig.DesktopMaximumImageBytes);
    CurrentCapture := FRuntime.Capture(CaptureArgs,FConfig.DesktopMaximumImageBytes);
    if (CurrentCapture.SourceX<>AState.SourceX) or
       (CurrentCapture.SourceY<>AState.SourceY) or
       (CurrentCapture.SourceWidth<>AState.SourceWidth) or
       (CurrentCapture.SourceHeight<>AState.SourceHeight) or
       (CurrentCapture.Width<>AState.ImageWidth) or
       (CurrentCapture.Height<>AState.ImageHeight) then
      raise Exception.Create(
        'snapshot is stale because the target window geometry changed; take a new desktop_snapshot');

    CurrentHash := HashBytes(CurrentCapture.Data);
    if CurrentHash=AState.StateHash then Exit(False);

    { A full-window byte hash is deliberately only the fast path. A blinking
      caret, hover state, clock, progress animation, etc. can change unrelated
      pixels without moving the target. When that happens, run the same visual
      grounder again and only accept the click when the target can be
      re-identified near its old box. This keeps stale-target protection without
      making snapshot mode unusable on dynamic desktop UIs. }
    Grounded := FGrounder.Ground(CurrentCapture.Data,CurrentCapture.MimeType,
      GroundStatus);
    if (Grounded=nil) or (Grounded.Count=0) then
      raise Exception.Create(
        'snapshot pixels changed and the visual target could not be re-grounded; take a new desktop_snapshot');

    WantedText := NormalizeText(ATarget.Name);
    WantedRole := LowerCase(Trim(ATarget.Role));
    OldCx := (ATarget.ImageBounds.Left+ATarget.ImageBounds.Right) div 2;
    OldCy := (ATarget.ImageBounds.Top+ATarget.ImageBounds.Bottom) div 2;
    MaxDx := Max(48,(ATarget.ImageBounds.Right-ATarget.ImageBounds.Left)*2);
    MaxDy := Max(36,(ATarget.ImageBounds.Bottom-ATarget.ImageBounds.Top)*2);
    Found := False;
    BestDistance := High(Int64);

    for I := 0 to Grounded.Count-1 do
    begin
      if Grounded.Items[I].JSONType<>jtObject then Continue;
      G := TJSONObject(Grounded.Items[I]);
      CandidateText := Trim(JsonString(G,'text',
        JsonString(G,'name',JsonString(G,'label',''))));
      CandidateRole := LowerCase(Trim(JsonString(G,'role','visual')));
      if CandidateRole='' then CandidateRole := 'visual';
      if CandidateText<>'' then
        CandidateText := NormalizeText(CandidateText)
      else
        CandidateText := '[' + CandidateRole + ']';

      if CandidateText<>WantedText then Continue;
      if (WantedRole<>'') and (CandidateRole<>'') and
         (WantedRole<>CandidateRole) and
         (WantedText='['+WantedRole+']') then Continue;

      D := G.Find('bounds');
      if (D=nil) or (D.JSONType<>jtObject) then Continue;
      B := TJSONObject(D);
      R.Left := JsonInteger(B,'x',-1); R.Top := JsonInteger(B,'y',-1);
      R.Right := R.Left + JsonInteger(B,'width',0);
      R.Bottom := R.Top + JsonInteger(B,'height',0);
      if (R.Left<0) or (R.Top<0) or (R.Right<=R.Left) or
         (R.Bottom<=R.Top) then Continue;
      if not ClipRectToImage(R,AState.ImageWidth,AState.ImageHeight,ClippedR) then
        Continue;
      R := ClippedR;
      NewCx := (R.Left+R.Right) div 2;
      NewCy := (R.Top+R.Bottom) div 2;
      Dx := Abs(NewCx-OldCx);
      Dy := Abs(NewCy-OldCy);
      if (not RectsOverlap(ATarget.ImageBounds,R)) and
         ((Dx>MaxDx) or (Dy>MaxDy)) then Continue;
      Distance := Int64(Dx)*Int64(Dx)+Int64(Dy)*Int64(Dy);
      if (not Found) or (Distance<BestDistance) then
      begin
        Found := True;
        BestDistance := Distance;
        BestRect := R;
      end;
    end;

    if not Found then
      raise Exception.Create(
        'snapshot pixels changed and the selected visual target is no longer at its grounded location; take a new desktop_snapshot');

    { Use the freshly grounded rectangle rather than the old one. The caller
      still supplied only a target number; coordinates stay entirely server-side. }
    ATarget.ImageBounds := BestRect;
    ATarget.HasImageBounds := True;
    ATarget.ScreenBounds := MapImageToScreen(AState,BestRect);
    ATarget.HasScreenBounds := True;
    Result := True;
  finally
    GroundStatus.Free;
    Grounded.Free;
    CaptureArgs.Free;
  end;
end;

function BuildOverlayTargets(AState: TDesktopSnapshotState): TJSONArray;
var
  I: Integer;
  T: TSnapshotTarget;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to AState.Targets.Count - 1 do
  begin
    T := TSnapshotTarget(AState.Targets[I]);
    if not T.HasImageBounds then Continue;
    O := TJSONObject.Create;
    O.Add('target', T.Mark);
    O.Add('bounds', RectToJson(T.ImageBounds));
    Result.Add(O);
  end;
end;

function TDesktopSnapshotManager.CreateSnapshot(AArguments: TJSONObject;
  AMaximumImageBytes: Cardinal; out ACapture: TDesktopCaptureResult): TJSONObject;
var
  HandleText, Resolution: string;
  CaptureArgs: TJSONObject;
  State: TDesktopSnapshotState;
  PublicTargets, Grounded, OverlayTargets: TJSONArray;
  GroundStatus, WindowObj: TJSONObject;
  Previous: TDesktopSnapshotState;
  MaxTargets, SemanticMaxTargets, SemanticCount, VisualCount: Integer;
begin
  EnterCriticalSection(FLock);
  try
    HandleText := ResolveWindowHandle(AArguments,Resolution);
    CaptureArgs := TJSONObject.Create;
    Grounded := nil;
    OverlayTargets := nil;
    GroundStatus := nil;
    State := TDesktopSnapshotState.Create;
    PublicTargets := TJSONArray.Create;
    try
      CaptureArgs.Add('target','window');
      CaptureArgs.Add('handle',HandleText);
      CaptureArgs.Add('format','png');
      CaptureArgs.Add('max_width',JsonInteger(AArguments,'max_width',2048));
      CaptureArgs.Add('max_height',JsonInteger(AArguments,'max_height',2048));
      CaptureArgs.Add('max_bytes',JsonInteger(AArguments,'max_bytes',8388608));
      ACapture := FRuntime.Capture(CaptureArgs,AMaximumImageBytes);
      State.Id := 's' + UIntToStr(FNextId); Inc(FNextId);
      State.WindowHandle := ACapture.WindowHandle;
      State.WindowTitle := ACapture.WindowTitle;
      State.SourceX:=ACapture.SourceX; State.SourceY:=ACapture.SourceY;
      State.SourceWidth:=ACapture.SourceWidth; State.SourceHeight:=ACapture.SourceHeight;
      State.ImageWidth:=ACapture.Width; State.ImageHeight:=ACapture.Height;
      State.StateHash := HashBytes(ACapture.Data);
      MaxTargets := JsonInteger(AArguments,'max_targets',FConfig.DesktopGrounderMaxTargets);
      if MaxTargets<1 then MaxTargets:=1;
      if MaxTargets>500 then MaxTargets:=500;

      { Visual grounding is intentionally independent of UIA. If OCR/detection
        is available, reserve part of the public target budget for it so a noisy
        accessibility tree cannot crowd out the very fallback that snapshot mode
        is meant to provide. If grounding is unavailable, semantics may use the
        full budget. }
      Grounded := FGrounder.Ground(ACapture.Data,ACapture.MimeType,GroundStatus);
      if (Grounded <> nil) and (Grounded.Count > 0) then
        SemanticMaxTargets := Max(1, (MaxTargets * 2) div 3)
      else
        SemanticMaxTargets := MaxTargets;
      AddSemanticTargets(State,PublicTargets,HandleText,SemanticMaxTargets);
      SemanticCount := State.Targets.Count;
      AddVisualTargets(State,PublicTargets,Grounded,MaxTargets);
      VisualCount := State.Targets.Count - SemanticCount;
      OverlayTargets := BuildOverlayTargets(State);
      ACapture.Data := RenderSomOverlay(ACapture.Data,OverlayTargets);

      Result := TJSONObject.Create;
      Result.Add('snapshot_id',State.Id);
      Result.Add('state_hash',State.StateHash);
      Result.Add('consumed',False);
      Result.Add('resolution',Resolution);
      Previous := MostRecentSnapshot;
      if Previous<>nil then
      begin
        Result.Add('previous_snapshot_id',Previous.Id);
        Result.Add('window_changed_from_previous',
          Previous.WindowHandle<>State.WindowHandle);
        if Previous.WindowHandle=State.WindowHandle then
        begin
          Result.Add('state_changed_from_previous',
            Previous.StateHash<>State.StateHash);
          if Previous.StateHash<>State.StateHash then
            Result.Add('progress','state_changed')
          else
            Result.Add('progress','state_unchanged');
        end
        else
          Result.Add('progress','window_changed');
      end
      else
        Result.Add('progress','initial_snapshot');
      WindowObj := TJSONObject.Create;
      WindowObj.Add('handle',UIntToStr(State.WindowHandle));
      WindowObj.Add('title',State.WindowTitle);
      Result.Add('window',WindowObj);
      Result.Add('window_handle',UIntToStr(State.WindowHandle));
      Result.Add('window_title',State.WindowTitle);
      Result.Add('delivery','model_only');
      Result.Add('width',ACapture.Width); Result.Add('height',ACapture.Height);
      Result.Add('targets',PublicTargets); PublicTargets:=nil;
      Result.Add('target_count',State.Targets.Count);
      Result.Add('semantic_target_count',SemanticCount);
      Result.Add('visual_target_count',VisualCount);
      Result.Add('grounding',GroundStatus); GroundStatus:=nil;
      if (Previous<>nil) and (Previous.WindowHandle=State.WindowHandle) and
         (Previous.StateHash=State.StateHash) then
        Result.Add('guidance','Choose a numbered target and call desktop_act with this snapshot_id. Do not infer or estimate x/y coordinates. The clean window state is unchanged from the previous snapshot, so do not blindly repeat the same ineffective action. After any state-changing action, take a new snapshot.')
      else
        Result.Add('guidance','Choose a numbered target and call desktop_act with this snapshot_id. Do not infer or estimate x/y coordinates. After any state-changing action, take a new snapshot.');
      FSnapshots.Add(State); State:=nil;
      PruneSnapshots;
    finally
      PublicTargets.Free;
      State.Free;
      GroundStatus.Free;
      OverlayTargets.Free;
      Grounded.Free;
      CaptureArgs.Free;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TDesktopSnapshotManager.PhysicalClickTarget(AState: TDesktopSnapshotState;
  ATarget: TSnapshotTarget; AArguments: TJSONObject): TJSONObject;
var
  Events: TJSONArray;
  E: TJSONObject;
  CX,CY,NX,NY,I,Clicks: Integer;
  WasRegrounded: Boolean;
begin
  if ATarget.Provider<>'vision' then
    raise Exception.Create(
      'Physical snapshot fallback is reserved for visually grounded targets; take a new desktop_snapshot if a semantic ref became stale');
  if not ATarget.HasScreenBounds then
    raise Exception.Create('Target has no grounded bounding box for physical fallback');
  WasRegrounded := RevalidateVisualTargetCurrent(AState,ATarget);
  CX := (ATarget.ScreenBounds.Left + ATarget.ScreenBounds.Right) div 2;
  CY := (ATarget.ScreenBounds.Top + ATarget.ScreenBounds.Bottom) div 2;
  NX := Round((CX-AState.SourceX)*1000/AState.SourceWidth);
  NY := Round((CY-AState.SourceY)*1000/AState.SourceHeight);
  NX := EnsureRange(NX,0,1000); NY := EnsureRange(NY,0,1000);
  Clicks := JsonInteger(AArguments,'clicks',1);
  if (Clicks<1) or (Clicks>2) then raise Exception.Create('clicks must be 1 or 2');
  Events := TJSONArray.Create;
  E := TJSONObject.Create;
  E.Add('type','mouse_move_window'); E.Add('handle',UIntToStr(AState.WindowHandle));
  E.Add('x',NX); E.Add('y',NY); E.Add('activate',True); E.Add('require_foreground',True);
  Events.Add(E);
  for I := 1 to Clicks do
  begin
    E := TJSONObject.Create; E.Add('type','mouse_button');
    E.Add('button',JsonString(AArguments,'button','left')); E.Add('state','click'); Events.Add(E);
  end;
  E := TJSONObject.Create; E.Add('events',Events);
  try
    Result := FRuntime.SendInput(E);
    Result.Add('resolved_action','grounded_click');
    Result.Add('grounded_not_guessed',True);
    Result.Add('regrounded_after_pixel_change',WasRegrounded);
  finally
    E.Free;
  end;
end;

function TDesktopSnapshotManager.Act(AArguments: TJSONObject): TJSONObject;
var
  SnapshotId, ActionName: string;
  Mark: Integer;
  State: TDesktopSnapshotState;
  Target: TSnapshotTarget;
  SemanticArgs: TJSONObject;
  DirectResult: TJSONObject;
  DirectError: string;
  CanFallback: Boolean;
  I: Integer;
begin
  EnterCriticalSection(FLock);
  try
    SnapshotId := Trim(JsonString(AArguments,'snapshot_id',''));
    if SnapshotId='' then raise Exception.Create('snapshot_id is required');
    Mark := JsonInteger(AArguments,'target',0);
    if Mark<1 then raise Exception.Create('target must be a positive numbered target from desktop_snapshot');
    State := FindSnapshot(SnapshotId);
    if State=nil then raise Exception.Create('snapshot_id is unknown or expired; take a new desktop_snapshot');
    if State.Consumed then raise Exception.Create('snapshot is stale/consumed; take a new desktop_snapshot');
    Target := State.FindTarget(Mark);
    if Target=nil then raise Exception.Create('target does not exist in this snapshot');
    ActionName := LowerCase(Trim(JsonString(AArguments,'action','activate')));
    DirectError := '';
    DirectResult := nil;

    if Target.ProviderRef<>'' then
    begin
      SemanticArgs := TJSONObject.Create;
      try
        SemanticArgs.Add('handle',UIntToStr(State.WindowHandle));
        SemanticArgs.Add('ref',Target.ProviderRef);
        SemanticArgs.Add('action',ActionName);
        if AArguments.Find('value')<>nil then SemanticArgs.Add('value',JsonString(AArguments,'value'));
        if AArguments.Find('button')<>nil then SemanticArgs.Add('button',JsonString(AArguments,'button'));
        if AArguments.Find('clicks')<>nil then SemanticArgs.Add('clicks',JsonInteger(AArguments,'clicks',1));
        try
          DirectResult := FRuntime.PerformUiAction(SemanticArgs);
        except
          on E: Exception do DirectError := E.Message;
        end;
      finally
        SemanticArgs.Free;
      end;
    end;

    CanFallback := (ActionName='activate') or (ActionName='click') or
      (ActionName='invoke') or (ActionName='select');
    if (DirectResult=nil) and CanFallback and (Target.Provider='vision') and
       Target.HasScreenBounds then
      DirectResult := PhysicalClickTarget(State,Target,AArguments);
    if DirectResult=nil then
    begin
      State.Consumed := True;
      if DirectError<>'' then raise Exception.Create(DirectError)
      else raise Exception.Create('Target cannot perform action=' + ActionName);
    end;
    { Any successful GUI action can invalidate observations of every window, not
      just the snapshot used for this action (modals can open/close elsewhere). }
    for I := 0 to FSnapshots.Count-1 do
      TDesktopSnapshotState(FSnapshots[I]).Consumed := True;
    DirectResult.Add('snapshot_id',State.Id);
    DirectResult.Add('target',Mark);
    DirectResult.Add('target_name',Target.Name);
    DirectResult.Add('target_source',Target.Provider);
    DirectResult.Add('snapshot_consumed',True);
    DirectResult.Add('next','Take a fresh desktop_snapshot before choosing the next target.');
    Result := DirectResult;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TDesktopSnapshotManager.InvalidateAll;
var I: Integer;
begin
  EnterCriticalSection(FLock);
  try
    for I := 0 to FSnapshots.Count-1 do
      TDesktopSnapshotState(FSnapshots[I]).Consumed := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
