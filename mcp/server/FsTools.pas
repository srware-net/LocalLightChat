unit FsTools;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  TFsTools = class
  private
    FWorkspaceRoot: string;
    FAllowDelete: Boolean;
    function IsAbsolutePath(const APath: string): Boolean;
    function IsInsideWorkspace(const APath: string): Boolean;
    function RelativeToWorkspace(const APath: string): string;
    procedure SearchSingleFile(const AFileName, AQuery: string;
      AMaximumResults: Integer; AResults: TJSONArray);
    procedure SearchDirectory(const ADirectory, AQuery: string;
      ARecursive: Boolean; AMaximumResults: Integer; AResults: TJSONArray);
  public
    constructor Create(const AWorkspaceRoot: string; AAllowDelete: Boolean);
    function ResolvePath(const APath: string): string;
    function ListDirectory(AArguments: TJSONObject): TJSONData;
    function ReadFile(AArguments: TJSONObject): TJSONData;
    function WriteFile(AArguments: TJSONObject): TJSONData;
    function ReplaceText(AArguments: TJSONObject): TJSONData;
    function SearchFiles(AArguments: TJSONObject): TJSONData;
    function StatPath(AArguments: TJSONObject): TJSONData;
    function MakeDirectory(AArguments: TJSONObject): TJSONData;
    function MovePath(AArguments: TJSONObject): TJSONData;
    function CopyFilePath(AArguments: TJSONObject): TJSONData;
    function DeletePath(AArguments: TJSONObject): TJSONData;
    property WorkspaceRoot: string read FWorkspaceRoot;
  end;

implementation

uses
  StrUtils, DateUtils, McpJson;

function ReadWholeFile(const AFileName: string): RawByteString;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure WriteWholeFile(const AFileName: string; const AContent: RawByteString);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(AContent) > 0 then
      Stream.WriteBuffer(AContent[1], Length(AContent));
  finally
    Stream.Free;
  end;
end;

constructor TFsTools.Create(const AWorkspaceRoot: string; AAllowDelete: Boolean);
begin
  inherited Create;
  FWorkspaceRoot := ExcludeTrailingPathDelimiter(ExpandFileName(AWorkspaceRoot));
  FAllowDelete := AAllowDelete;
  ForceDirectories(FWorkspaceRoot);
end;

function TFsTools.IsAbsolutePath(const APath: string): Boolean;
begin
  Result := (APath <> '') and
    ((APath[1] = DirectorySeparator) or (APath[1] = '/') or
     (APath[1] = '\') or (ExtractFileDrive(APath) <> ''));
end;

function TFsTools.IsInsideWorkspace(const APath: string): Boolean;
var
  RootWithSeparator, Candidate: string;
begin
  RootWithSeparator := IncludeTrailingPathDelimiter(FWorkspaceRoot);
  Candidate := ExpandFileName(APath);
  {$IFDEF Windows}
  Result := SameText(Candidate, FWorkspaceRoot) or
    (CompareText(Copy(Candidate, 1, Length(RootWithSeparator)),
      RootWithSeparator) = 0);
  {$ELSE}
  Result := (Candidate = FWorkspaceRoot) or
    (Copy(Candidate, 1, Length(RootWithSeparator)) = RootWithSeparator);
  {$ENDIF}
end;

function TFsTools.ResolvePath(const APath: string): string;
var
  Requested: string;
begin
  Requested := APath;
  if Requested = '' then
    Requested := '.';
  if IsAbsolutePath(Requested) then
    Result := ExpandFileName(Requested)
  else
    Result := ExpandFileName(IncludeTrailingPathDelimiter(FWorkspaceRoot) + Requested);

  if not IsInsideWorkspace(Result) then
    raise Exception.CreateFmt('Path escapes workspace: %s', [APath]);
end;

function TFsTools.RelativeToWorkspace(const APath: string): string;
begin
  Result := ExtractRelativePath(IncludeTrailingPathDelimiter(FWorkspaceRoot), APath);
  if Result = '' then
    Result := '.';
end;

function TFsTools.ListDirectory(AArguments: TJSONObject): TJSONData;
var
  Path, FullName: string;
  SearchRec: TSearchRec;
  Entries: TJSONArray;
  Item: TJSONObject;
begin
  Path := ResolvePath(JsonString(AArguments, 'path', '.'));
  if not DirectoryExists(Path) then
    raise Exception.CreateFmt('Directory not found: %s', [Path]);

  Entries := TJSONArray.Create;
  if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, SearchRec) = 0 then
  try
    repeat
      if (SearchRec.Name = '.') or (SearchRec.Name = '..') then
        Continue;
      FullName := IncludeTrailingPathDelimiter(Path) + SearchRec.Name;
      Item := TJSONObject.Create;
      Item.Add('name', SearchRec.Name);
      Item.Add('path', RelativeToWorkspace(FullName));
      Item.Add('is_directory', (SearchRec.Attr and faDirectory) <> 0);
      Item.Add('size', SearchRec.Size);
      Item.Add('modified', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss',
        FileDateToDateTime(SearchRec.Time)));
      Entries.Add(Item);
    until FindNext(SearchRec) <> 0;
  finally
    FindClose(SearchRec);
  end;

  Result := TJSONObject.Create;
  TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
  TJSONObject(Result).Add('entries', Entries);
end;

function TFsTools.ReadFile(AArguments: TJSONObject): TJSONData;
var
  Path: string;
  Stream: TFileStream;
  Offset, RequestedLimit, Remaining, ReadCount: Int64;
  Buffer: RawByteString;
begin
  Path := ResolvePath(JsonString(AArguments, 'path'));
  Offset := JsonInteger(AArguments, 'offset', 0);
  RequestedLimit := JsonInteger(AArguments, 'limit', 1024 * 1024);
  if Offset < 0 then
    raise Exception.Create('offset must be >= 0');
  if RequestedLimit < 1 then
    raise Exception.Create('limit must be >= 1');
  if not FileExists(Path) then
    raise Exception.CreateFmt('File not found: %s', [Path]);

  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    if Offset > Stream.Size then
      Offset := Stream.Size;
    Stream.Position := Offset;
    Remaining := Stream.Size - Offset;
    if RequestedLimit < Remaining then
      ReadCount := RequestedLimit
    else
      ReadCount := Remaining;
    SetLength(Buffer, ReadCount);
    if ReadCount > 0 then
      Stream.ReadBuffer(Buffer[1], ReadCount);

    Result := TJSONObject.Create;
    TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
    TJSONObject(Result).Add('content', UTF8String(Buffer));
    TJSONObject(Result).Add('offset', Offset);
    TJSONObject(Result).Add('bytes_read', ReadCount);
    TJSONObject(Result).Add('file_size', Stream.Size);
    TJSONObject(Result).Add('truncated', Offset + ReadCount < Stream.Size);
  finally
    Stream.Free;
  end;
end;

function TFsTools.WriteFile(AArguments: TJSONObject): TJSONData;
var
  Path: string;
  Content: UTF8String;
  Stream: TFileStream;
begin
  Path := ResolvePath(JsonString(AArguments, 'path'));
  Content := JsonUtf8String(AArguments, 'content');
  if JsonBoolean(AArguments, 'create_directories', True) then
    ForceDirectories(ExtractFileDir(Path));

  { fpjson already stores JSON strings as UTF-8. Write those bytes verbatim;
    converting UTF8String -> String -> UTF8String is locale-dependent. }
  Stream := TFileStream.Create(Path, fmCreate);
  try
    if Length(Content) > 0 then
      Stream.WriteBuffer(Content[1], Length(Content));
  finally
    Stream.Free;
  end;

  Result := TJSONObject.Create;
  TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
  TJSONObject(Result).Add('bytes_written', Length(Content));
end;

function CountOccurrences(const AText, APattern: string): Integer;
var
  P, StartAt: SizeInt;
begin
  Result := 0;
  if APattern = '' then
    Exit;
  StartAt := 1;
  repeat
    P := PosEx(APattern, AText, StartAt);
    if P = 0 then
      Break;
    Inc(Result);
    StartAt := P + Length(APattern);
  until False;
end;

function TFsTools.ReplaceText(AArguments: TJSONObject): TJSONData;
var
  Path, OldText, NewText: string;
  Content, ReplacedContent: RawByteString;
  Count, Expected: Integer;
begin
  Path := ResolvePath(JsonString(AArguments, 'path'));
  OldText := JsonString(AArguments, 'old_text');
  NewText := JsonString(AArguments, 'new_text');
  Expected := JsonInteger(AArguments, 'expected_occurrences', 1);
  if OldText = '' then
    raise Exception.Create('old_text must not be empty');
  if not FileExists(Path) then
    raise Exception.CreateFmt('File not found: %s', [Path]);

  Content := ReadWholeFile(Path);
  Count := CountOccurrences(string(Content), OldText);
  if Count <> Expected then
    raise Exception.CreateFmt('Expected %d occurrence(s), found %d',
      [Expected, Count]);
  ReplacedContent := RawByteString(StringReplace(string(Content), OldText,
    NewText, [rfReplaceAll]));
  WriteWholeFile(Path, ReplacedContent);

  Result := TJSONObject.Create;
  TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
  TJSONObject(Result).Add('replacements', Count);
end;

procedure TFsTools.SearchSingleFile(const AFileName, AQuery: string;
  AMaximumResults: Integer; AResults: TJSONArray);
var
  Lines: TStringList;
  I: Integer;
  Item: TJSONObject;
begin
  if AResults.Count >= AMaximumResults then
    Exit;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName);
    except
      Exit;
    end;
    for I := 0 to Lines.Count - 1 do
    begin
      if Pos(LowerCase(AQuery), LowerCase(Lines[I])) > 0 then
      begin
        Item := TJSONObject.Create;
        Item.Add('path', RelativeToWorkspace(AFileName));
        Item.Add('line', I + 1);
        Item.Add('text', Lines[I]);
        AResults.Add(Item);
        if AResults.Count >= AMaximumResults then
          Break;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TFsTools.SearchDirectory(const ADirectory, AQuery: string;
  ARecursive: Boolean; AMaximumResults: Integer; AResults: TJSONArray);
var
  SearchRec: TSearchRec;
  FullName: string;
begin
  if AResults.Count >= AMaximumResults then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADirectory) + '*',
    faAnyFile, SearchRec) <> 0 then
    Exit;
  try
    repeat
      if AResults.Count >= AMaximumResults then
        Exit;
      if (SearchRec.Name = '.') or (SearchRec.Name = '..') then
        Continue;
      FullName := IncludeTrailingPathDelimiter(ADirectory) + SearchRec.Name;
      if (SearchRec.Attr and faDirectory) <> 0 then
      begin
        if ARecursive then
          SearchDirectory(FullName, AQuery, ARecursive,
            AMaximumResults, AResults);
        Continue;
      end;
      if SearchRec.Size > 2 * 1024 * 1024 then
        Continue;

      SearchSingleFile(FullName, AQuery, AMaximumResults, AResults);
    until FindNext(SearchRec) <> 0;
  finally
    FindClose(SearchRec);
  end;
end;

function TFsTools.SearchFiles(AArguments: TJSONObject): TJSONData;
var
  Path, Query: string;
  Recursive: Boolean;
  MaximumResults: Integer;
  Results: TJSONArray;
begin
  Path := ResolvePath(JsonString(AArguments, 'path', '.'));
  Query := JsonString(AArguments, 'query');
  Recursive := JsonBoolean(AArguments, 'recursive', True);
  MaximumResults := JsonInteger(AArguments, 'max_results', 100);
  if Query = '' then
    raise Exception.Create('query must not be empty');
  if MaximumResults < 1 then
    MaximumResults := 1;
  if MaximumResults > 1000 then
    MaximumResults := 1000;

  Results := TJSONArray.Create;
  if DirectoryExists(Path) then
    SearchDirectory(Path, Query, Recursive, MaximumResults, Results)
  else if FileExists(Path) then
    SearchSingleFile(Path, Query, MaximumResults, Results)
  else
    raise Exception.CreateFmt('Path not found: %s', [Path]);

  Result := TJSONObject.Create;
  TJSONObject(Result).Add('query', Query);
  TJSONObject(Result).Add('results', Results);
end;

function TFsTools.StatPath(AArguments: TJSONObject): TJSONData;
var
  Path: string;
  Info: TSearchRec;
begin
  Path := ResolvePath(JsonString(AArguments, 'path'));
  if FindFirst(Path, faAnyFile, Info) <> 0 then
    raise Exception.CreateFmt('Path not found: %s', [Path]);
  try
    Result := TJSONObject.Create;
    TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
    TJSONObject(Result).Add('exists', True);
    TJSONObject(Result).Add('is_directory', (Info.Attr and faDirectory) <> 0);
    TJSONObject(Result).Add('size', Info.Size);
    TJSONObject(Result).Add('modified', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss',
      FileDateToDateTime(Info.Time)));
    TJSONObject(Result).Add('attributes', Info.Attr);
  finally
    FindClose(Info);
  end;
end;

function TFsTools.MakeDirectory(AArguments: TJSONObject): TJSONData;
var
  Path: string;
begin
  Path := ResolvePath(JsonString(AArguments, 'path'));
  if not ForceDirectories(Path) then
    raise Exception.CreateFmt('Could not create directory: %s', [Path]);
  Result := TJSONObject.Create;
  TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
  TJSONObject(Result).Add('created', True);
end;

function TFsTools.MovePath(AArguments: TJSONObject): TJSONData;
var
  SourcePath, TargetPath: string;
begin
  SourcePath := ResolvePath(JsonString(AArguments, 'source'));
  TargetPath := ResolvePath(JsonString(AArguments, 'target'));
  ForceDirectories(ExtractFileDir(TargetPath));
  if not RenameFile(SourcePath, TargetPath) then
    raise Exception.CreateFmt('Could not move %s to %s',
      [SourcePath, TargetPath]);
  Result := TJSONObject.Create;
  TJSONObject(Result).Add('source', RelativeToWorkspace(SourcePath));
  TJSONObject(Result).Add('target', RelativeToWorkspace(TargetPath));
  TJSONObject(Result).Add('moved', True);
end;

function TFsTools.CopyFilePath(AArguments: TJSONObject): TJSONData;
var
  SourcePath, TargetPath: string;
  SourceStream, TargetStream: TFileStream;
  CopiedBytes: Int64;
begin
  SourcePath := ResolvePath(JsonString(AArguments, 'source'));
  TargetPath := ResolvePath(JsonString(AArguments, 'target'));
  if not FileExists(SourcePath) then
    raise Exception.CreateFmt('File not found: %s', [SourcePath]);
  ForceDirectories(ExtractFileDir(TargetPath));
  SourceStream := TFileStream.Create(SourcePath, fmOpenRead or fmShareDenyNone);
  TargetStream := TFileStream.Create(TargetPath, fmCreate);
  try
    TargetStream.CopyFrom(SourceStream, 0);
    CopiedBytes := TargetStream.Size;
  finally
    TargetStream.Free;
    SourceStream.Free;
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).Add('source', RelativeToWorkspace(SourcePath));
  TJSONObject(Result).Add('target', RelativeToWorkspace(TargetPath));
  TJSONObject(Result).Add('bytes_copied', CopiedBytes);
end;

function TFsTools.DeletePath(AArguments: TJSONObject): TJSONData;
var
  Path: string;
  Deleted: Boolean;
begin
  if not FAllowDelete then
    raise Exception.Create('Delete operations are disabled by configuration');
  Path := ResolvePath(JsonString(AArguments, 'path'));
  if SameText(Path, FWorkspaceRoot) then
    raise Exception.Create('Workspace root cannot be deleted');
  if DirectoryExists(Path) then
    Deleted := RemoveDir(Path)
  else if FileExists(Path) then
    Deleted := DeleteFile(Path)
  else
    raise Exception.CreateFmt('Path not found: %s', [Path]);
  if not Deleted then
    raise Exception.CreateFmt('Could not delete path: %s', [Path]);
  Result := TJSONObject.Create;
  TJSONObject(Result).Add('path', RelativeToWorkspace(Path));
  TJSONObject(Result).Add('deleted', True);
end;

end.
