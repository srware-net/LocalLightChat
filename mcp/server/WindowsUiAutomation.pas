unit WindowsUiAutomation;

{$mode objfpc}{$H+}
{$interfaces com}

interface

uses
  SysUtils, fpjson;

type
  TWindowsUiAutomation = class
  public
    class function GetStatus: TJSONObject;
    class function ListElements(AArguments: TJSONObject): TJSONObject;
    class function PerformAction(AArguments: TJSONObject): TJSONObject;
  end;

implementation

uses
  Windows, ActiveX, Variants, McpJson, WindowsNativeControls;

const
  CLSID_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';
  IID_IUIAutomation: TGUID = '{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}';

  UIA_InvokePatternId = 10000;
  UIA_ValuePatternId = 10002;
  UIA_ExpandCollapsePatternId = 10005;
  UIA_SelectionItemPatternId = 10010;
  UIA_TogglePatternId = 10015;
  UIA_ScrollItemPatternId = 10017;
  UIA_LegacyIAccessiblePatternId = 10018;

  TreeScope_Descendants = $4;

  ExpandCollapseState_Collapsed = 0;
  ExpandCollapseState_Expanded = 1;
  ExpandCollapseState_PartiallyExpanded = 2;
  ExpandCollapseState_LeafNode = 3;

  RPC_E_CHANGED_MODE_VALUE = HRESULT(-2147417850);

type
  IUIAutomationElement = interface;
  IUIAutomationElementArray = interface;
  IUIAutomationCondition = interface;
  IUIAutomationCacheRequest = interface;
  IUIAutomationTreeWalker = interface;

  IUIAutomationCondition = interface(IUnknown)
    ['{352FFBA8-0973-437C-A61F-F64CAFD81DF9}']
  end;

  IUIAutomationCacheRequest = interface(IUnknown)
    ['{B32A92B5-BC25-4078-9C08-D7EE95C48E03}']
  end;

  IUIAutomationTreeWalker = interface(IUnknown)
    ['{4042C624-389C-4AFC-A630-9DF854A541FC}']
    function GetParentElement(AElement: IUIAutomationElement;
      out AParent: IUIAutomationElement): HRESULT; stdcall;
  end;

  IUIAutomationElementArray = interface(IUnknown)
    ['{14314595-B4BC-4055-95F2-58F2E42C9855}']
    function get_Length(out ALength: Integer): HRESULT; stdcall;
    function GetElement(AIndex: Integer;
      out AElement: IUIAutomationElement): HRESULT; stdcall;
  end;

  IUIAutomationInvokePattern = interface(IUnknown)
    ['{FB377FBE-8EA6-46D5-9C73-6499642D3059}']
    function Invoke: HRESULT; stdcall;
  end;

  IUIAutomationValuePattern = interface(IUnknown)
    ['{A94CD8B1-0844-4CD6-9D2D-640537AB39E9}']
    function SetValue(AValue: WideString): HRESULT; stdcall;
    function get_CurrentValue(out AValue: WideString): HRESULT; stdcall;
    function get_CurrentIsReadOnly(out AValue: LongBool): HRESULT; stdcall;
    function get_CachedValue(out AValue: WideString): HRESULT; stdcall;
    function get_CachedIsReadOnly(out AValue: LongBool): HRESULT; stdcall;
  end;

  IUIAutomationTogglePattern = interface(IUnknown)
    ['{94CF8058-9B8D-4AB9-8BFD-4CD0A33C8C70}']
    function Toggle: HRESULT; stdcall;
    function get_CurrentToggleState(out AState: Integer): HRESULT; stdcall;
    function get_CachedToggleState(out AState: Integer): HRESULT; stdcall;
  end;

  IUIAutomationSelectionItemPattern = interface(IUnknown)
    ['{A8EFA66A-0FDA-421A-9194-38021F3578EA}']
    function Select: HRESULT; stdcall;
    function AddToSelection: HRESULT; stdcall;
    function RemoveFromSelection: HRESULT; stdcall;
    function get_CurrentIsSelected(out AValue: LongBool): HRESULT; stdcall;
    function get_CurrentSelectionContainer(
      out AElement: IUIAutomationElement): HRESULT; stdcall;
    function get_CachedIsSelected(out AValue: LongBool): HRESULT; stdcall;
    function get_CachedSelectionContainer(
      out AElement: IUIAutomationElement): HRESULT; stdcall;
  end;

  IUIAutomationExpandCollapsePattern = interface(IUnknown)
    ['{619BE086-1F4E-4EE4-BAFA-210128738730}']
    function Expand: HRESULT; stdcall;
    function Collapse: HRESULT; stdcall;
    function get_CurrentExpandCollapseState(out AState: Integer): HRESULT; stdcall;
    function get_CachedExpandCollapseState(out AState: Integer): HRESULT; stdcall;
  end;

  IUIAutomationScrollItemPattern = interface(IUnknown)
    ['{B488300F-D015-4F19-9C29-BB595E3645EF}']
    function ScrollIntoView: HRESULT; stdcall;
  end;

  IUIAutomationLegacyIAccessiblePattern = interface(IUnknown)
    ['{828055AD-355B-4435-86D5-3B51C14A9B1B}']
    function Select(AFlagsSelect: Integer): HRESULT; stdcall;
    function DoDefaultAction: HRESULT; stdcall;
    function SetValue(AValue: WideString): HRESULT; stdcall;
    function get_CurrentChildId(out AValue: Integer): HRESULT; stdcall;
    function get_CurrentName(out AValue: WideString): HRESULT; stdcall;
    function get_CurrentValue(out AValue: WideString): HRESULT; stdcall;
    function get_CurrentDescription(out AValue: WideString): HRESULT; stdcall;
    function get_CurrentRole(out AValue: Cardinal): HRESULT; stdcall;
    function get_CurrentState(out AValue: Cardinal): HRESULT; stdcall;
    function get_CurrentHelp(out AValue: WideString): HRESULT; stdcall;
    function get_CurrentKeyboardShortcut(out AValue: WideString): HRESULT; stdcall;
    function GetCurrentSelection(out AValue: IUIAutomationElementArray): HRESULT; stdcall;
    function get_CurrentDefaultAction(out AValue: WideString): HRESULT; stdcall;
  end;

  IUIAutomationElement = interface(IUnknown)
    ['{D22108AA-8AC5-49A5-837B-37BBB3D7591E}']
    function SetFocus: HRESULT; stdcall;
    function GetRuntimeId(out ARuntimeId: Pointer): HRESULT; stdcall;
    function FindFirst(AScope: Integer; ACondition: IUIAutomationCondition;
      out AFound: IUIAutomationElement): HRESULT; stdcall;
    function FindAll(AScope: Integer; ACondition: IUIAutomationCondition;
      out AFound: IUIAutomationElementArray): HRESULT; stdcall;
    function FindFirstBuildCache(AScope: Integer;
      ACondition: IUIAutomationCondition; ACacheRequest: IUIAutomationCacheRequest;
      out AFound: IUIAutomationElement): HRESULT; stdcall;
    function FindAllBuildCache(AScope: Integer;
      ACondition: IUIAutomationCondition; ACacheRequest: IUIAutomationCacheRequest;
      out AFound: IUIAutomationElementArray): HRESULT; stdcall;
    function BuildUpdatedCache(ACacheRequest: IUIAutomationCacheRequest;
      out AUpdatedElement: IUIAutomationElement): HRESULT; stdcall;
    function GetCurrentPropertyValue(APropertyId: Integer;
      out ARetVal: OleVariant): HRESULT; stdcall;
    function GetCurrentPropertyValueEx(APropertyId: Integer;
      AIgnoreDefaultValue: LongBool; out ARetVal: OleVariant): HRESULT; stdcall;
    function GetCachedPropertyValue(APropertyId: Integer;
      out ARetVal: OleVariant): HRESULT; stdcall;
    function GetCachedPropertyValueEx(APropertyId: Integer;
      AIgnoreDefaultValue: LongBool; out ARetVal: OleVariant): HRESULT; stdcall;
    function GetCurrentPatternAs(APatternId: Integer; const AIid: TGUID;
      out APatternObject: Pointer): HRESULT; stdcall;
    function GetCachedPatternAs(APatternId: Integer; const AIid: TGUID;
      out APatternObject: Pointer): HRESULT; stdcall;
    function GetCurrentPattern(APatternId: Integer;
      out APatternObject: IUnknown): HRESULT; stdcall;
    function GetCachedPattern(APatternId: Integer;
      out APatternObject: IUnknown): HRESULT; stdcall;
    function GetCachedParent(out AParent: IUIAutomationElement): HRESULT; stdcall;
    function GetCachedChildren(
      out AChildren: IUIAutomationElementArray): HRESULT; stdcall;
    function get_CurrentProcessId(out ARetVal: Integer): HRESULT; stdcall;
    function get_CurrentControlType(out ARetVal: Integer): HRESULT; stdcall;
    function get_CurrentLocalizedControlType(
      out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentName(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentAcceleratorKey(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentAccessKey(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentHasKeyboardFocus(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentIsKeyboardFocusable(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentIsEnabled(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentAutomationId(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentClassName(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentHelpText(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentCulture(out ARetVal: Integer): HRESULT; stdcall;
    function get_CurrentIsControlElement(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentIsContentElement(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentIsPassword(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentNativeWindowHandle(out ARetVal: HWND): HRESULT; stdcall;
    function get_CurrentItemType(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentIsOffscreen(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentOrientation(out ARetVal: Integer): HRESULT; stdcall;
    function get_CurrentFrameworkId(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentIsRequiredForForm(out ARetVal: LongBool): HRESULT; stdcall;
    function get_CurrentItemStatus(out ARetVal: WideString): HRESULT; stdcall;
    function get_CurrentBoundingRectangle(out ARetVal: TRect): HRESULT; stdcall;

    { IUIAutomationElement::GetClickablePoint is the last method of the base
      interface. These placeholders preserve the exact vtable slots between
      CurrentBoundingRectangle and GetClickablePoint without making this unit
      depend on every rarely-used UIA property type. Do not call them. }
    function _Reserved01: HRESULT; stdcall;
    function _Reserved02: HRESULT; stdcall;
    function _Reserved03: HRESULT; stdcall;
    function _Reserved04: HRESULT; stdcall;
    function _Reserved05: HRESULT; stdcall;
    function _Reserved06: HRESULT; stdcall;
    function _Reserved07: HRESULT; stdcall;
    function _Reserved08: HRESULT; stdcall;
    function _Reserved09: HRESULT; stdcall;
    function _Reserved10: HRESULT; stdcall;
    function _Reserved11: HRESULT; stdcall;
    function _Reserved12: HRESULT; stdcall;
    function _Reserved13: HRESULT; stdcall;
    function _Reserved14: HRESULT; stdcall;
    function _Reserved15: HRESULT; stdcall;
    function _Reserved16: HRESULT; stdcall;
    function _Reserved17: HRESULT; stdcall;
    function _Reserved18: HRESULT; stdcall;
    function _Reserved19: HRESULT; stdcall;
    function _Reserved20: HRESULT; stdcall;
    function _Reserved21: HRESULT; stdcall;
    function _Reserved22: HRESULT; stdcall;
    function _Reserved23: HRESULT; stdcall;
    function _Reserved24: HRESULT; stdcall;
    function _Reserved25: HRESULT; stdcall;
    function _Reserved26: HRESULT; stdcall;
    function _Reserved27: HRESULT; stdcall;
    function _Reserved28: HRESULT; stdcall;
    function _Reserved29: HRESULT; stdcall;
    function _Reserved30: HRESULT; stdcall;
    function _Reserved31: HRESULT; stdcall;
    function _Reserved32: HRESULT; stdcall;
    function _Reserved33: HRESULT; stdcall;
    function _Reserved34: HRESULT; stdcall;
    function _Reserved35: HRESULT; stdcall;
    function _Reserved36: HRESULT; stdcall;
    function _Reserved37: HRESULT; stdcall;
    function _Reserved38: HRESULT; stdcall;
    function _Reserved39: HRESULT; stdcall;
    function _Reserved40: HRESULT; stdcall;
    function GetClickablePoint(out APoint: TPoint;
      out AGotClickable: LongBool): HRESULT; stdcall;
  end;

  IUIAutomation = interface(IUnknown)
    ['{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}']
    function CompareElements(AElement1, AElement2: IUIAutomationElement;
      out AAreSame: LongBool): HRESULT; stdcall;
    function CompareRuntimeIds(ARuntimeId1, ARuntimeId2: Pointer;
      out AAreSame: LongBool): HRESULT; stdcall;
    function GetRootElement(out ARoot: IUIAutomationElement): HRESULT; stdcall;
    function ElementFromHandle(AWindow: HWND;
      out AElement: IUIAutomationElement): HRESULT; stdcall;
    function ElementFromPoint(APoint: TPoint;
      out AElement: IUIAutomationElement): HRESULT; stdcall;
    function GetFocusedElement(out AElement: IUIAutomationElement): HRESULT; stdcall;
    function GetRootElementBuildCache(ACacheRequest: IUIAutomationCacheRequest;
      out ARoot: IUIAutomationElement): HRESULT; stdcall;
    function ElementFromHandleBuildCache(AWindow: HWND;
      ACacheRequest: IUIAutomationCacheRequest;
      out AElement: IUIAutomationElement): HRESULT; stdcall;
    function ElementFromPointBuildCache(APoint: TPoint;
      ACacheRequest: IUIAutomationCacheRequest;
      out AElement: IUIAutomationElement): HRESULT; stdcall;
    function GetFocusedElementBuildCache(ACacheRequest: IUIAutomationCacheRequest;
      out AElement: IUIAutomationElement): HRESULT; stdcall;
    function CreateTreeWalker(ACondition: IUIAutomationCondition;
      out AWalker: IUIAutomationTreeWalker): HRESULT; stdcall;
    function get_ControlViewWalker(out AWalker: IUIAutomationTreeWalker): HRESULT; stdcall;
    function get_ContentViewWalker(out AWalker: IUIAutomationTreeWalker): HRESULT; stdcall;
    function get_RawViewWalker(out AWalker: IUIAutomationTreeWalker): HRESULT; stdcall;
    function get_RawViewCondition(
      out ACondition: IUIAutomationCondition): HRESULT; stdcall;
    function get_ControlViewCondition(
      out ACondition: IUIAutomationCondition): HRESULT; stdcall;
    function get_ContentViewCondition(
      out ACondition: IUIAutomationCondition): HRESULT; stdcall;
    function CreateCacheRequest(
      out ACacheRequest: IUIAutomationCacheRequest): HRESULT; stdcall;
    function CreateTrueCondition(
      out ACondition: IUIAutomationCondition): HRESULT; stdcall;
  end;

  TUiElementInfo = record
    Name: string;
    AutomationId: string;
    LocalizedControlType: string;
    ControlType: string;
    ControlTypeId: Integer;
    ClassName: string;
    FrameworkId: string;
    ProcessId: Integer;
    Enabled: Boolean;
    Offscreen: Boolean;
    Focused: Boolean;
    Focusable: Boolean;
    Bounds: TRect;
    HasBounds: Boolean;
    CanInvoke: Boolean;
    CanSetValue: Boolean;
    CanToggle: Boolean;
    CanSelect: Boolean;
    CanExpandCollapse: Boolean;
    ExpandCollapseState: Integer;
    CanScrollIntoView: Boolean;
    CanLegacyDefault: Boolean;
    LegacyDefaultAction: string;
  end;

function HResultSucceeded(AResult: HRESULT): Boolean; inline;
begin
  Result := AResult >= 0;
end;

function WinBool(AValue: LongBool): Boolean; inline;
begin
  Result := Boolean(AValue);
end;

procedure CheckHResult(AResult: HRESULT; const AOperation: string);
begin
  if not HResultSucceeded(AResult) then
    raise Exception.CreateFmt('%s failed with HRESULT 0x%.8x',
      [AOperation, Cardinal(AResult)]);
end;

function Utf8FromWide(const AValue: WideString): string;
begin
  Result := string(UTF8Encode(UnicodeString(AValue)));
end;

function ReadWindowHandle(AArguments: TJSONObject): HWND;
var
  HandleText: string;
  HandleValue: QWord;
begin
  HandleText := Trim(JsonString(AArguments, 'handle', ''));
  if HandleText = '' then
    raise Exception.Create('handle is required');
  if not TryStrToQWord(HandleText, HandleValue) then
    raise Exception.Create('handle must be an unsigned integer string');
  Result := HWND(PtrUInt(HandleValue));
  if (Result = 0) or (not WinBool(IsWindow(Result))) then
    raise Exception.Create('handle does not identify a current Windows window');
end;

function ControlTypeName(AControlTypeId: Integer): string;
begin
  case AControlTypeId of
    50000: Result := 'button';
    50001: Result := 'calendar';
    50002: Result := 'check_box';
    50003: Result := 'combo_box';
    50004: Result := 'edit';
    50005: Result := 'hyperlink';
    50006: Result := 'image';
    50007: Result := 'list_item';
    50008: Result := 'list';
    50009: Result := 'menu';
    50010: Result := 'menu_bar';
    50011: Result := 'menu_item';
    50012: Result := 'progress_bar';
    50013: Result := 'radio_button';
    50014: Result := 'scroll_bar';
    50015: Result := 'slider';
    50016: Result := 'spinner';
    50017: Result := 'status_bar';
    50018: Result := 'tab';
    50019: Result := 'tab_item';
    50020: Result := 'text';
    50021: Result := 'tool_bar';
    50022: Result := 'tool_tip';
    50023: Result := 'tree';
    50024: Result := 'tree_item';
    50025: Result := 'custom';
    50026: Result := 'group';
    50027: Result := 'thumb';
    50028: Result := 'data_grid';
    50029: Result := 'data_item';
    50030: Result := 'document';
    50031: Result := 'split_button';
    50032: Result := 'window';
    50033: Result := 'pane';
    50034: Result := 'header';
    50035: Result := 'header_item';
    50036: Result := 'table';
    50037: Result := 'title_bar';
    50038: Result := 'separator';
    50039: Result := 'semantic_zoom';
    50040: Result := 'app_bar';
  else
    Result := 'control_' + IntToStr(AControlTypeId);
  end;
end;

function ExpandCollapseStateName(AState: Integer): string;
begin
  case AState of
    ExpandCollapseState_Collapsed: Result := 'collapsed';
    ExpandCollapseState_Expanded: Result := 'expanded';
    ExpandCollapseState_PartiallyExpanded: Result := 'partially_expanded';
    ExpandCollapseState_LeafNode: Result := 'leaf';
  else
    Result := 'unknown_' + IntToStr(AState);
  end;
end;

function SupportsPattern(AElement: IUIAutomationElement;
  APatternId: Integer): Boolean;
var
  PatternObject: IUnknown;
  HR: HRESULT;
begin
  PatternObject := nil;
  HR := AElement.GetCurrentPattern(APatternId, PatternObject);
  Result := HResultSucceeded(HR) and Assigned(PatternObject);
end;

procedure ReadElementInfo(AElement: IUIAutomationElement;
  out AInfo: TUiElementInfo);
var
  WideValue: WideString;
  BoolValue: LongBool;
  IntegerValue: Integer;
  RectValue: TRect;
  PatternObject: IUnknown;
  ExpandPattern: IUIAutomationExpandCollapsePattern;
  LegacyPattern: IUIAutomationLegacyIAccessiblePattern;
begin
  AInfo.Name := '';
  AInfo.AutomationId := '';
  AInfo.LocalizedControlType := '';
  AInfo.ControlType := '';
  AInfo.ControlTypeId := 0;
  AInfo.ClassName := '';
  AInfo.FrameworkId := '';
  AInfo.ProcessId := 0;
  AInfo.Enabled := False;
  AInfo.Offscreen := False;
  AInfo.Focused := False;
  AInfo.Focusable := False;
  FillChar(AInfo.Bounds, SizeOf(AInfo.Bounds), 0);
  AInfo.HasBounds := False;
  AInfo.CanInvoke := False;
  AInfo.CanSetValue := False;
  AInfo.CanToggle := False;
  AInfo.CanSelect := False;
  AInfo.CanExpandCollapse := False;
  AInfo.ExpandCollapseState := -1;
  AInfo.CanScrollIntoView := False;
  AInfo.CanLegacyDefault := False;
  AInfo.LegacyDefaultAction := '';

  WideValue := '';
  if HResultSucceeded(AElement.get_CurrentName(WideValue)) then
    AInfo.Name := Utf8FromWide(WideValue);
  WideValue := '';
  if HResultSucceeded(AElement.get_CurrentAutomationId(WideValue)) then
    AInfo.AutomationId := Utf8FromWide(WideValue);
  WideValue := '';
  if HResultSucceeded(AElement.get_CurrentLocalizedControlType(WideValue)) then
    AInfo.LocalizedControlType := Utf8FromWide(WideValue);
  WideValue := '';
  if HResultSucceeded(AElement.get_CurrentClassName(WideValue)) then
    AInfo.ClassName := Utf8FromWide(WideValue);
  WideValue := '';
  if HResultSucceeded(AElement.get_CurrentFrameworkId(WideValue)) then
    AInfo.FrameworkId := Utf8FromWide(WideValue);

  IntegerValue := 0;
  if HResultSucceeded(AElement.get_CurrentControlType(IntegerValue)) then
  begin
    AInfo.ControlTypeId := IntegerValue;
    AInfo.ControlType := ControlTypeName(IntegerValue);
  end;
  IntegerValue := 0;
  if HResultSucceeded(AElement.get_CurrentProcessId(IntegerValue)) then
    AInfo.ProcessId := IntegerValue;

  BoolValue := False;
  if HResultSucceeded(AElement.get_CurrentIsEnabled(BoolValue)) then
    AInfo.Enabled := WinBool(BoolValue);
  BoolValue := False;
  if HResultSucceeded(AElement.get_CurrentIsOffscreen(BoolValue)) then
    AInfo.Offscreen := WinBool(BoolValue);
  BoolValue := False;
  if HResultSucceeded(AElement.get_CurrentHasKeyboardFocus(BoolValue)) then
    AInfo.Focused := WinBool(BoolValue);
  BoolValue := False;
  if HResultSucceeded(AElement.get_CurrentIsKeyboardFocusable(BoolValue)) then
    AInfo.Focusable := WinBool(BoolValue);

  FillChar(RectValue, SizeOf(RectValue), 0);
  if HResultSucceeded(AElement.get_CurrentBoundingRectangle(RectValue)) then
  begin
    AInfo.Bounds := RectValue;
    AInfo.HasBounds := (RectValue.Right > RectValue.Left) and
      (RectValue.Bottom > RectValue.Top);
  end;

  AInfo.CanInvoke := SupportsPattern(AElement, UIA_InvokePatternId);
  AInfo.CanSetValue := SupportsPattern(AElement, UIA_ValuePatternId);
  AInfo.CanToggle := SupportsPattern(AElement, UIA_TogglePatternId);
  AInfo.CanSelect := SupportsPattern(AElement, UIA_SelectionItemPatternId);
  AInfo.CanExpandCollapse := SupportsPattern(AElement, UIA_ExpandCollapsePatternId);
  AInfo.CanScrollIntoView := SupportsPattern(AElement, UIA_ScrollItemPatternId);
  AInfo.CanLegacyDefault := SupportsPattern(AElement,
    UIA_LegacyIAccessiblePatternId);

  if AInfo.CanExpandCollapse then
  begin
    PatternObject := nil;
    ExpandPattern := nil;
    if HResultSucceeded(AElement.GetCurrentPattern(UIA_ExpandCollapsePatternId,
      PatternObject)) and
      Supports(PatternObject, IUIAutomationExpandCollapsePattern,
        ExpandPattern) then
    begin
      IntegerValue := -1;
      if HResultSucceeded(ExpandPattern.get_CurrentExpandCollapseState(
        IntegerValue)) then
        AInfo.ExpandCollapseState := IntegerValue;
    end;
  end;

  if AInfo.CanLegacyDefault then
  begin
    PatternObject := nil;
    LegacyPattern := nil;
    if HResultSucceeded(AElement.GetCurrentPattern(
      UIA_LegacyIAccessiblePatternId, PatternObject)) and
      Supports(PatternObject, IUIAutomationLegacyIAccessiblePattern,
        LegacyPattern) then
    begin
      { UIA normally maps the MSAA accessible name into CurrentName. Some
        legacy providers only expose it through LegacyIAccessible, so keep
        that as a fallback for native/older controls. }
      if Trim(AInfo.Name) = '' then
      begin
        WideValue := '';
        if HResultSucceeded(LegacyPattern.get_CurrentName(WideValue)) then
          AInfo.Name := Utf8FromWide(WideValue);
      end;
      WideValue := '';
      if HResultSucceeded(LegacyPattern.get_CurrentDefaultAction(WideValue)) then
        AInfo.LegacyDefaultAction := Utf8FromWide(WideValue);

      { A LegacyIAccessible pattern existing does not guarantee that the node
        actually has a default action. Keep activate from selecting a dead-end
        legacy path when a verified physical click is available instead. }
      AInfo.CanLegacyDefault := Trim(AInfo.LegacyDefaultAction) <> '';
    end
    else
      AInfo.CanLegacyDefault := False;
  end;
end;

function IsActionable(const AInfo: TUiElementInfo): Boolean;
begin
  Result := AInfo.CanInvoke or AInfo.CanSetValue or AInfo.CanToggle or
    AInfo.CanSelect or AInfo.CanExpandCollapse or AInfo.CanScrollIntoView or
    AInfo.CanLegacyDefault or AInfo.Focusable or
    (AInfo.HasBounds and (Trim(AInfo.Name) <> ''));
end;

function HashElementInfo(const AInfo: TUiElementInfo): Cardinal;
var
  S: string;
  I: Integer;
begin
  S := AInfo.Name + #0 + AInfo.AutomationId + #0 + AInfo.ControlType + #0 +
    AInfo.LocalizedControlType + #0 + AInfo.ClassName + #0 +
    IntToStr(AInfo.Bounds.Left) + ',' + IntToStr(AInfo.Bounds.Top) + ',' +
    IntToStr(AInfo.Bounds.Right) + ',' + IntToStr(AInfo.Bounds.Bottom);
  Result := Cardinal($811C9DC5);
  for I := 1 to Length(S) do
  begin
    Result := Result xor Ord(S[I]);
    Result := Cardinal((QWord(Result) * QWord(16777619)) and QWord($FFFFFFFF));
  end;
end;

function ViewPrefix(const AView: string): Char;
begin
  if AView = 'raw' then
    Result := 'r'
  else if AView = 'content' then
    Result := 'n'
  else
    Result := 'c';
end;

function BuildElementRef(const AView: string; ASourceIndex: Integer;
  const AInfo: TUiElementInfo): string;
begin
  Result := ViewPrefix(AView);
  Result := Result + IntToStr(ASourceIndex) + '-' +
    LowerCase(IntToHex(HashElementInfo(AInfo), 8));
end;

function ParseElementRef(const ARef: string; out AView: string;
  out ASourceIndex: Integer): Boolean;
var
  DashPos: Integer;
  IndexText: string;
begin
  Result := False;
  AView := '';
  ASourceIndex := -1;
  if Length(ARef) < 4 then
    Exit;
  case ARef[1] of
    'c', 'C': AView := 'control';
    'r', 'R': AView := 'raw';
    'n', 'N': AView := 'content';
  else
    Exit;
  end;
  DashPos := Pos('-', ARef);
  if DashPos <= 2 then
    Exit;
  IndexText := Copy(ARef, 2, DashPos - 2);
  if not TryStrToInt(IndexText, ASourceIndex) then
    Exit;
  Result := ASourceIndex >= 0;
end;

function ElementInfoToJson(const AInfo: TUiElementInfo;
  ASourceIndex: Integer; const AView: string; ADetails: Boolean): TJSONObject;
var
  Bounds: TJSONObject;
  Actions: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.Add('ref', BuildElementRef(AView, ASourceIndex, AInfo));
  Result.Add('source_index', ASourceIndex);
  Result.Add('view', AView);
  Result.Add('name', AInfo.Name);
  Result.Add('automation_id', AInfo.AutomationId);
  Result.Add('control_type', AInfo.ControlType);
  Result.Add('enabled', AInfo.Enabled);
  Result.Add('offscreen', AInfo.Offscreen);

  if AInfo.HasBounds then
  begin
    Bounds := TJSONObject.Create;
    Bounds.Add('x', AInfo.Bounds.Left);
    Bounds.Add('y', AInfo.Bounds.Top);
    Bounds.Add('width', AInfo.Bounds.Right - AInfo.Bounds.Left);
    Bounds.Add('height', AInfo.Bounds.Bottom - AInfo.Bounds.Top);
    Result.Add('bounds', Bounds);
  end;

  if AInfo.CanExpandCollapse and (AInfo.ExpandCollapseState >= 0) then
    Result.Add('expand_collapse_state',
      ExpandCollapseStateName(AInfo.ExpandCollapseState));

  if ADetails then
  begin
    Result.Add('control_type_id', AInfo.ControlTypeId);
    Result.Add('localized_control_type', AInfo.LocalizedControlType);
    Result.Add('class_name', AInfo.ClassName);
    Result.Add('framework_id', AInfo.FrameworkId);
    Result.Add('process_id', AInfo.ProcessId);
    Result.Add('focused', AInfo.Focused);
    Result.Add('focusable', AInfo.Focusable);
    Result.Add('legacy_default_action', AInfo.LegacyDefaultAction);
  end;

  Actions := TJSONArray.Create;
  if IsActionable(AInfo) then Actions.Add('activate');
  if AInfo.CanInvoke then Actions.Add('invoke');
  if AInfo.CanSetValue then Actions.Add('set_value');
  if AInfo.CanToggle then Actions.Add('toggle');
  if AInfo.CanSelect then Actions.Add('select');
  if AInfo.CanExpandCollapse then
  begin
    if AInfo.ExpandCollapseState <> ExpandCollapseState_LeafNode then
    begin
      if AInfo.ExpandCollapseState <> ExpandCollapseState_Expanded then
        Actions.Add('expand');
      if AInfo.ExpandCollapseState <> ExpandCollapseState_Collapsed then
        Actions.Add('collapse');
    end;
  end;
  if AInfo.CanScrollIntoView then Actions.Add('scroll_into_view');
  if AInfo.CanLegacyDefault then Actions.Add('legacy_default');
  if AInfo.Focusable then Actions.Add('focus');
  if AInfo.HasBounds then Actions.Add('click');
  Result.Add('actions', Actions);
end;

function TextMatches(const AActual, AExpected, AMatchMode: string): Boolean;
var
  ActualText, ExpectedText: string;
begin
  if AExpected = '' then
    Exit(True);
  ActualText := LowerCase(Trim(AActual));
  ExpectedText := LowerCase(Trim(AExpected));
  if AMatchMode = 'contains' then
    Result := Pos(ExpectedText, ActualText) > 0
  else
    Result := ActualText = ExpectedText;
end;

function InfoMatches(const AInfo: TUiElementInfo; const AName,
  AAutomationId, AControlType, AQuery, AMatchMode: string): Boolean;
var
  QueryText, SearchText: string;
begin
  Result := TextMatches(AInfo.Name, AName, AMatchMode) and
    TextMatches(AInfo.AutomationId, AAutomationId, AMatchMode) and
    (TextMatches(AInfo.ControlType, AControlType, AMatchMode) or
      TextMatches(AInfo.LocalizedControlType, AControlType, AMatchMode));
  if not Result then
    Exit;
  QueryText := LowerCase(Trim(AQuery));
  if QueryText = '' then
    Exit(True);
  SearchText := LowerCase(AInfo.Name + #10 + AInfo.AutomationId + #10 +
    AInfo.ControlType + #10 + AInfo.LocalizedControlType + #10 +
    AInfo.ClassName);
  Result := Pos(QueryText, SearchText) > 0;
end;

function NormalizeViewName(const AView: string): string;
begin
  Result := LowerCase(Trim(AView));
  if Result = '' then
    Result := 'auto';
  if (Result <> 'auto') and (Result <> 'control') and
     (Result <> 'content') and (Result <> 'raw') and (Result <> 'native') then
    raise Exception.Create('view must be auto, control, content, raw, or native');
end;

procedure InitializeAutomation(out AAutomation: IUIAutomation;
  out ACoInitialized: Boolean);
var
  HR: HRESULT;
begin
  AAutomation := nil;
  ACoInitialized := False;
  HR := CoInitializeEx(nil, COINIT_MULTITHREADED);
  if HResultSucceeded(HR) then
    ACoInitialized := True
  else if HR <> RPC_E_CHANGED_MODE_VALUE then
    CheckHResult(HR, 'CoInitializeEx');

  HR := CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
    IID_IUIAutomation, AAutomation);
  CheckHResult(HR, 'CoCreateInstance(CUIAutomation)');
end;

procedure InitializeWindowAutomation(AArguments: TJSONObject;
  out AAutomation: IUIAutomation; out ARoot: IUIAutomationElement;
  out AWindowHandle: HWND; out ACoInitialized: Boolean);
var
  HR: HRESULT;
begin
  AAutomation := nil;
  ARoot := nil;
  InitializeAutomation(AAutomation, ACoInitialized);
  AWindowHandle := ReadWindowHandle(AArguments);
  HR := AAutomation.ElementFromHandle(AWindowHandle, ARoot);
  CheckHResult(HR, 'IUIAutomation.ElementFromHandle');
  if not Assigned(ARoot) then
    raise Exception.Create('UI Automation returned no root element for the window');
end;

procedure FindElementsForView(AAutomation: IUIAutomation;
  ARoot: IUIAutomationElement; const AView: string;
  out AElements: IUIAutomationElementArray);
var
  Condition: IUIAutomationCondition;
  HR: HRESULT;
begin
  AElements := nil;
  Condition := nil;
  if AView = 'control' then
    HR := AAutomation.get_ControlViewCondition(Condition)
  else if AView = 'content' then
    HR := AAutomation.get_ContentViewCondition(Condition)
  else if AView = 'raw' then
    HR := AAutomation.get_RawViewCondition(Condition)
  else
    raise Exception.Create('internal error: unsupported UI Automation view');

  if (not HResultSucceeded(HR)) or (not Assigned(Condition)) then
  begin
    Condition := nil;
    HR := AAutomation.CreateTrueCondition(Condition);
    CheckHResult(HR, 'IUIAutomation.CreateTrueCondition(view fallback)');
  end;

  HR := ARoot.FindAll(TreeScope_Descendants, Condition, AElements);
  CheckHResult(HR, 'IUIAutomationElement.FindAll(' + AView + ')');
  if not Assigned(AElements) then
    raise Exception.Create('UI Automation returned no element array');
end;

procedure CollectMatches(AElements: IUIAutomationElementArray;
  const AView, AName, AAutomationId, AControlType, AQuery, AMatchMode: string;
  AIncludeOffscreen, AActionableOnly, ADetails: Boolean; ALimit: Integer;
  AItems: TJSONArray; out AScanned, AMatched: Integer);
var
  Count, I: Integer;
  Element: IUIAutomationElement;
  Info: TUiElementInfo;
begin
  AScanned := 0;
  AMatched := 0;
  Count := 0;
  CheckHResult(AElements.get_Length(Count), 'IUIAutomationElementArray.Length');
  AScanned := Count;
  for I := 0 to Count - 1 do
  begin
    Element := nil;
    if not HResultSucceeded(AElements.GetElement(I, Element)) or
      (not Assigned(Element)) then
      Continue;
    ReadElementInfo(Element, Info);
    if (not AIncludeOffscreen) and Info.Offscreen then
      Continue;
    if AActionableOnly and (not IsActionable(Info)) then
      Continue;
    if not InfoMatches(Info, AName, AAutomationId, AControlType,
      AQuery, AMatchMode) then
      Continue;
    Inc(AMatched);
    if AItems.Count < ALimit then
      AItems.Add(ElementInfoToJson(Info, I, AView, ADetails));
  end;
end;

function FindMatchInView(AAutomation: IUIAutomation;
  ARoot: IUIAutomationElement; const AView, AName, AAutomationId,
  AControlType, AQuery, AMatchMode: string; AIncludeOffscreen: Boolean;
  AMatchIndex: Integer; out AMatchedElement: IUIAutomationElement;
  out AMatchedInfo: TUiElementInfo; out ASourceIndex: Integer): Boolean;
var
  Elements: IUIAutomationElementArray;
  Element: IUIAutomationElement;
  Info: TUiElementInfo;
  Count, I, CurrentMatch: Integer;
begin
  Result := False;
  AMatchedElement := nil;
  ASourceIndex := -1;
  Elements := nil;
  FindElementsForView(AAutomation, ARoot, AView, Elements);
  Count := 0;
  CheckHResult(Elements.get_Length(Count), 'IUIAutomationElementArray.Length');
  CurrentMatch := 0;
  for I := 0 to Count - 1 do
  begin
    Element := nil;
    if not HResultSucceeded(Elements.GetElement(I, Element)) or
      (not Assigned(Element)) then
      Continue;
    ReadElementInfo(Element, Info);
    if (not AIncludeOffscreen) and Info.Offscreen then
      Continue;
    if not InfoMatches(Info, AName, AAutomationId, AControlType,
      AQuery, AMatchMode) then
      Continue;
    if CurrentMatch = AMatchIndex then
    begin
      AMatchedElement := Element;
      AMatchedInfo := Info;
      ASourceIndex := I;
      Exit(True);
    end;
    Inc(CurrentMatch);
  end;
end;

function ResolveElementRef(AAutomation: IUIAutomation;
  ARoot: IUIAutomationElement; const ARef: string;
  out AView: string; out AMatchedElement: IUIAutomationElement;
  out AMatchedInfo: TUiElementInfo; out ASourceIndex: Integer): Boolean;
var
  Elements: IUIAutomationElementArray;
  Count: Integer;
begin
  Result := False;
  AMatchedElement := nil;
  if not ParseElementRef(ARef, AView, ASourceIndex) then
    raise Exception.Create('ref is invalid; use the exact ref returned by desktop_ui_elements');
  Elements := nil;
  FindElementsForView(AAutomation, ARoot, AView, Elements);
  Count := 0;
  CheckHResult(Elements.get_Length(Count), 'IUIAutomationElementArray.Length');
  if ASourceIndex >= Count then
    raise Exception.Create('ref is stale; the UI tree changed, so list elements again');
  CheckHResult(Elements.GetElement(ASourceIndex, AMatchedElement),
    'IUIAutomationElementArray.GetElement(ref)');
  if not Assigned(AMatchedElement) then
    raise Exception.Create('ref resolved to no current element; list elements again');
  ReadElementInfo(AMatchedElement, AMatchedInfo);
  if not SameText(BuildElementRef(AView, ASourceIndex, AMatchedInfo), ARef) then
    raise Exception.Create('ref is stale; the UI element changed, so list elements again');
  Result := True;
end;

function ElementsSame(AAutomation: IUIAutomation;
  AElement1, AElement2: IUIAutomationElement): Boolean;
var
  SameValue: LongBool;
begin
  Result := False;
  if (not Assigned(AElement1)) or (not Assigned(AElement2)) then
    Exit;
  SameValue := False;
  if HResultSucceeded(AAutomation.CompareElements(AElement1, AElement2,
    SameValue)) then
    Result := WinBool(SameValue);
end;

function IsAncestorOf(AAutomation: IUIAutomation;
  AAncestor, AElement: IUIAutomationElement): Boolean;
var
  Walker: IUIAutomationTreeWalker;
  Current, Parent: IUIAutomationElement;
  HR: HRESULT;
  Depth: Integer;
begin
  Result := False;
  if ElementsSame(AAutomation, AAncestor, AElement) then
    Exit(True);
  Walker := nil;
  HR := AAutomation.get_RawViewWalker(Walker);
  if (not HResultSucceeded(HR)) or (not Assigned(Walker)) then
    Exit(False);
  Current := AElement;
  for Depth := 0 to 63 do
  begin
    Parent := nil;
    HR := Walker.GetParentElement(Current, Parent);
    if (not HResultSucceeded(HR)) or (not Assigned(Parent)) then
      Exit(False);
    if ElementsSame(AAutomation, AAncestor, Parent) then
      Exit(True);
    Current := Parent;
  end;
end;

function ElementsRelated(AAutomation: IUIAutomation;
  AExpected, AHit: IUIAutomationElement): Boolean;
begin
  { A child returned by ElementFromPoint is acceptable (for example a text
    fragment inside a button/tree item). Merely hitting an ancestor is not
    enough evidence: a parent tree/list can cover many sibling items. }
  Result := IsAncestorOf(AAutomation, AExpected, AHit);
end;

function WindowOwnsForeground(AWindow: HWND): Boolean;
var
  ForegroundWindow, OwnerWindow: HWND;
  Depth: Integer;
begin
  Result := False;
  ForegroundWindow := GetForegroundWindow;
  if ForegroundWindow = 0 then
    Exit;
  if ForegroundWindow = AWindow then
    Exit(True);
  if WinBool(IsChild(AWindow, ForegroundWindow)) then
    Exit(True);
  OwnerWindow := ForegroundWindow;
  for Depth := 0 to 15 do
  begin
    OwnerWindow := GetWindow(OwnerWindow, GW_OWNER);
    if OwnerWindow = 0 then
      Break;
    if OwnerWindow = AWindow then
      Exit(True);
  end;
end;

procedure EnsureWindowForeground(AWindow: HWND; AActivate,
  ARequireForeground: Boolean);
var
  Attempt: Integer;
begin
  if AActivate and (not WindowOwnsForeground(AWindow)) then
  begin
    if WinBool(IsIconic(AWindow)) then
      ShowWindow(AWindow, SW_RESTORE);
    SetForegroundWindow(AWindow);
    BringWindowToTop(AWindow);
    for Attempt := 1 to 20 do
    begin
      if WindowOwnsForeground(AWindow) then
        Break;
      Sleep(10);
    end;
  end;
  if ARequireForeground and (not WindowOwnsForeground(AWindow)) then
    raise Exception.Create(
      'Target window could not be confirmed in the foreground. No physical click was sent.');
end;

procedure TryScrollElementIntoView(AElement: IUIAutomationElement);
var
  PatternObject: IUnknown;
  ScrollPattern: IUIAutomationScrollItemPattern;
  HR: HRESULT;
begin
  if not SupportsPattern(AElement, UIA_ScrollItemPatternId) then
    Exit;
  PatternObject := nil;
  ScrollPattern := nil;
  HR := AElement.GetCurrentPattern(UIA_ScrollItemPatternId, PatternObject);
  if HResultSucceeded(HR) and
    Supports(PatternObject, IUIAutomationScrollItemPattern, ScrollPattern) then
  begin
    HR := ScrollPattern.ScrollIntoView;
    if HResultSucceeded(HR) then
      Sleep(20);
  end;
end;

procedure PhysicalClickElement(AAutomation: IUIAutomation;
  AElement: IUIAutomationElement; AWindow: HWND; AArguments: TJSONObject;
  out APoint: TPoint; out AHitVerified: Boolean);
var
  GotClickable: LongBool;
  HitElement: IUIAutomationElement;
  HR: HRESULT;
  ActivateWindow, RequireForeground: Boolean;
  ButtonName: string;
  Clicks, I: Integer;
  DownFlag, UpFlag: DWord;
  ElementBounds: TRect;
begin
  FillChar(APoint, SizeOf(APoint), 0);
  AHitVerified := False;
  ActivateWindow := JsonBoolean(AArguments, 'activate_window', True);
  RequireForeground := JsonBoolean(AArguments, 'require_foreground', True);
  ButtonName := LowerCase(Trim(JsonString(AArguments, 'button', 'left')));
  Clicks := JsonInteger(AArguments, 'clicks', 1);
  if (Clicks < 1) or (Clicks > 2) then
    raise Exception.Create('clicks must be 1 or 2');
  if ButtonName = 'left' then
  begin
    DownFlag := MOUSEEVENTF_LEFTDOWN;
    UpFlag := MOUSEEVENTF_LEFTUP;
  end
  else if ButtonName = 'right' then
  begin
    DownFlag := MOUSEEVENTF_RIGHTDOWN;
    UpFlag := MOUSEEVENTF_RIGHTUP;
  end
  else if ButtonName = 'middle' then
  begin
    DownFlag := MOUSEEVENTF_MIDDLEDOWN;
    UpFlag := MOUSEEVENTF_MIDDLEUP;
  end
  else
    raise Exception.Create('button must be left, right, or middle');

  TryScrollElementIntoView(AElement);
  EnsureWindowForeground(AWindow, ActivateWindow, RequireForeground);

  GotClickable := False;
  HR := AElement.GetClickablePoint(APoint, GotClickable);
  if (not HResultSucceeded(HR)) or (not WinBool(GotClickable)) then
    raise Exception.CreateFmt(
      'UI Automation could not provide a clickable point for this element (HRESULT 0x%.8x). No coordinate guess was used.',
      [Cardinal(HR)]);

  FillChar(ElementBounds, SizeOf(ElementBounds), 0);
  if HResultSucceeded(AElement.get_CurrentBoundingRectangle(ElementBounds)) and
     (ElementBounds.Right > ElementBounds.Left) and
     (ElementBounds.Bottom > ElementBounds.Top) and
     ((APoint.X < ElementBounds.Left) or (APoint.X >= ElementBounds.Right) or
      (APoint.Y < ElementBounds.Top) or (APoint.Y >= ElementBounds.Bottom)) then
    raise Exception.Create(
      'The provider-supplied clickable point lies outside the selected element bounding rectangle. No click was sent.');

  HitElement := nil;
  HR := AAutomation.ElementFromPoint(APoint, HitElement);
  if HResultSucceeded(HR) and Assigned(HitElement) then
    AHitVerified := ElementsRelated(AAutomation, AElement, HitElement);
  if not AHitVerified then
    raise Exception.Create(
      'Clickable-point hit test did not resolve to the selected element or a related UI Automation node. No click was sent.');

  if not WinBool(SetCursorPos(APoint.X, APoint.Y)) then
    RaiseLastOSError;
  for I := 1 to Clicks do
  begin
    mouse_event(DownFlag, 0, 0, 0, 0);
    mouse_event(UpFlag, 0, 0, 0, 0);
    if I < Clicks then
      Sleep(80);
  end;
end;

class function TWindowsUiAutomation.GetStatus: TJSONObject;
var
  Automation: IUIAutomation;
  CoInitialized: Boolean;
  Views: TJSONArray;
begin
  Result := TJSONObject.Create;
  Automation := nil;
  CoInitialized := False;
  try
    try
      InitializeAutomation(Automation, CoInitialized);
      Result.Add('available', Assigned(Automation));
      Result.Add('backend', 'windows_ui_automation');
      Result.Add('semantic_elements', True);
      Result.Add('element_refs', True);
      Result.Add('invoke', True);
      Result.Add('set_value', True);
      Result.Add('toggle', True);
      Result.Add('select', True);
      Result.Add('expand_collapse', True);
      Result.Add('scroll_item', True);
      Result.Add('legacy_accessible', True);
      Result.Add('clickable_point', True);
      Result.Add('hit_test_verified_click', True);
      Result.Add('focus', True);
      Views := TJSONArray.Create;
      Views.Add('control');
      Views.Add('content');
      Views.Add('raw');
      Views.Add('native');
      Result.Add('views', Views);
      Result.Add('native_common_controls', TWindowsNativeControls.GetStatus);
    except
      on E: Exception do
      begin
        Result.Add('available', False);
        Result.Add('backend', 'windows_ui_automation');
        Result.Add('reason', E.Message);
      end;
    end;
  finally
    Automation := nil;
    if CoInitialized then
      CoUninitialize;
  end;
end;

class function TWindowsUiAutomation.ListElements(
  AArguments: TJSONObject): TJSONObject;
var
  Automation: IUIAutomation;
  Root: IUIAutomationElement;
  Elements: IUIAutomationElementArray;
  WindowHandle: HWND;
  CoInitialized: Boolean;
  Items: TJSONArray;
  LimitValue, Scanned, MatchedCount, PrimaryScanned, PrimaryMatched,
    ReturnedCount: Integer;
  QueryText, NameText, AutomationIdText, ControlTypeText,
    MatchMode, RequestedView, UsedView: string;
  IncludeOffscreen, ActionableOnly, Details, HasSelector,
    RawFallback, NativeFallback: Boolean;
  NativeResult: TJSONObject;
  NativeItems, CombinedItems: TJSONArray;
  NativeData: TJSONData;
  NativeMatched, NativeScanned, I: Integer;
begin
  Automation := nil;
  Root := nil;
  Elements := nil;
  WindowHandle := 0;
  CoInitialized := False;
  Items := TJSONArray.Create;
  NativeResult := nil;
  NativeItems := nil;
  CombinedItems := nil;
  try
    RequestedView := NormalizeViewName(JsonString(AArguments, 'view', 'auto'));
    if RequestedView = 'native' then
    begin
      Result := TWindowsNativeControls.ListElements(AArguments);
      Exit;
    end;

    LimitValue := JsonInteger(AArguments, 'limit', 100);
    if (LimitValue < 1) or (LimitValue > 500) then
      raise Exception.Create('limit must be between 1 and 500');
    QueryText := JsonString(AArguments, 'query', '');
    NameText := JsonString(AArguments, 'name', '');
    AutomationIdText := JsonString(AArguments, 'automation_id', '');
    ControlTypeText := JsonString(AArguments, 'control_type', '');
    MatchMode := LowerCase(Trim(JsonString(AArguments, 'match_mode', 'contains')));
    if (MatchMode <> 'exact') and (MatchMode <> 'contains') then
      raise Exception.Create('match_mode must be exact or contains');
    IncludeOffscreen := JsonBoolean(AArguments, 'include_offscreen', False);
    ActionableOnly := JsonBoolean(AArguments, 'actionable_only', False);
    Details := JsonBoolean(AArguments, 'details', False);
    HasSelector := (Trim(QueryText) <> '') or (Trim(NameText) <> '') or
      (Trim(AutomationIdText) <> '') or (Trim(ControlTypeText) <> '');

    InitializeWindowAutomation(AArguments, Automation, Root, WindowHandle,
      CoInitialized);

    if RequestedView = 'auto' then
      UsedView := 'control'
    else
      UsedView := RequestedView;

    FindElementsForView(Automation, Root, UsedView, Elements);
    CollectMatches(Elements, UsedView, NameText, AutomationIdText,
      ControlTypeText, QueryText, MatchMode, IncludeOffscreen,
      ActionableOnly, Details, LimitValue, Items, PrimaryScanned,
      PrimaryMatched);
    Scanned := PrimaryScanned;
    MatchedCount := PrimaryMatched;
    RawFallback := False;
    NativeFallback := False;

    if (RequestedView = 'auto') and (PrimaryMatched = 0) and
      (HasSelector or (PrimaryScanned = 0)) then
    begin
      Elements := nil;
      FindElementsForView(Automation, Root, 'raw', Elements);
      CollectMatches(Elements, 'raw', NameText, AutomationIdText,
        ControlTypeText, QueryText, MatchMode, IncludeOffscreen,
        ActionableOnly, Details, LimitValue, Items, Scanned, MatchedCount);
      Scanned := PrimaryScanned + Scanned;
      UsedView := 'raw';
      RawFallback := True;
    end;

    if RequestedView = 'auto' then
    begin
      NativeFallback := True;
      NativeResult := TWindowsNativeControls.ListElements(AArguments);
      NativeMatched := JsonInteger(NativeResult, 'matched', 0);
      NativeScanned := JsonInteger(NativeResult, 'scanned', 0);
      if NativeMatched > 0 then
      begin
        NativeData := NativeResult.Find('elements');
        if (NativeData <> nil) and (NativeData.JSONType = jtArray) then
        begin
          NativeItems := TJSONArray(NativeData);
          CombinedItems := TJSONArray.Create;
          { Native tree/list matches come first. This prevents a same-named
            static UIA text (for example the Lazarus description "Application")
            from hiding the actual selectable tree item. }
          for I := 0 to NativeItems.Count - 1 do
          begin
            if CombinedItems.Count >= LimitValue then
              Break;
            CombinedItems.Add(NativeItems.Items[I].Clone);
          end;
          for I := 0 to Items.Count - 1 do
          begin
            if CombinedItems.Count >= LimitValue then
              Break;
            CombinedItems.Add(Items.Items[I].Clone);
          end;

          ReturnedCount := CombinedItems.Count;
          Result := TJSONObject.Create;
          Result.Add('elements', CombinedItems);
          CombinedItems := nil;
          Result.Add('count', ReturnedCount);
          Result.Add('matched', NativeMatched + MatchedCount);
          Result.Add('native_matched', NativeMatched);
          Result.Add('uia_matched', MatchedCount);
          Result.Add('scanned', Scanned + NativeScanned);
          Result.Add('uia_scanned', Scanned);
          Result.Add('native_scanned', NativeScanned);
          Result.Add('limit', LimitValue);
          Result.Add('details', Details);
          Result.Add('requested_view', RequestedView);
          if MatchedCount > 0 then
            Result.Add('view_used', 'native+uia')
          else
            Result.Add('view_used', 'native');
          Result.Add('raw_fallback', RawFallback);
          Result.Add('native_fallback', True);
          Result.Add('actionable_only', ActionableOnly);
          Result.Add('truncated', NativeMatched + MatchedCount > LimitValue);
          Result.Add('selector_advice',
            'Native common-control matches are ranked before same-named UIA text. Prefer the returned tree_item/list_item ref when that is the intended target.');
          Result.Add('coordinate_advice',
            'Native tree/list refs are acted on by exact item handle/index. No screenshot coordinates are involved.');
          Exit;
        end;
      end;
    end;

    ReturnedCount := Items.Count;
    Result := TJSONObject.Create;
    Result.Add('elements', Items);
    Items := nil;
    Result.Add('count', ReturnedCount);
    Result.Add('matched', MatchedCount);
    Result.Add('scanned', Scanned);
    Result.Add('limit', LimitValue);
    Result.Add('details', Details);
    Result.Add('requested_view', RequestedView);
    Result.Add('view_used', UsedView);
    Result.Add('raw_fallback', RawFallback);
    Result.Add('native_fallback', NativeFallback);
    Result.Add('actionable_only', ActionableOnly);
    Result.Add('truncated', MatchedCount > LimitValue);
    Result.Add('selector_advice',
      'Prefer ref from this result for the immediate next action. Otherwise prefer automation_id, then exact name plus control_type. view=auto tries control UIA, raw UIA, then exact Win32 SysTreeView32/SysListView32 item enumeration.');
    Result.Add('coordinate_advice',
      'Do not derive mouse coordinates from bounds. UIA actions stay semantic where possible; native tree/list fallbacks select the exact common-control item by handle/index and do not use screenshot coordinates.');
  finally
    CombinedItems.Free;
    NativeResult.Free;
    Items.Free;
    Elements := nil;
    Root := nil;
    Automation := nil;
    if CoInitialized then
      CoUninitialize;
  end;
end;

class function TWindowsUiAutomation.PerformAction(
  AArguments: TJSONObject): TJSONObject;
var
  Automation: IUIAutomation;
  Root, MatchedElement: IUIAutomationElement;
  WindowHandle: HWND;
  PatternObject: IUnknown;
  InvokePattern: IUIAutomationInvokePattern;
  ValuePattern: IUIAutomationValuePattern;
  TogglePattern: IUIAutomationTogglePattern;
  SelectionPattern: IUIAutomationSelectionItemPattern;
  ExpandPattern: IUIAutomationExpandCollapsePattern;
  ScrollPattern: IUIAutomationScrollItemPattern;
  LegacyPattern: IUIAutomationLegacyIAccessiblePattern;
  CoInitialized: Boolean;
  MatchedInfo: TUiElementInfo;
  MatchIndex, SourceIndex: Integer;
  ActionName, ResolvedAction, QueryText, NameText, AutomationIdText,
    ControlTypeText, MatchMode, ValueText, RequestedView, UsedView,
    ElementRef: string;
  WideValueText: WideString;
  IncludeOffscreen, Found, HitVerified, UsedRef: Boolean;
  HR: HRESULT;
  ClickPoint: TPoint;
  NativeProbe: TJSONObject;
  NativeProbeMatched: Integer;
begin
  Automation := nil;
  Root := nil;
  MatchedElement := nil;
  PatternObject := nil;
  InvokePattern := nil;
  ValuePattern := nil;
  TogglePattern := nil;
  SelectionPattern := nil;
  ExpandPattern := nil;
  ScrollPattern := nil;
  LegacyPattern := nil;
  WindowHandle := 0;
  CoInitialized := False;
  FillChar(ClickPoint, SizeOf(ClickPoint), 0);
  HitVerified := False;
  NativeProbe := nil;

  ActionName := LowerCase(Trim(JsonString(AArguments, 'action', 'activate')));
  if (ActionName <> 'activate') and (ActionName <> 'invoke') and
     (ActionName <> 'focus') and (ActionName <> 'set_value') and
     (ActionName <> 'toggle') and (ActionName <> 'select') and
     (ActionName <> 'expand') and (ActionName <> 'collapse') and
     (ActionName <> 'scroll_into_view') and
     (ActionName <> 'legacy_default') and (ActionName <> 'click') then
    raise Exception.Create(
      'action must be activate, invoke, focus, set_value, toggle, select, expand, collapse, scroll_into_view, legacy_default, or click');

  ElementRef := Trim(JsonString(AArguments, 'ref', ''));
  QueryText := JsonString(AArguments, 'query', '');
  NameText := JsonString(AArguments, 'name', '');
  AutomationIdText := JsonString(AArguments, 'automation_id', '');
  ControlTypeText := JsonString(AArguments, 'control_type', '');
  UsedRef := ElementRef <> '';
  if (not UsedRef) and (Trim(QueryText) = '') and (Trim(NameText) = '') and
     (Trim(AutomationIdText) = '') and (Trim(ControlTypeText) = '') then
    raise Exception.Create(
      'Provide ref from desktop_ui_elements or at least one selector: automation_id, name, control_type, or query');

  MatchMode := LowerCase(Trim(JsonString(AArguments, 'match_mode', 'exact')));
  if (MatchMode <> 'exact') and (MatchMode <> 'contains') then
    raise Exception.Create('match_mode must be exact or contains');
  MatchIndex := JsonInteger(AArguments, 'match_index', 0);
  if MatchIndex < 0 then
    raise Exception.Create('match_index must be zero or positive');
  IncludeOffscreen := JsonBoolean(AArguments, 'include_offscreen', False);
  ValueText := JsonString(AArguments, 'value', '');
  RequestedView := NormalizeViewName(JsonString(AArguments, 'view', 'auto'));

  if TWindowsNativeControls.IsNativeRef(ElementRef) or
     (RequestedView = 'native') then
  begin
    Result := TWindowsNativeControls.PerformAction(AArguments);
    Exit;
  end;

  { For selector-based auto actions, probe native tree/list items before UIA.
    This matters when UIA exposes a same-named static text but omits the actual
    SysTreeView32 item. A concrete native match is more actionable than that
    incidental text. }
  if (not UsedRef) and (RequestedView = 'auto') and
     ((ActionName = 'activate') or (ActionName = 'select') or
      (ActionName = 'expand') or (ActionName = 'collapse') or
      (ActionName = 'scroll_into_view')) and
     ((Trim(QueryText) <> '') or (Trim(NameText) <> '') or
      (Trim(ControlTypeText) <> '')) then
  begin
    NativeProbe := TWindowsNativeControls.ListElements(AArguments);
    try
      NativeProbeMatched := JsonInteger(NativeProbe, 'matched', 0);
      if NativeProbeMatched > 0 then
      begin
        Result := TWindowsNativeControls.PerformAction(AArguments);
        Exit;
      end;
    finally
      NativeProbe.Free;
      NativeProbe := nil;
    end;
  end;

  try
    InitializeWindowAutomation(AArguments, Automation, Root, WindowHandle,
      CoInitialized);

    if UsedRef then
    begin
      Found := ResolveElementRef(Automation, Root, ElementRef, UsedView,
        MatchedElement, MatchedInfo, SourceIndex);
      if not Found then
        raise Exception.Create('ref could not be resolved');
      if (not IncludeOffscreen) and MatchedInfo.Offscreen and
         (ActionName <> 'scroll_into_view') and (ActionName <> 'click') and
         (ActionName <> 'activate') then
        raise Exception.Create(
          'The ref currently resolves to an offscreen element; set include_offscreen=true or scroll it into view');
    end
    else
    begin
      if RequestedView = 'auto' then
        UsedView := 'control'
      else
        UsedView := RequestedView;
      Found := FindMatchInView(Automation, Root, UsedView, NameText,
        AutomationIdText, ControlTypeText, QueryText, MatchMode,
        IncludeOffscreen, MatchIndex, MatchedElement, MatchedInfo,
        SourceIndex);
      if (not Found) and (RequestedView = 'auto') then
      begin
        UsedView := 'raw';
        Found := FindMatchInView(Automation, Root, UsedView, NameText,
          AutomationIdText, ControlTypeText, QueryText, MatchMode,
          IncludeOffscreen, MatchIndex, MatchedElement, MatchedInfo,
          SourceIndex);
      end;
      if (not Found) and (RequestedView = 'auto') then
      begin
        Result := TWindowsNativeControls.PerformAction(AArguments);
        Exit;
      end;
      if not Found then
        raise Exception.CreateFmt(
          'No UI Automation element matched the selector at match_index %d in the requested view(s)',
          [MatchIndex]);
    end;

    if not MatchedInfo.Enabled then
      raise Exception.Create('The matched UI Automation element is disabled');

    ResolvedAction := ActionName;
    if ActionName = 'activate' then
    begin
      if MatchedInfo.CanInvoke then
        ResolvedAction := 'invoke'
      else if MatchedInfo.CanSelect then
        ResolvedAction := 'select'
      else if MatchedInfo.CanToggle then
        ResolvedAction := 'toggle'
      else if MatchedInfo.CanLegacyDefault then
        ResolvedAction := 'legacy_default'
      else if MatchedInfo.HasBounds then
        ResolvedAction := 'click'
      else if MatchedInfo.Focusable then
        ResolvedAction := 'focus'
      else
        raise Exception.Create(
          'The matched element has no supported activation path');
    end;

    if ResolvedAction = 'focus' then
      HR := MatchedElement.SetFocus
    else if ResolvedAction = 'invoke' then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_InvokePatternId, PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(Invoke)');
      if not Supports(PatternObject, IUIAutomationInvokePattern, InvokePattern) then
        raise Exception.Create('The matched element does not support InvokePattern');
      HR := InvokePattern.Invoke;
    end
    else if ResolvedAction = 'set_value' then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_ValuePatternId, PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(Value)');
      if not Supports(PatternObject, IUIAutomationValuePattern, ValuePattern) then
        raise Exception.Create('The matched element does not support ValuePattern');
      WideValueText := WideString(UTF8Decode(ValueText));
      HR := ValuePattern.SetValue(WideValueText);
    end
    else if ResolvedAction = 'toggle' then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_TogglePatternId, PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(Toggle)');
      if not Supports(PatternObject, IUIAutomationTogglePattern, TogglePattern) then
        raise Exception.Create('The matched element does not support TogglePattern');
      HR := TogglePattern.Toggle;
    end
    else if ResolvedAction = 'select' then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_SelectionItemPatternId,
        PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(SelectionItem)');
      if not Supports(PatternObject, IUIAutomationSelectionItemPattern,
        SelectionPattern) then
        raise Exception.Create(
          'The matched element does not support SelectionItemPattern');
      HR := SelectionPattern.Select;
    end
    else if (ResolvedAction = 'expand') or (ResolvedAction = 'collapse') then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_ExpandCollapsePatternId,
        PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(ExpandCollapse)');
      if not Supports(PatternObject, IUIAutomationExpandCollapsePattern,
        ExpandPattern) then
        raise Exception.Create(
          'The matched element does not support ExpandCollapsePattern');
      if ResolvedAction = 'expand' then
        HR := ExpandPattern.Expand
      else
        HR := ExpandPattern.Collapse;
    end
    else if ResolvedAction = 'scroll_into_view' then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_ScrollItemPatternId,
        PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(ScrollItem)');
      if not Supports(PatternObject, IUIAutomationScrollItemPattern,
        ScrollPattern) then
        raise Exception.Create(
          'The matched element does not support ScrollItemPattern');
      HR := ScrollPattern.ScrollIntoView;
    end
    else if ResolvedAction = 'legacy_default' then
    begin
      PatternObject := nil;
      HR := MatchedElement.GetCurrentPattern(UIA_LegacyIAccessiblePatternId,
        PatternObject);
      CheckHResult(HR, 'GetCurrentPattern(LegacyIAccessible)');
      if not Supports(PatternObject, IUIAutomationLegacyIAccessiblePattern,
        LegacyPattern) then
        raise Exception.Create(
          'The matched element does not support LegacyIAccessiblePattern');
      HR := LegacyPattern.DoDefaultAction;
    end
    else if ResolvedAction = 'click' then
    begin
      PhysicalClickElement(Automation, MatchedElement, WindowHandle,
        AArguments, ClickPoint, HitVerified);
      HR := 0;
    end
    else
      raise Exception.Create('internal error: unresolved UI Automation action');

    CheckHResult(HR, 'UI Automation action ' + ResolvedAction);

    Result := TJSONObject.Create;
    Result.Add('success', True);
    Result.Add('action', ActionName);
    Result.Add('resolved_action', ResolvedAction);
    Result.Add('match_index', MatchIndex);
    Result.Add('used_ref', UsedRef);
    Result.Add('view_used', UsedView);
    Result.Add('element', ElementInfoToJson(MatchedInfo, SourceIndex,
      UsedView, False));
    if ResolvedAction = 'click' then
    begin
      Result.Add('physical_click', True);
      Result.Add('click_point_source', 'uia_get_clickable_point');
      Result.Add('hit_test_verified', HitVerified);
    end;
    if ResolvedAction = 'click' then
      Result.Add('verification',
        'The server obtained a provider-supplied clickable point, verified it with ElementFromPoint against the selected UIA node, then injected the physical click. No model-supplied coordinates were used.')
    else
      Result.Add('verification',
        'The UI Automation provider accepted the semantic action. A screenshot is normally unnecessary.');
  finally
    LegacyPattern := nil;
    ScrollPattern := nil;
    ExpandPattern := nil;
    SelectionPattern := nil;
    TogglePattern := nil;
    ValuePattern := nil;
    InvokePattern := nil;
    PatternObject := nil;
    MatchedElement := nil;
    Root := nil;
    Automation := nil;
    if CoInitialized then
      CoUninitialize;
  end;
end;

end.
