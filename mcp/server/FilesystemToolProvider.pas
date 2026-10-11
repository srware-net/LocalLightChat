unit FilesystemToolProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, ToolProvider, FsTools;

type
  TFilesystemToolProvider = class(TToolProvider)
  private
    FFsTools: TFsTools;
    FAllowDelete: Boolean;
  public
    constructor Create(const AWorkspaceRoot: string; AAllowDelete: Boolean);
    destructor Destroy; override;
    procedure AddTools(ATools: TJSONArray); override;
    function HandlesTool(const AName: string): Boolean; override;
    function CallTool(const AName: string; AArguments: TJSONObject;
      const ACorrelationId: string): TJSONObject; override;
    function ResolvePath(const APath: string): string;
  end;

implementation

uses
  McpProtocol, McpJson;

constructor TFilesystemToolProvider.Create(const AWorkspaceRoot: string;
  AAllowDelete: Boolean);
begin
  inherited Create;
  FAllowDelete := AAllowDelete;
  FFsTools := TFsTools.Create(AWorkspaceRoot, AAllowDelete);
end;

destructor TFilesystemToolProvider.Destroy;
begin
  FFsTools.Free;
  inherited Destroy;
end;

procedure TFilesystemToolProvider.AddTools(ATools: TJSONArray);
var
  Props: TJSONObject;
begin
  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('Directory relative to the configured workspace'));
  ATools.Add(BuildTool('fs_list', 'Lists files and directories in the workspace.',
    ObjectSchema(Props, [])));

  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('File relative to the configured workspace'));
  Props.Add('offset', IntegerProperty(0, 0, High(LongInt)));
  Props.Add('limit', IntegerProperty(1048576, 1, 16777216));
  ATools.Add(BuildTool('fs_read', 'Reads a UTF-8 text file.',
    ObjectSchema(Props, ['path'])));

  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('File relative to the configured workspace'));
  Props.Add('content', StringProperty('Complete UTF-8 file content'));
  Props.Add('create_directories', BooleanProperty(True));
  ATools.Add(BuildTool('fs_write', 'Creates or overwrites a UTF-8 text file.',
    ObjectSchema(Props, ['path', 'content'])));

  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('File relative to the configured workspace'));
  Props.Add('old_text', StringProperty('Exact text to replace'));
  Props.Add('new_text', StringProperty('Replacement text'));
  Props.Add('expected_occurrences', IntegerProperty(1, 1, 1000000));
  ATools.Add(BuildTool('fs_replace',
    'Replaces exact text only when the expected occurrence count matches.',
    ObjectSchema(Props, ['path', 'old_text', 'new_text'])));

  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('Directory relative to the workspace'));
  Props.Add('query', StringProperty('Case-insensitive text query'));
  Props.Add('recursive', BooleanProperty(True));
  Props.Add('max_results', IntegerProperty(100, 1, 1000));
  ATools.Add(BuildTool('fs_search', 'Searches text files line by line.',
    ObjectSchema(Props, ['query'])));

  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('File or directory relative to the workspace'));
  ATools.Add(BuildTool('fs_stat', 'Returns metadata for a file or directory.',
    ObjectSchema(Props, ['path'])));

  Props := TJSONObject.Create;
  Props.Add('path', StringProperty('Directory relative to the workspace'));
  ATools.Add(BuildTool('fs_create_directory', 'Creates a directory tree.',
    ObjectSchema(Props, ['path'])));

  Props := TJSONObject.Create;
  Props.Add('source', StringProperty('Source path relative to the workspace'));
  Props.Add('target', StringProperty('Target path relative to the workspace'));
  ATools.Add(BuildTool('fs_move', 'Moves or renames a file or directory.',
    ObjectSchema(Props, ['source', 'target'])));

  Props := TJSONObject.Create;
  Props.Add('source', StringProperty('Source file relative to the workspace'));
  Props.Add('target', StringProperty('Target file relative to the workspace'));
  ATools.Add(BuildTool('fs_copy', 'Copies a file.',
    ObjectSchema(Props, ['source', 'target'])));

  if FAllowDelete then
  begin
    Props := TJSONObject.Create;
    Props.Add('path', StringProperty('File or empty directory relative to the workspace'));
    ATools.Add(BuildTool('fs_delete',
      'Deletes a file or empty directory.',
      ObjectSchema(Props, ['path'])));
  end;
end;

function TFilesystemToolProvider.HandlesTool(const AName: string): Boolean;
begin
  Result := (AName = 'fs_list') or (AName = 'fs_read') or
    (AName = 'fs_write') or (AName = 'fs_replace') or
    (AName = 'fs_search') or (AName = 'fs_stat') or
    (AName = 'fs_create_directory') or (AName = 'fs_move') or
    (AName = 'fs_copy') or ((AName = 'fs_delete') and FAllowDelete);
end;

function TFilesystemToolProvider.CallTool(const AName: string;
  AArguments: TJSONObject; const ACorrelationId: string): TJSONObject;
var
  Structured: TJSONData;
  Obj: TJSONObject;
  Summary: string;
begin
  Structured := nil;
  if AName = 'fs_list' then
    Structured := FFsTools.ListDirectory(AArguments)
  else if AName = 'fs_read' then
    Structured := FFsTools.ReadFile(AArguments)
  else if AName = 'fs_write' then
    Structured := FFsTools.WriteFile(AArguments)
  else if AName = 'fs_replace' then
    Structured := FFsTools.ReplaceText(AArguments)
  else if AName = 'fs_search' then
    Structured := FFsTools.SearchFiles(AArguments)
  else if AName = 'fs_stat' then
    Structured := FFsTools.StatPath(AArguments)
  else if AName = 'fs_create_directory' then
    Structured := FFsTools.MakeDirectory(AArguments)
  else if AName = 'fs_move' then
    Structured := FFsTools.MovePath(AArguments)
  else if AName = 'fs_copy' then
    Structured := FFsTools.CopyFilePath(AArguments)
  else if AName = 'fs_delete' then
    Structured := FFsTools.DeletePath(AArguments);

  if Structured = nil then
    raise Exception.CreateFmt('Unknown filesystem tool: %s', [AName]);

  Obj := TJSONObject(Structured);
  if AName = 'fs_list' then
  begin
    if Obj.Find('entries') <> nil then
      Summary := Format('%d directory entries returned for %s.',
        [TJSONArray(Obj.Find('entries')).Count, JsonString(Obj, 'path', '.')])
    else
      Summary := 'Directory listing returned.';
  end
  else if AName = 'fs_read' then
    Summary := Format('Read %d bytes from %s. File content is in structuredContent.content.',
      [JsonInteger(Obj, 'bytes_read', 0), JsonString(Obj, 'path')])
  else if AName = 'fs_search' then
  begin
    if Obj.Find('results') <> nil then
      Summary := Format('%d filesystem search results returned.',
        [TJSONArray(Obj.Find('results')).Count])
    else
      Summary := 'Filesystem search completed.';
  end
  else if AName = 'fs_write' then
    Summary := Format('Wrote %d bytes to %s.',
      [JsonInteger(Obj, 'bytes_written', 0), JsonString(Obj, 'path')])
  else if AName = 'fs_replace' then
    Summary := 'Text replacement completed.'
  else if AName = 'fs_stat' then
    Summary := 'Filesystem metadata returned.'
  else if AName = 'fs_create_directory' then
    Summary := 'Directory creation completed.'
  else if AName = 'fs_move' then
    Summary := 'Move operation completed.'
  else if AName = 'fs_copy' then
    Summary := 'Copy operation completed.'
  else if AName = 'fs_delete' then
    Summary := 'Delete operation completed.'
  else
    Summary := 'Filesystem operation completed.';

  Result := NewToolTextResult(Summary, Structured, False);
end;

function TFilesystemToolProvider.ResolvePath(const APath: string): string;
begin
  Result := FFsTools.ResolvePath(APath);
end;

end.
