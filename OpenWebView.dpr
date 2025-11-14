program OpenWebView;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {OpenWebViewAI},
  Vcl.Themes,
  Vcl.Styles;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Windows10 Dark');
  Application.CreateForm(TOpenWebViewAI, OpenWebViewAI);
  Application.Run;
end.
