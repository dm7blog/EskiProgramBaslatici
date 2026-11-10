unit MainUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  StdCtrls, Menus, IniFiles, Process, contnrs, LazUTF8;

type
  // pkWin16 = otvdmw.exe ile, pkDos = DOSBox ile,
  // pkWin32 / pkWin64 = doğrudan çalıştırılır (sıra ini uyumu için değişmemeli)
  TProgKind = (pkWin16, pkDos, pkWin32, pkWin64);

  TEntry = class
    Name: string;      // kullanıcının verdiği ad (boşsa dosya adı kullanılır)
    Path: string;
    Params: string;
    Kind: TProgKind;
    function DisplayName: string;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    // Bileşenler MainUnit.lfm içinde tanımlıdır
    pnlTop: TPanel;
    btnAdd: TButton;
    btnSettings: TButton;
    btnDosbox: TButton;
    lvProgs: TListView;
    imgList: TImageList;
    popMenu: TPopupMenu;
    miRun: TMenuItem;
    miSet: TMenuItem;
    miRemove: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure DoAdd(Sender: TObject);
    procedure DoSettings(Sender: TObject);
    procedure DoDosboxOnly(Sender: TObject);
    procedure LVMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure LVDblClick(Sender: TObject);
    procedure PopupOpen(Sender: TObject);
    procedure DoRun(Sender: TObject);
    procedure DoEntrySettings(Sender: TObject);
    procedure DoRemove(Sender: TObject);
  private
    FEntries: TObjectList;
    FOtvdm: string;   // otvdmw.exe yolu
    FDosbox: string;  // dosbox.exe yolu
    FOtvdmParams: string;   // otvdmw.exe için genel parametreler
    FDosboxParams: string;  // DOSBox için genel parametreler
    FDefaultDir: string;    // Ekle'de açılan varsayılan klasör
    FIniFile: string;
    FSetEdOtvdm, FSetEdDosbox, FSetEdPath, FSetEdDefDir: TEdit;
    function  MakeIcon(const E: TEntry): TBitmap;
    function  CurrentEntry: TEntry;
    function  EnsureTool(Kind: TProgKind): Boolean;
    function  DetectKind(const FileName: string): TProgKind;
    procedure LoadConfig;
    procedure SaveConfig;
    procedure Rebuild;
    procedure Launch(E: TEntry);
    procedure BrowseTool(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  AppVersion = '1.6';

// Derleme tarihi/saati derleyici tarafından yazılır: {$I %DATE%} = YYYY/MM/DD
function BuildDateStr: string;
const
  D = {$I %DATE%};
  T = {$I %TIME%};
begin
  Result := Copy(D, 9, 2) + '.' + Copy(D, 6, 2) + '.' + Copy(D, 1, 4) +
    ' ' + Copy(T, 1, 5);
end;

{ TEntry }

function TEntry.DisplayName: string;
begin
  if Trim(Name) <> '' then
    Result := Name
  else
    Result := ChangeFileExt(ExtractFileName(Path), '');
end;

// Simgeleri ada göre (büyük/küçük harf duyarsız) sıralar
function CompareEntries(Item1, Item2: Pointer): Integer;
begin
  Result := UTF8CompareText(TEntry(Item1).DisplayName, TEntry(Item2).DisplayName);
  if Result = 0 then
    Result := UTF8CompareStr(TEntry(Item1).Path, TEntry(Item2).Path);
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'Eski Program Başlatıcı - (' + AppVersion +
    ' - ' + BuildDateStr + ')';
  FEntries := TObjectList.Create(True);
  FIniFile := ChangeFileExt(Application.ExeName, '.ini');
  LoadConfig;
  Rebuild;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FEntries.Free;
end;

{ ---------- yapılandırma ---------- }

procedure TMainForm.LoadConfig;
var
  Ini: TIniFile;
  Cnt, i: Integer;
  E: TEntry;
  S: string;
begin
  FEntries.Clear;
  if not FileExists(FIniFile) then Exit;
  Ini := TIniFile.Create(FIniFile);
  try
    FOtvdm := Ini.ReadString('Ayarlar', 'Otvdmw', '');
    FDosbox := Ini.ReadString('Ayarlar', 'DosBox', '');
    FOtvdmParams := Ini.ReadString('Ayarlar', 'OtvdmwParametre', '');
    FDosboxParams := Ini.ReadString('Ayarlar', 'DosBoxParametre', '');
    FDefaultDir := Ini.ReadString('Ayarlar', 'VarsayilanYol', '');
    Cnt := Ini.ReadInteger('Ayarlar', 'Sayi', 0);
    for i := 0 to Cnt - 1 do
    begin
      S := 'Program' + IntToStr(i);
      E := TEntry.Create;
      E.Name := Ini.ReadString(S, 'Ad', '');
      E.Path := Ini.ReadString(S, 'Yol', '');
      E.Params := Ini.ReadString(S, 'Parametre', '');
      E.Kind := TProgKind(Ini.ReadInteger(S, 'Tur', 0));
      FEntries.Add(E);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.SaveConfig;
var
  Ini: TIniFile;
  i: Integer;
  E: TEntry;
  S: string;
begin
  if FileExists(FIniFile) then DeleteFile(FIniFile);
  Ini := TIniFile.Create(FIniFile);
  try
    Ini.WriteString('Ayarlar', 'Otvdmw', FOtvdm);
    Ini.WriteString('Ayarlar', 'DosBox', FDosbox);
    Ini.WriteString('Ayarlar', 'OtvdmwParametre', FOtvdmParams);
    Ini.WriteString('Ayarlar', 'DosBoxParametre', FDosboxParams);
    Ini.WriteString('Ayarlar', 'VarsayilanYol', FDefaultDir);
    Ini.WriteInteger('Ayarlar', 'Sayi', FEntries.Count);
    for i := 0 to FEntries.Count - 1 do
    begin
      E := TEntry(FEntries[i]);
      S := 'Program' + IntToStr(i);
      Ini.WriteString(S, 'Ad', E.Name);
      Ini.WriteString(S, 'Yol', E.Path);
      Ini.WriteString(S, 'Parametre', E.Params);
      Ini.WriteInteger(S, 'Tur', Ord(E.Kind));
    end;
  finally
    Ini.Free;
  end;
end;

{ ---------- simge ve liste ---------- }

function TMainForm.MakeIcon(const E: TEntry): TBitmap;
var
  Tagg, Ch: string;
begin
  Result := TBitmap.Create;
  Result.SetSize(48, 48);
  with Result.Canvas do
  begin
    Brush.Color := clWhite;
    FillRect(0, 0, 48, 48);
    case E.Kind of
      pkWin16:
        begin
          Brush.Color := RGBToColor(0, 90, 170);
          Tagg := 'W16';
        end;
      pkWin32:
        begin
          Brush.Color := RGBToColor(0, 130, 80);
          Tagg := 'W32';
        end;
      pkWin64:
        begin
          Brush.Color := RGBToColor(140, 40, 150);
          Tagg := 'W64';
        end;
    else
      begin
        Brush.Color := RGBToColor(40, 40, 40);
        Tagg := 'DOS';
      end;
    end;
    Pen.Color := clGray;
    RoundRect(2, 2, 46, 46, 8, 8);
    Font.Color := clWhite;
    Font.Style := [fsBold];
    Font.Size := 16;
    Ch := UpperCase(Copy(E.DisplayName, 1, 1));
    TextOut((48 - TextWidth(Ch)) div 2, 6, Ch);
    Font.Size := 8;
    TextOut((48 - TextWidth(Tagg)) div 2, 31, Tagg);
  end;
end;

procedure TMainForm.Rebuild;
var
  i: Integer;
  E: TEntry;
  Bmp: TBitmap;
  It: TListItem;
begin
  FEntries.Sort(@CompareEntries);   // otomatik alfabetik sıralama
  lvProgs.Items.BeginUpdate;
  try
    lvProgs.Items.Clear;
    imgList.Clear;
    for i := 0 to FEntries.Count - 1 do
    begin
      E := TEntry(FEntries[i]);
      Bmp := MakeIcon(E);
      try
        imgList.Add(Bmp, nil);
      finally
        Bmp.Free;
      end;
      It := lvProgs.Items.Add;
      It.Caption := E.DisplayName;
      It.ImageIndex := i;
      It.Data := E;
    end;
  finally
    lvProgs.Items.EndUpdate;
  end;
end;

function TMainForm.CurrentEntry: TEntry;
begin
  if lvProgs.Selected <> nil then
    Result := TEntry(lvProgs.Selected.Data)
  else
    Result := nil;
end;

{ ---------- program türünü otomatik belirleme ---------- }

// .com/.bat ve düz MZ (DOS) -> DOSBox; NE (Win16) -> otvdmw;
// PE -> makine türüne göre 32 bit veya 64 bit (doğrudan çalıştırılır)
function TMainForm.DetectKind(const FileName: string): TProgKind;
var
  FS: TFileStream;
  Ext: string;
  W, Machine: Word;
  Off: LongWord;
  Sig: array[0..1] of Char;
begin
  Result := pkWin16;
  Ext := LowerCase(ExtractFileExt(FileName));
  if (Ext = '.com') or (Ext = '.bat') then
  begin
    Result := pkDos;
    Exit;
  end;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Result := pkDos;
      if FS.Size < 64 then Exit;
      FS.ReadBuffer(W, 2);
      if W <> $5A4D then Exit;                 // 'MZ' değil
      FS.Position := $3C;
      FS.ReadBuffer(Off, 4);
      if (Off < 64) or (Int64(Off) + 2 > FS.Size) then Exit;  // sadece DOS başlığı
      FS.Position := Off;
      FS.ReadBuffer(Sig, 2);
      if (Sig[0] = 'N') and (Sig[1] = 'E') then
        Result := pkWin16
      else if (Sig[0] = 'P') and (Sig[1] = 'E') then
      begin
        Result := pkWin32;
        if Int64(Off) + 6 <= FS.Size then
        begin
          FS.Position := Int64(Off) + 4;       // IMAGE_FILE_HEADER.Machine
          FS.ReadBuffer(Machine, 2);
          if (Machine = $8664) or (Machine = $AA64) or (Machine = $0200) then
            Result := pkWin64;                 // x64, ARM64, IA64
        end;
      end
      else
        Result := pkDos;                       // LE/LX gibi DOS genişleticiler
    finally
      FS.Free;
    end;
  except
    Result := pkWin16;
  end;
end;

{ ---------- araç yolları ---------- }

function TMainForm.EnsureTool(Kind: TProgKind): Boolean;
var
  Dlg: TOpenDialog;
begin
  if Kind in [pkWin32, pkWin64] then
  begin
    Result := True;                          // emülatör gerekmez
    Exit;
  end;
  if Kind = pkWin16 then
    Result := (FOtvdm <> '') and FileExists(FOtvdm)
  else
    Result := (FDosbox <> '') and FileExists(FDosbox);
  if Result then Exit;

  Dlg := TOpenDialog.Create(nil);
  try
    if Kind = pkWin16 then
    begin
      Dlg.Title := 'otvdmw.exe dosyasını seçin';
      Dlg.Filter := 'otvdmw.exe|otvdmw.exe|Programlar|*.exe';
    end
    else
    begin
      Dlg.Title := 'DOSBox.exe dosyasını seçin';
      Dlg.Filter := 'DOSBox|dosbox*.exe|Programlar|*.exe';
    end;
    Result := Dlg.Execute;
    if Result then
    begin
      if Kind = pkWin16 then FOtvdm := Dlg.FileName
      else FDosbox := Dlg.FileName;
      SaveConfig;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.DoSettings(Sender: TObject);
var
  F: TForm;
  EdOtvdm, EdDosbox, EdOtvdmPar, EdDosboxPar, EdDefDir: TEdit;
  BtnO, BtnD, BtnDir, BtnOk, BtnCancel: TButton;

  procedure AddLabel(const Txt: string; Y: Integer);
  var
    L: TLabel;
  begin
    L := TLabel.Create(F);
    L.Parent := F;
    L.SetBounds(12, Y, 496, 16);
    L.Caption := Txt;
  end;

  function AddEdit(const Val: string; Y, W: Integer): TEdit;
  begin
    Result := TEdit.Create(F);
    Result.Parent := F;
    Result.SetBounds(12, Y, W, 24);
    Result.Text := Val;
  end;

  function AddButton(const Cap: string; X, Y, W, H: Integer): TButton;
  begin
    Result := TButton.Create(F);
    Result.Parent := F;
    Result.SetBounds(X, Y, W, H);
    Result.Caption := Cap;
  end;

begin
  F := TForm.CreateNew(Self);
  try
    F.Caption := 'Ayarlar';
    F.Position := poOwnerFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 520;
    F.ClientHeight := 316;

    AddLabel('otvdmw.exe yolu:', 12);
    EdOtvdm := AddEdit(FOtvdm, 30, 420);
    BtnO := AddButton('Gözat...', 440, 29, 68, 26);
    AddLabel('otvdmw.exe parametreleri (program yolundan önce eklenir):', 62);
    EdOtvdmPar := AddEdit(FOtvdmParams, 80, 496);

    AddLabel('DOSBox yolu:', 116);
    EdDosbox := AddEdit(FDosbox, 134, 420);
    BtnD := AddButton('Gözat...', 440, 133, 68, 26);
    AddLabel('DOSBox parametreleri (program yolundan önce eklenir):', 166);
    EdDosboxPar := AddEdit(FDosboxParams, 184, 496);

    AddLabel('Varsayılan program klasörü (Ekle bu klasörde açılır):', 220);
    EdDefDir := AddEdit(FDefaultDir, 238, 420);
    BtnDir := AddButton('Gözat...', 440, 237, 68, 26);

    BtnOk := AddButton('Tamam', 332, 276, 80, 28);
    BtnOk.ModalResult := mrOK;
    BtnOk.Default := True;
    BtnCancel := AddButton('İptal', 424, 276, 80, 28);
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel := True;

    FSetEdOtvdm := EdOtvdm;
    FSetEdDosbox := EdDosbox;
    FSetEdDefDir := EdDefDir;
    BtnDir.Tag := 4;
    BtnDir.OnClick := @BrowseTool;
    BtnO.Tag := 1;
    BtnD.Tag := 2;
    BtnO.OnClick := @BrowseTool;
    BtnD.OnClick := @BrowseTool;

    if F.ShowModal = mrOK then
    begin
      FOtvdm := Trim(EdOtvdm.Text);
      FDosbox := Trim(EdDosbox.Text);
      FOtvdmParams := Trim(EdOtvdmPar.Text);
      FDosboxParams := Trim(EdDosboxPar.Text);
      FDefaultDir := Trim(EdDefDir.Text);
      SaveConfig;
    end;
  finally
    FSetEdOtvdm := nil;
    FSetEdDosbox := nil;
    FSetEdDefDir := nil;
    F.Free;
  end;
end;

procedure TMainForm.BrowseTool(Sender: TObject);
var
  Dlg: TOpenDialog;
  DirDlg: TSelectDirectoryDialog;
  Ed: TEdit;
begin
  if TComponent(Sender).Tag = 4 then
  begin
    DirDlg := TSelectDirectoryDialog.Create(nil);
    try
      DirDlg.Title := 'Varsayılan program klasörünü seçin';
      if DirectoryExists(FSetEdDefDir.Text) then
        DirDlg.InitialDir := FSetEdDefDir.Text;
      if DirDlg.Execute then FSetEdDefDir.Text := DirDlg.FileName;
    finally
      DirDlg.Free;
    end;
    Exit;
  end;
  Dlg := TOpenDialog.Create(nil);
  try
    if TComponent(Sender).Tag = 1 then
    begin
      Ed := FSetEdOtvdm;
      Dlg.Title := 'otvdmw.exe dosyasını seçin';
      Dlg.Filter := 'otvdmw.exe|otvdmw.exe|Programlar|*.exe';
    end
    else if TComponent(Sender).Tag = 3 then
    begin
      Ed := FSetEdPath;
      Dlg.Title := 'Çalıştırılacak programı seçin';
      Dlg.Filter := 'Programlar|*.exe;*.com;*.bat|Tüm dosyalar|*.*';
    end
    else
    begin
      Ed := FSetEdDosbox;
      Dlg.Title := 'DOSBox.exe dosyasını seçin';
      Dlg.Filter := 'DOSBox|dosbox*.exe|Programlar|*.exe';
    end;
    if Dlg.Execute then Ed.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

{ ---------- ekleme ---------- }

procedure TMainForm.DoAdd(Sender: TObject);
var
  Dlg: TOpenDialog;
  E: TEntry;
begin
  E := nil;
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Çalıştırılacak programı seçin';
    Dlg.Filter := 'Programlar|*.exe;*.com;*.bat|Tüm dosyalar|*.*';
    if (FDefaultDir <> '') and DirectoryExists(FDefaultDir) then
      Dlg.InitialDir := FDefaultDir;       // ayarlardaki varsayılan klasör
    if not Dlg.Execute then Exit;

    E := TEntry.Create;
    E.Path := Dlg.FileName;
    E.Kind := DetectKind(Dlg.FileName);   // otomatik; sağ tıkla değiştirilebilir
    if E.Kind = pkDos then E.Params := '-exit';
    FEntries.Add(E);
  finally
    Dlg.Free;
  end;
  SaveConfig;
  Rebuild;
  Launch(E);                              // eklenir eklenmez çalıştır
end;

{ ---------- çalıştırma ---------- }

procedure TMainForm.Launch(E: TEntry);
var
  P: TProcess;
  ToolParams: string;
begin
  if not EnsureTool(E.Kind) then Exit;
  if not FileExists(E.Path) then
  begin
    ShowMessage('Program bulunamadı:' + LineEnding + E.Path);
    Exit;
  end;

  P := TProcess.Create(nil);
  try
    P.CurrentDirectory := ExtractFilePath(E.Path);
    if E.Kind in [pkWin32, pkWin64] then
    begin
      // 32/64 bit Windows programı: emülatörsüz, doğrudan çalıştır
      P.Executable := E.Path;
    end
    else
    begin
      if E.Kind = pkWin16 then
      begin
        P.Executable := FOtvdm;
        ToolParams := FOtvdmParams;
      end
      else
      begin
        P.Executable := FDosbox;
        ToolParams := FDosboxParams;
      end;
      // 1) ayarlardaki araç parametreleri (varsa)
      if Trim(ToolParams) <> '' then
        CommandToList(ToolParams, P.Parameters);
      // 2) çalıştırılacak program
      P.Parameters.Add(E.Path);
    end;
    // 3) simgeye ait parametreler (varsa)
    if Trim(E.Params) <> '' then
      CommandToList(E.Params, P.Parameters);
    P.Options := [];
    try
      P.Execute;
    except
      on Ex: Exception do
        ShowMessage('Çalıştırılamadı: ' + Ex.Message);
    end;
  finally
    P.Free; // süreç kapanmaz, sadece nesne serbest bırakılır
  end;
end;

// DOSBox'ı programsız, yalnızca ayarlardaki DOSBox parametreleriyle başlatır
procedure TMainForm.DoDosboxOnly(Sender: TObject);
var
  P: TProcess;
begin
  if not EnsureTool(pkDos) then Exit;
  P := TProcess.Create(nil);
  try
    P.Executable := FDosbox;
    P.CurrentDirectory := ExtractFilePath(FDosbox);
    if Trim(FDosboxParams) <> '' then
      CommandToList(FDosboxParams, P.Parameters);
    P.Options := [];
    try
      P.Execute;
    except
      on Ex: Exception do
        ShowMessage('Çalıştırılamadı: ' + Ex.Message);
    end;
  finally
    P.Free;
  end;
end;

procedure TMainForm.LVMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbRight then
    lvProgs.Selected := lvProgs.GetItemAt(X, Y); // sağ tıklanan simge seçilsin
end;

// Tek tık: simgeyi seçer (ListView kendisi yapar). Çift tık: çalıştırır.
procedure TMainForm.LVDblClick(Sender: TObject);
var
  P: TPoint;
  It: TListItem;
begin
  P := lvProgs.ScreenToClient(Mouse.CursorPos);
  It := lvProgs.GetItemAt(P.X, P.Y);   // boş alana çift tıklanırsa çalışmaz
  if It <> nil then
    Launch(TEntry(It.Data));
end;

{ ---------- sağ tık menüsü ---------- }

procedure TMainForm.PopupOpen(Sender: TObject);
var
  Has: Boolean;
begin
  Has := CurrentEntry <> nil;
  miRun.Enabled := Has;
  miSet.Enabled := Has;
  miRemove.Enabled := Has;
end;

procedure TMainForm.DoRun(Sender: TObject);
begin
  if CurrentEntry <> nil then Launch(CurrentEntry);
end;

// Simgeye ait yol, parametre ve çalıştırma programı (otvdmw / DOSBox) seçimi
procedure TMainForm.DoEntrySettings(Sender: TObject);
var
  E: TEntry;
  F: TForm;
  EdName, EdPath, EdParams: TEdit;
  RG: TRadioGroup;
  BtnP, BtnOk, BtnCancel: TButton;
  NewKind: TProgKind;
  NewName, NewPath, NewParams: string;

  procedure AddLabel(const Txt: string; Y: Integer);
  var
    L: TLabel;
  begin
    L := TLabel.Create(F);
    L.Parent := F;
    L.SetBounds(12, Y, 496, 16);
    L.Caption := Txt;
  end;

  function AddEdit(const Val: string; Y, W: Integer): TEdit;
  begin
    Result := TEdit.Create(F);
    Result.Parent := F;
    Result.SetBounds(12, Y, W, 24);
    Result.Text := Val;
  end;

  function AddButton(const Cap: string; X, Y, W, H: Integer): TButton;
  begin
    Result := TButton.Create(F);
    Result.Parent := F;
    Result.SetBounds(X, Y, W, H);
    Result.Caption := Cap;
  end;

begin
  E := CurrentEntry;
  if E = nil then Exit;
  F := TForm.CreateNew(Self);
  try
    F.Caption := 'Ayarla - ' + E.DisplayName;
    F.Position := poOwnerFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 520;
    F.ClientHeight := 354;

    AddLabel('Simge adı (boş bırakılırsa dosya adı kullanılır):', 12);
    EdName := AddEdit(E.Name, 30, 496);

    AddLabel('Çalıştırılacak programın yolu:', 66);
    EdPath := AddEdit(E.Path, 84, 420);
    BtnP := AddButton('Gözat...', 440, 83, 68, 26);

    AddLabel('Parametreler (programdan sonra eklenir):', 120);
    EdParams := AddEdit(E.Params, 138, 496);

    RG := TRadioGroup.Create(F);
    RG.Parent := F;
    RG.SetBounds(12, 174, 496, 118);
    RG.Caption := 'Şununla çalıştır';
    RG.Items.Add('otvdmw.exe (Windows 16 bit)');
    RG.Items.Add('DOSBox (DOS)');
    RG.Items.Add('Doğrudan (Windows 32 bit)');
    RG.Items.Add('Doğrudan (Windows 64 bit)');
    RG.ItemIndex := Ord(E.Kind);

    BtnOk := AddButton('Tamam', 332, 312, 80, 28);
    BtnOk.ModalResult := mrOK;
    BtnOk.Default := True;
    BtnCancel := AddButton('İptal', 424, 312, 80, 28);
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel := True;

    FSetEdPath := EdPath;
    BtnP.Tag := 3;
    BtnP.OnClick := @BrowseTool;

    if F.ShowModal = mrOK then
    begin
      NewName := Trim(EdName.Text);
      NewPath := Trim(EdPath.Text);
      NewParams := Trim(EdParams.Text);
      NewKind := TProgKind(RG.ItemIndex);
      // tür değişti ve parametre elle değiştirilmediyse varsayılanı uyarla
      if (NewKind <> E.Kind) and (NewParams = Trim(E.Params)) then
      begin
        if (NewKind = pkDos) and (NewParams = '') then
          NewParams := '-exit'
        else if (NewKind <> pkDos) and (NewParams = '-exit') then
          NewParams := '';
      end;
      E.Name := NewName;
      if NewPath <> '' then E.Path := NewPath;
      E.Params := NewParams;
      E.Kind := NewKind;
      SaveConfig;
      Rebuild;
    end;
  finally
    FSetEdPath := nil;
    F.Free;
  end;
end;

procedure TMainForm.DoRemove(Sender: TObject);
var
  E: TEntry;
begin
  E := CurrentEntry;
  if E = nil then Exit;
  if MessageDlg('Kaldır', '"' + E.DisplayName + '" simgesi kaldırılsın mı?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    lvProgs.Selected := nil;
    FEntries.Remove(E); // nesneyi de serbest bırakır
    SaveConfig;
    Rebuild;
  end;
end;

end.
