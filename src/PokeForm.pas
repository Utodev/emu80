{ PokeForm: dialog to POKE memory ("35899,0" or "35899,0 : 36000,201"),
  with the last 20 POKEs used and the file they were applied to. }
unit PokeForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Dialogs, Pokes;

type
  TApplyPokes = procedure(const Pokes: TPokeList) of object;

{ Show the dialog. CurrentFile is the last file loaded ('' if none); Apply
  writes the POKEs. }
procedure ShowPokeDialog(const CurrentFile: string; Apply: TApplyPokes);

implementation

uses
  Config, Lang;

type
  TPokeDialog = class(TForm)
  public
    Edit: TEdit;
    List: TListBox;
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
  end;

procedure TPokeDialog.ListClick(Sender: TObject);
var
  Entry: string;
begin
  if List.ItemIndex < 0 then Exit;
  Entry := Settings.PokeHistory[List.ItemIndex];
  Edit.Text := Copy(Entry, Pos('|', Entry) + 1, MaxInt);
end;

procedure TPokeDialog.ListDblClick(Sender: TObject);
begin
  ListClick(Sender);
  ModalResult := mrOK;
end;

procedure ShowPokeDialog(const CurrentFile: string; Apply: TApplyPokes);
var
  Dlg: TPokeDialog;
  Lbl: TLabel;
  Btn: TButton;
  I, P: Integer;
  Entry, Name, Error: string;
  Pokes: TPokeList;
begin
  Dlg := TPokeDialog.CreateNew(Application.MainForm, 0);
  try
    Dlg.Caption := 'POKE';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 440;
    Dlg.ClientHeight := 380;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.AutoSize := False;
    Lbl.SetBounds(10, 10, 420, 36);
    Lbl.WordWrap := True;
    Lbl.Caption := _('Address,value (decimal, or hex with $). Several POKEs separated by ":",' +
      ' e.g.  35899,0 : 36000,201');
    Dlg.Edit := TEdit.Create(Dlg);
    Dlg.Edit.Parent := Dlg;
    Dlg.Edit.SetBounds(10, 50, 420, 24);
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.SetBounds(10, 84, 420, 18);
    Lbl.Caption := _('Last POKEs (click to use, double-click to apply):');
    Dlg.List := TListBox.Create(Dlg);
    Dlg.List.Parent := Dlg;
    Dlg.List.SetBounds(10, 106, 420, 220);
    for I := 0 to Settings.PokeHistory.Count - 1 do
    begin
      Entry := Settings.PokeHistory[I];
      P := Pos('|', Entry);
      Name := Copy(Entry, 1, P - 1);
      if Name <> '' then
        Dlg.List.Items.Add(Name + ':  ' + Copy(Entry, P + 1, MaxInt))
      else
        Dlg.List.Items.Add(Copy(Entry, P + 1, MaxInt));
    end;
    Dlg.List.OnClick := @Dlg.ListClick;
    Dlg.List.OnDblClick := @Dlg.ListDblClick;
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'POKE';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(270, 340, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := _('Close');
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(355, 340, 75, 28);
    Dlg.ActiveControl := Dlg.Edit;
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      if ParsePokes(Dlg.Edit.Text, Pokes, Error) then Break;
      MessageDlg(Error, mtError, [mbOK], 0);
    until False;
    Apply(Pokes);
    Settings.AddPoke(CurrentFile, Trim(Dlg.Edit.Text));
  finally
    Dlg.Free;
  end;
end;

end.
