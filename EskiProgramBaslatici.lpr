program EskiProgramBaslatici;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL widgetset
  Forms, MainUnit;

{$R *.res}

begin
  Application.Title := 'Eski Program Başlatıcı';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
