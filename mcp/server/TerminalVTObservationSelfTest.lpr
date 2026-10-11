program TerminalVTObservationSelfTest;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, TerminalScreen, TerminalVTParser, TerminalObservation;

procedure Require(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('VT self-test failed: ' + AMessage);
end;

var
  Screen: TTerminalScreen;
  Parser: TTerminalVTParser;
  Observation: TTerminalObservationState;
  Capture: TTerminalObservationCapture;
  Text: UTF8String;
  I: Integer;
begin
  Screen := TTerminalScreen.Create(20, 4, 200);
  Parser := TTerminalVTParser.Create(Screen);
  Observation := TTerminalObservationState.Create;
  try
    Parser.Feed('progress 0%'#13'progress 50%'#13'progress 100%'#13#10'done');
    Text := Screen.RenderCurrentScreen;
    Require(Pos('progress 100%', string(Text)) > 0,
      'carriage-return overwrite did not preserve final progress value');
    Require(Pos('progress 0%', string(Text)) = 0,
      'carriage-return repaint leaked old progress frame');

    Screen.Reset;
    Parser.Reset;
    Parser.Feed('alpha'#13#10'beta');
    Parser.Feed(#27'[Homega'#27'[K');
    Text := Screen.RenderCurrentScreen;
    Require(Pos('omega', string(Text)) > 0,
      'cursor-home repaint did not update the first line');
    Require(Pos('alpha', string(Text)) = 0,
      'cursor-home repaint retained overwritten text');

    Parser.Feed(#27'[?1049hFRAME1'#27'[HFRAME2'#27'[K');
    Require(Screen.AlternateActive, 'alternate screen did not activate');
    Text := Screen.RenderCurrentScreen;
    Require(Pos('FRAME2', string(Text)) > 0,
      'alternate-screen repaint missing latest frame');
    Require(Pos('FRAME1', string(Text)) = 0,
      'alternate-screen repaint leaked old frame');
    Parser.Feed(#27'[?1049l');
    Require(not Screen.AlternateActive, 'alternate screen did not deactivate');
    Text := Screen.RenderCurrentScreen;
    Require(Pos('omega', string(Text)) > 0,
      'normal screen was not restored after alternate screen');

    Screen.Reset;
    Parser.Reset;
    for I := 1 to 100 do
      Parser.Feed(RawByteString(Format('line-%d'#13#10, [I])));
    Capture := Observation.Capture(Screen, 10000, 128);
    Require(Length(Capture.Text) <= 128,
      'observation exceeded configured byte limit');
    Require(Capture.OmittedBytes > 0,
      'large rendered state was not coalesced/truncated');
    Capture := Observation.Capture(Screen, 10000, 128);
    Require(Capture.Text = '',
      'coalesced old rendered state was queued as a later backlog');

    WriteLn('Terminal VT observation self-test: OK');
  finally
    Observation.Free;
    Parser.Free;
    Screen.Free;
  end;
end.
