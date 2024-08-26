{
================================================================================
Project : DControlsFix.dpk
File    : AKControlsFix.pas
Purpose : Remove Explicit* properties when saving to DFM, just to keep
          your DFMs smaller and the source control diffs less cluttered :-)

Credits :
- Andreas Hausladen for the Hooking Code (from VCLFixPack V1.4):
  https://www.idefixpack.de/blog/bugfix-units/vclfixpack-10/
  and for the DDevExtension pack.
  https://www.idefixpack.de/blog/ide-tools/ddevextensions/

- Jeremy North (JED Software) for the blog post explaining the backgrounds of
  those ExplicitXXXX properties:
  http://jedqc.blogspot.com/2006/02/d2006-what-on-earth-are-these-explicit.html

- Embarcadero for making Delphi :-)
================================================================================
}
unit AKControlsFix;

interface

uses
  ToolsAPI;

implementation

uses
  Winapi.Windows,
  System.Classes,
  Vcl.Controls;

procedure DebugLog(const S: string);
begin
  OutputDebugString(PChar('Patch installed: ' + S));
end;

{ Hooking }

type
  TJumpOfs = Integer;
  PPointer = ^Pointer;
  PXRedirCode = ^TXRedirCode;
  TXRedirCode = packed record
    Jump: Byte;
    Offset: TJumpOfs;
  end;

  PAbsoluteIndirectJmp = ^TAbsoluteIndirectJmp;
  TAbsoluteIndirectJmp = packed record
    OpCode: Word;   //$FF25(Jmp, FF /4)
    Addr: PPointer;
  end;

function GetActualAddr(Proc: Pointer): Pointer;
begin
  if Proc <> nil then
  begin
    if (PAbsoluteIndirectJmp(Proc).OpCode = $25FF) then
      Result := PAbsoluteIndirectJmp(Proc).Addr^
    else
      Result := Proc;
  end
  else
    Result := nil;
end;

procedure HookProc(Proc, Dest: Pointer; var BackupCode: TXRedirCode);
var
  n: NativeUInt;
  Code: TXRedirCode;
begin
  Proc := GetActualAddr(Proc);
  Assert(Proc <> nil);
  if ReadProcessMemory(GetCurrentProcess, Proc, @BackupCode, SizeOf(BackupCode), n) then
  begin
    Code.Jump := $E9;
    Code.Offset := PAnsiChar(Dest) - PAnsiChar(Proc) - SizeOf(Code);
    WriteProcessMemory(GetCurrentProcess, Proc, @Code, SizeOf(Code), n);
  end;
end;

procedure UnhookProc(Proc: Pointer; var BackupCode: TXRedirCode);
var
  n: NativeUInt;
begin
  if (BackupCode.Jump <> 0) and (Proc <> nil) then
  begin
    Proc := GetActualAddr(Proc);
    Assert(Proc <> nil);
    WriteProcessMemory(GetCurrentProcess, Proc, @BackupCode, SizeOf(BackupCode), n);
    BackupCode.Jump := 0;
  end;
end;

type
  TControlAccess = class(TControl);

var
  Control_DefineProperties: Pointer;
  BackupDefineProperties: TXRedirCode;

type
  TControlExplicitFix = class(TControl)
  private
    procedure ReadExplicitHeight(Reader: TReader);
    procedure ReadExplicitLeft(Reader: TReader);
    procedure ReadExplicitTop(Reader: TReader);
    procedure ReadExplicitWidth(Reader: TReader);
    procedure ReadIsControl(Reader: TReader);

    procedure WriteExplicitHeight(Writer: TWriter);
    procedure WriteExplicitLeft(Writer: TWriter);
    procedure WriteExplicitTop(Writer: TWriter);
    procedure WriteExplicitWidth(Writer: TWriter);
    procedure WriteIsControl(Writer: TWriter);
  protected
    procedure DefineProperties(Filer: TFiler); override;
  end;

procedure TControlExplicitFix.WriteExplicitTop(Writer: TWriter);
begin
  Writer.WriteInteger(FExplicitTop);
end;

procedure TControlExplicitFix.WriteExplicitHeight(Writer: TWriter);
begin
  Writer.WriteInteger(FExplicitHeight);
end;

procedure TControlExplicitFix.WriteExplicitLeft(Writer: TWriter);
begin
  Writer.WriteInteger(FExplicitLeft);
end;

procedure TControlExplicitFix.ReadExplicitWidth(Reader: TReader);
begin
  FExplicitWidth := Reader.ReadInteger;
end;

procedure TControlExplicitFix.WriteExplicitWidth(Writer: TWriter);
begin
  Writer.WriteInteger(FExplicitWidth);
end;

procedure TControlExplicitFix.ReadExplicitTop(Reader: TReader);
begin
  FExplicitTop := Reader.ReadInteger;
end;

procedure TControlExplicitFix.ReadExplicitHeight(Reader: TReader);
begin
  FExplicitHeight := Reader.ReadInteger;
end;

procedure TControlExplicitFix.ReadExplicitLeft(Reader: TReader);
begin
  FExplicitLeft := Reader.ReadInteger;
end;

procedure TControlExplicitFix.ReadIsControl(Reader: TReader);
begin
  IsControl := Reader.ReadBoolean;
end;

procedure TControlExplicitFix.WriteIsControl(Writer: TWriter);
begin
  Writer.WriteBoolean(IsControl);
end;

procedure TControlExplicitFix.DefineProperties(Filer: TFiler);
type
  TExplicitDimension = (edLeft, edTop, edWidth, edHeight);

  function DoWriteIsControl: Boolean;
  begin
    if Filer.Ancestor <> nil then
      Result := TControlAccess(Filer.Ancestor).IsControl <> IsControl
    else
      Result := IsControl;
  end;

  function DoWriteExplicit(Dim: TExplicitDimension): Boolean;
  begin
    Result := False;
  end;

begin
  // no inherited! See comment in Vcl.Controls.pas
  Filer.DefineProperty('IsControl', ReadIsControl, WriteIsControl, DoWriteIsControl);
  Filer.DefineProperty('ExplicitLeft', ReadExplicitLeft, WriteExplicitLeft, not (csReading in ComponentState) and DoWriteExplicit(edLeft));
  Filer.DefineProperty('ExplicitTop', ReadExplicitTop, WriteExplicitTop, not (csReading in ComponentState) and DoWriteExplicit(edTop));
  Filer.DefineProperty('ExplicitWidth', ReadExplicitWidth, WriteExplicitWidth, not (csReading in ComponentState) and DoWriteExplicit(edWidth));
  Filer.DefineProperty('ExplicitHeight', ReadExplicitHeight, WriteExplicitHeight, not (csReading in ComponentState) and DoWriteExplicit(edHeight));
end;

procedure InitControlExplicitFix;
begin
  // InitializeCriticalSection(DialogsTaskModalDialogCritSect);
  Control_DefineProperties := @TControlAccess.DefineProperties;
  HookProc(Control_DefineProperties, @TControlExplicitFix.DefineProperties, BackupDefineProperties);
  DebugLog('InitControlExplicitFix');
end;

procedure FiniControlExplicitFix;
begin
  UnhookProc(Control_DefineProperties, BackupDefineProperties);
end;

initialization
  InitControlExplicitFix;

finalization
  FiniControlExplicitFix;

end.
