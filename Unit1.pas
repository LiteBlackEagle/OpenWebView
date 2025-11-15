unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, Vcl.Dialogs, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Winapi.WebView2, Winapi.ActiveX,
  Vcl.ExtCtrls, Edge, threading, Winapi.EdgeUtils,
  Vcl.ComCtrls,System.JSON,shellapi, Vcl.StdCtrls, System.NetEncoding,
  System.DateUtils, System.IOUtils, System.Hash, math
  ;

type
  NTSTATUS = Longint;
  TProcFunction = function(ProcHandle: THandle): NTSTATUS; stdcall;
const
  STATUS_SUCCESS = $00000000;
  PROCESS_SUSPEND_RESUME = $0800;
var
 NtSuspendProcess: TProcFunction;
 NtResumeProcess: TProcFunction;
 ProcHandle: THandle;
 LibHandle: THandle;

type
  TOpenWebViewAI = class(TForm)
    Label1: TLabel;
    Panel1: TPanel;
    EdgeBrowser0: TEdgeBrowser;
    Panel2: TPanel;
    Splitter1: TSplitter;
    Panel3: TPanel;
    EdgeBrowser00: TEdgeBrowser;
    Panel4: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure EdgeBrowser0CreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure EdgeBrowser0DevToolsProtocolEventReceived(Sender: TCustomEdgeBrowser; const CDPEventName, AParameterObjectAsJson: string);
    procedure EdgeBrowser0NavigationCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure EdgeBrowser0HistoryChanged(Sender: TCustomEdgeBrowser);
    procedure EdgeBrowser0WebMessageReceived(Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
    procedure EdgeBrowser0WebResourceRequested(Sender: TCustomEdgeBrowser; Args: TWebResourceRequestedEventArgs);
    procedure EdgeBrowser0NewWindowRequested(Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
    procedure EdgeBrowser0NavigationStarting(Sender: TCustomEdgeBrowser; Args: TNavigationStartingEventArgs);
    procedure EdgeBrowser2HistoryChanged(Sender: TCustomEdgeBrowser);
    procedure EdgeBrowser2NavigationStarting(Sender: TCustomEdgeBrowser; Args: TNavigationStartingEventArgs);
    procedure EdgeBrowser2NewWindowRequested(Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
    procedure EdgeBrowser2NavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure EdgeBrowser0DocumentTitleChanged(Sender: TCustomEdgeBrowser;
      const ADocumentTitle: string);
  private
    procedure ControlCreate;
  public
  end;

var
  OpenWebViewAI: TOpenWebViewAI;
  loadz,zlocaload:byte;
  DevList,WhiteList,BlackList:Tstringlist;
  DZ,Ddev,DWebUI,Ddownload,Ddownloado,Ddownloadv,Ddownloadp,Dsettings: string;
  folderbrowser,favibrowser,downloadbrowser,historybrowser,localbrowser,activebrowser,aibrowser:TCustomEdgeBrowser;
  limittime,CurrentTime,LastTime:int64;
  webView2_19: ICoreWebView2_19;
  Deferral: ICoreWebView2Deferral;
  LSizeInBytes,LSizeInBytes2: Int64;
  API_PORT :integer;
  chis:string;

  brcount:integer=12;
  edgebrowser: array [1 .. 12] of TEdgeBrowser;

implementation

uses
  Zhex, Zplug, Zstr, Zprompt;

{$R *.dfm}

function EnPri(const Value: BOOLEAN): BOOLEAN;
const
  SE_DEBUG_NAME = ' SeDebugPrivilege ';
var
  hToken: THandle;
  tp: TOKEN_PRIVILEGES;
  d: DWORD;
begin
  result := False;
  if OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES, hToken) then
  begin
    tp.PrivilegeCount := 1;
    LookupPrivilegeValue(nil, SE_DEBUG_NAME, tp.Privileges[0].Luid);
    if Value then
      tp.Privileges[0].Attributes := $00000002
    else
      tp.Privileges[0].Attributes := $80000000;
    AdjustTokenPrivileges(hToken, False, tp, SizeOf(TOKEN_PRIVILEGES), nil, d);
    if GetLastError = ERROR_SUCCESS then
    begin
      result := true;
    end;
    CloseHandle(hToken);
  end;
end;

procedure DeleteFileOnReboot(const FileName: string);
begin
  if not MoveFileEx(PChar(FileName), nil, MOVEFILE_DELAY_UNTIL_REBOOT) then
    RaiseLastOSError;
end;

function LoadDllFromHexString(const HexString: string): HMODULE;
var
  BinaryData: TBytes;
  TempDir, TempFileName: string;
  TempPath: array[0..MAX_PATH] of Char;
  TempFileStream: TFileStream;
  DllHandle: HMODULE;
begin
  SetLength(BinaryData, Length(HexString) div 2);
  HexToBin(PChar(HexString), @BinaryData[0], Length(BinaryData));

  GetTempPath(MAX_PATH, TempPath);
  TempDir := IncludeTrailingPathDelimiter(TempPath) + Format('TempDllDir_%s', [FormatDateTime('yyyymmddhhnnsszzz', Now)]);
  if not DirectoryExists(TempDir) then
    CreateDir(TempDir);

  TempFileName := IncludeTrailingPathDelimiter(TempDir) + 'WebView2Loader.dll';
  TempFileStream := TFileStream.Create(TempFileName, fmCreate);
  try
    TempFileStream.WriteBuffer(BinaryData[0], Length(BinaryData));
  finally
    TempFileStream.Free;
  end;

  DllHandle := LoadLibrary(PChar(TempFileName));
  if DllHandle <> 0 then
  begin
    DeleteFileOnReboot(TempFileName);
  end
  else
    raise Exception.Create('Zero DLL.');

  Result := DllHandle;
end;

function checkfilename(const FileName: UnicodeString): UnicodeString;
const
  InvalidChars: array[0..9] of Char = ('\', '/', ':', '*', '?', '"', '<', '>', '|', ' ');
var
  i: Integer;
begin
  Result := FileName;
  for i := 1 to Length(Result) do
  begin
    if Pos(Result[i], InvalidChars) > 0 then
      Result[i] := '-';
  end;
end;

function ExtractFolderName(const Path: string): string;
var
  FolderName: string;
begin
  FolderName := ExcludeTrailingPathDelimiter(Path);
  FolderName := ExtractFileName(FolderName);
  Result := FolderName;
end;
//==============================================================================

procedure TOpenWebViewAI.ControlCreate;
var
  i: Integer;
begin
  for i := 1 to brcount do
  begin
    edgebrowser[i] := TEdgeBrowser.Create(Self);

    edgebrowser[i].Parent := Self.Panel2;
    edgebrowser[i].Align := alClient;
    edgebrowser[i].Visible := false;

    edgebrowser[i].Tag := i;

    edgebrowser[i].OnCreateWebViewCompleted := EdgeBrowser0CreateWebViewCompleted;
    edgebrowser[i].OnDevToolsProtocolEventReceived := EdgeBrowser0DevToolsProtocolEventReceived;
    edgebrowser[i].OnDocumentTitleChanged := EdgeBrowser0DocumentTitleChanged;

    edgebrowser[i].OnHistoryChanged := EdgeBrowser0HistoryChanged;
    edgebrowser[i].OnNavigationCompleted := EdgeBrowser0NavigationCompleted;
    edgebrowser[i].OnNavigationStarting := EdgeBrowser0NavigationStarting;
    edgebrowser[i].OnNewWindowRequested := EdgeBrowser0NewWindowRequested;

    edgebrowser[i].OnWebMessageReceived := EdgeBrowser0WebMessageReceived;
    edgebrowser[i].OnWebResourceRequested := EdgeBrowser0WebResourceRequested;

    //edgebrowser[i].UserDataFolder:= EdgeBrowser0.UserDataFolder;
    edgebrowser[i].UserDataFolder:='AICenter\WebUI\WebView'+i.ToString;
  end;
end;


procedure ListCreate;
begin
  TTHREAD.Synchronize(nil,
  PROCEDURE
  BEGIN
    BlackList := TStringList.Create;
    begin
      BlackList.Add('ads');
      BlackList.Add('admicro');
      BlackList.Add('bet');
      BlackList.Add('banner');
    end;
    WhiteList := TStringList.Create;
    begin
    end;
  END);
end;

procedure dircreate;
begin
  DZ:=getcurrentdir + '\AICenter';
  Ddev := DZ+'\Dev';
  DWebUI:= DZ+'\WebUI';
  Dsettings := DZ+'\Settings';
  Ddownload := DZ+'\Download';
  Ddownloado := DZ+'\Download\Other';
  Ddownloadv := DZ+'\Download\Video';
  Ddownloadp := DZ+'\Download\Picture';

  if not DirectoryExists(DZ) then
  begin
    CreateDir(DZ);
  end;

  if not DirectoryExists(Dsettings) then
  begin
    CreateDir(Dsettings);
  end;

  if not DirectoryExists(Ddev) then
  begin
    CreateDir(Ddev);
  end;

  if not DirectoryExists(DWebUI) then
  begin
    CreateDir(DWebUI);
  end;

  if not DirectoryExists(Ddownload) then
  begin
    CreateDir(Ddownload);
  end;

  if not DirectoryExists(Ddownloado) then
  begin
    CreateDir(Ddownloado);
  end;
  if not DirectoryExists(Ddownloadp) then
  begin
    CreateDir(Ddownloadp);
  end;
  if not DirectoryExists(Ddownloadv) then
  begin
    CreateDir(Ddownloadv);
  end;
end;

procedure Navigate(const Edge: TCustomEdgeBrowser; AUri: string);
var
  FullUri: string;
begin
tthread.CreateAnonymousThread(
procedure
begin
  try
    if (AUri.StartsWith('about:blank'))
    or (AUri.StartsWith('edge:')) then
    begin
     tthread.Synchronize(nil,
       procedure
       begin
        Edge.Navigate(AUri);
        Edge.hint := AUri;
       end);
      Exit;
    end;

    if (AUri.ToLower.StartsWith('127.0.0.1')) then
    begin
     tthread.Synchronize(nil,
       procedure
       begin
        Edge.Navigate('http://'+AUri);
        Edge.hint := AUri;
       end);
      Exit;
    end;

    if AUri[2]=':' then
    begin
     tthread.Synchronize(nil,
       procedure
       begin
        Edge.Navigate('file:///' + AUri);
        Edge.hint := AUri;
       end);
      Exit;
    end;

    if AUri.ToLower.StartsWith('file:///') then
    begin
     tthread.Synchronize(nil,
       procedure
       begin
        Edge.Navigate(AUri);
        Edge.hint := AUri;
       end);
      Exit;
    end;

    if AUri.ToLower.StartsWith('localhost')
    or AUri.ToLower.StartsWith('http://localhost')
    or AUri.ToLower.StartsWith('about:blank') then
    begin
     tthread.Synchronize(nil,
       procedure
       begin
        Edge.Navigate(AUri);
        Edge.hint := AUri;
       end);
      Exit;
    end;

    if not AUri.ToLower.StartsWith('http') then
      FullUri := 'https://' + AUri
    else
      FullUri := AUri;
    if Pos('.', AUri) > 0 then
    begin
       tthread.Synchronize(nil,
       procedure
       begin
       Edge.Navigate(PChar(FullUri));
       end);
    end
    else
    begin
     tthread.Synchronize(nil,
       procedure
       begin
          Edge.Navigate('https://www.google.com/search?q=' + AUri);
       end);
    end;
    Edge.hint := AUri;
  finally
  end;
end).start;
end;

procedure TOpenWebViewAI.EdgeBrowser0CreateWebViewCompleted(
  Sender: TCustomEdgeBrowser; AResult: HRESULT);
var
 DevToolsReceiver: ICoreWebView2DevToolsProtocolEventReceiver;
 hr: HRESULT;
 webView2_13: ICoreWebView2_13;
 Settings: ICoreWebView2Settings;
 Profile2: ICoreWebView2Profile;
 Profile6: ICoreWebView2Profile6;
begin

    hr := Sender.DefaultInterface.GetDevToolsProtocolEventReceiver('', DevToolsReceiver);
    if SUCCEEDED(hr) then
    begin
      // Enable Console
      Sender.DefaultInterface.CallDevToolsProtocolMethod('Console.enable', '{}', nil);
      Sender.SubscribeToCDPEvent('Console.messageAdded');

      // Enable Network
      Sender.DefaultInterface.CallDevToolsProtocolMethod('Network.enable', '{}', nil);
      Sender.SubscribeToCDPEvent('Network.requestWillBeSent');
      Sender.SubscribeToCDPEvent('Network.responseReceived');
      Sender.SubscribeToCDPEvent('Network.requestServedFromCache');
      Sender.SubscribeToCDPEvent('Network.loadingFinished');
      Sender.SubscribeToCDPEvent('Network.responseReceivedExtraInfo');
      Sender.SubscribeToCDPEvent('Network.dataReceived');

      // Enable Fetch
      Sender.SubscribeToCDPEvent('Fetch.requestPaused');
      Sender.SubscribeToCDPEvent('Fetch.authRequired');
      Sender.SubscribeToCDPEvent('Fetch.requestServedFromCache');
      Sender.SubscribeToCDPEvent('Fetch.responseReceived');


      // Enable Page
      Sender.DefaultInterface.CallDevToolsProtocolMethod('Page.enable', '{}', nil);
      Sender.SubscribeToCDPEvent('Page.frameNavigated');
      Sender.SubscribeToCDPEvent('Page.frameStartedLoading');
      Sender.SubscribeToCDPEvent('Page.frameScheduledNavigation');{}
    end;

    Sender.DefaultInterface.AddWebResourceRequestedFilter('*',COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);

    if SUCCEEDED(ICoreWebView2(Sender.DefaultInterface).get_Settings(Settings)) then
    begin
      Settings.Set_IsStatusBarEnabled(0);
      Settings.Set_AreDefaultContextMenusEnabled(1);
      Settings.Set_IsWebMessageEnabled(1);
    end;


    if Supports(ICoreWebView2(Sender.DefaultInterface), ICoreWebView2_13,webView2_13) then
    begin
      webView2_13.Get_Profile(Profile2);

      if Supports(Profile2, ICoreWebView2Profile6, Profile6) then
      begin
        Profile6.Set_PreferredColorScheme(COREWEBVIEW2_PREFERRED_COLOR_SCHEME_DARK);
        Profile6.Set_IsPasswordAutosaveEnabled(1);
        Profile6.Set_IsGeneralAutofillEnabled(1);

        if DirectoryExists(Ddownload) then
        Profile6.Set_DefaultDownloadFolderPath(PWideChar(Ddownload));
      end;
    end;

end;
procedure TOpenWebViewAI.EdgeBrowser0DevToolsProtocolEventReceived(
  Sender: TCustomEdgeBrowser; const CDPEventName,
  AParameterObjectAsJson: string);
var
  JsonValue: TJsonValue;
  JsonObject, ResponseObject: TJsonObject;
  RequestId, RequestUrl, FrameId, Method: string;
  ResponseSize, ContentLength: Int64;
begin
  if Sender.tag >= 0 then
  begin
  TThread.Synchronize(nil,
    procedure
    begin
      if AParameterObjectAsJson <> '' then
      begin
        try
          Sender.DefaultInterface.CallDevToolsProtocolMethod('Fetch.enable', '{"patterns":[{"requestStage":"Request"}]}', nil);

          if SameText(CDPEventName, 'Console.messageAdded') then
          begin
            JsonValue := TJSONObject.ParseJSONValue(AParameterObjectAsJson);
            try
              if JsonValue is TJSONObject then
              begin
                JsonObject := JsonValue as TJSONObject;
                if JsonObject <> nil then
                begin
                  var Level: string;
                  if JsonObject.TryGetValue('message.level', Level) and
                     SameText(Level, 'error') then
                  begin
                    var Column, Line: Integer;
                    var Source, Text, Url: string;

                    JsonObject.TryGetValue('message.column', Column);
                    JsonObject.TryGetValue('message.line', Line);
                    JsonObject.TryGetValue('message.source', Source);
                    JsonObject.TryGetValue('message.text', Text);
                    JsonObject.TryGetValue('message.url', Url);

                    var ErrorLog: string;
                    ErrorLog := Format(
                      '{"column":%d,"level":"%s","line":%d,"source":"%s","text":"%s","url":"%s"}',
                      [Column, Level, Line, Source, Text, Url]);
                  end
                  else
                  begin
                  end;
                end;
              end;
            finally
              JsonValue.Free;
            end;
          end;

          if SameText(CDPEventName, 'Network.requestWillBeSent') then
          begin
            JsonValue := TJSONObject.ParseJSONValue(AParameterObjectAsJson);
            try
              if JsonValue is TJSONObject then
              begin
                JsonObject := JsonValue as TJSONObject;
                JsonObject.TryGetValue('requestId', RequestId);
                JsonObject.TryGetValue('request.url', RequestUrl);
              end;
            finally
              JsonValue.Free;
            end;
          end;

          if SameText(CDPEventName, 'Network.responseReceived') then
          begin
              JsonValue := TJSONObject.ParseJSONValue(AParameterObjectAsJson);
              try
                if JsonValue is TJSONObject then
                begin
                  JsonObject := JsonValue as TJSONObject;
                  ResponseObject := JsonObject.GetValue('response') as TJSONObject;
                  JsonObject.TryGetValue('request.frameId', FrameId);
                  ResponseObject.TryGetValue('encodedDataLength', ResponseSize);
                  ResponseObject.TryGetValue('url', RequestUrl);
                  ResponseObject.TryGetValue('mimeType', Method);

                  var HeadersObject := ResponseObject.GetValue('headers') as TJSONObject;
                  if Assigned(HeadersObject) and HeadersObject.TryGetValue('content-length', ContentLength) then
                  begin
                  end;
                end;
              finally
                JsonValue.Free;
              end;
              Exit;
          end;


        finally
          JsonObject := TJSONObject.ParseJSONValue(AParameterObjectAsJson) as TJSONObject;
          try
            if JsonObject.TryGetValue('requestId', RequestId) then
              Sender.DefaultInterface.CallDevToolsProtocolMethod('Fetch.continueRequest', PWideChar(Format('{"requestId":"%s"}', [RequestId])), nil);
          finally
            JsonObject.Free;
          end;
        end;
      end;
    end);
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser0DocumentTitleChanged(
  Sender: TCustomEdgeBrowser; const ADocumentTitle: string);
begin
caption:=sender.DocumentTitle;
end;

procedure TOpenWebViewAI.EdgeBrowser0HistoryChanged(Sender: TCustomEdgeBrowser);
begin
  begin
    sender.hint:=sender.LocationURL;

    if (trim(sender.hint)<>'')
    and (not sender.hint.StartsWith('https://private-local-server')) then
    begin
      if sender.tag >= 0  then
      begin
        TFile.WriteAllText(DwebUI+'\LastUri'+sender.tag.tostring+'.json', sender.hint);
      end;

       if Sender = localbrowser then
      begin
        TFile.WriteAllText(DwebUI+'\LastLocalUri.json', sender.hint);
      end;
    end;
  end;

  if chis<>sender.hint then
  begin
    chis:=sender.hint;
    zNotifier(sender,sender.Hint,0);
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser0NavigationCompleted(
  Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
  WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin;
  tthread.CreateAnonymousThread(
    procedure
    begin
    lockWindowUpdate(0);
    end).Start;

  sender.hint:=sender.LocationURL;

  begin
    if loadz<>1 then
    begin
      if sender.tag >= 0 then
      begin
        if not fileexists (DwebUI+'\LastUri'+sender.tag.tostring+'.json') then
        begin
        Sender.ExecuteScript(zload);
        sender.ExecuteScript(zKeyMapper);
        end
        else
        begin
          var x:=TFile.ReadAllText(DwebUI+'\LastUri'+sender.tag.tostring+'.json');
          if trim(x)<>'' then
          Navigate(activebrowser,x);
        end;
      end;
     loadz:=1;
    end;

    if zlocaload<>1 then
    begin
       if Sender = localbrowser then
      begin
        if not fileexists (DwebUI+'\LastLocalUri.json') then
        begin
        Sender.ExecuteScript(zload);
        end
        else
        begin
          var x:=TFile.ReadAllText(DwebUI+'\LastLocalUri.json');
          if trim(x)<>'' then
          Navigate(localbrowser,x);
        end;
      end;
      zlocaload:=1;
    end;

  end;
//==============================================================================
  begin
    begin
     //sender.ExecuteScript(zDB_script);
     zDB_script(sender,sender.tag);

     sender.ExecuteScript(zKeyMapper);
     sender.ExecuteScript(zkernel);
    end;

    if sender.tag >= 0 then
    begin
      Sender.ExecuteScript(zContextMenu);
      Sender.ExecuteScript(zContextMenu2);
      //sender.ExecuteScript(zZone);
    end;

    begin
      //Sender.ExecuteScript(zMediaPopup);
      sender.ExecuteScript(zMiniAlbum);

      sender.ExecuteScript(zErrorLogger);
    end;


  end;
end;

procedure TOpenWebViewAI.EdgeBrowser0NavigationStarting(
  Sender: TCustomEdgeBrowser; Args: TNavigationStartingEventArgs);
begin
  var uri: PWideChar;
  var urlx:string;
  var xx,yy,zz:string;

  Args.ArgsInterface.Get_uri(uri);
  urlx:=(uri);
  sender.Hint:=urlx;

  if (urlx.StartsWith('file:///')) then
  begin
    urlx:=(Copy(urlx, 9, Length(urlx)));
    urlx:=StringReplace(urlx, '/', '\', [rfReplaceAll]);
    urlx:=StringReplace(urlx, '%20', ' ', [rfReplaceAll]);

    xx:=ExtractFileName(urlx);
    yy:=ExtractFilePath(urlx);
    zz:=checkfilename(ExtractFolderName(ExtractFilePath(urlx)));

    if (FileExists(urlx)) and (DirectoryExists(yy)) then
    begin
      if Supports(sender.DefaultInterface, ICoreWebView2_19, webView2_19) then
      begin
        webView2_19.SetVirtualHostNameToFolderMapping(PWideChar('private-local-server'+'-'+zz),
        PWideChar(yy),
        COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
        sender.Navigate('https://private-local-server'+'-'+zz+'/'+xx);
      end;
    end;
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser0NewWindowRequested(
  Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
begin
  var uri: PWideChar;
  var urlx:string;

  Args.ArgsInterface.Get_uri(uri);
  urlx:=((uri));
  Args.ArgsInterface.Set_Handled(1);

  if (urlx.StartsWith('file:///')) then
  begin
    urlx:=(Copy(urlx, 9, Length(urlx)));
    urlx:=StringReplace(urlx, '/', '\', [rfReplaceAll]);
    urlx:=StringReplace(urlx, '%20', ' ', [rfReplaceAll]);
    Navigate(sender,PChar(urlx));
  end
  else
  begin
    if (pos(sender.hint,urlx)<>0)
    or (pos('google.com',urlx)<>0)
    then
    Navigate(sender,PChar(urlx));
  end;
end;

function FormatBytes(const ABytes: Int64): string;
const
  Units: array[0..5] of string = ('Byte', 'KB', 'MB', 'GB', 'TB', 'PB');
var
  LSize: Double;
  LUnitIndex: Integer;
begin
  if ABytes <= 0 then
    Exit('0 B');

  LSize := ABytes;
  LUnitIndex := Floor(LogN(1024, LSize));
  if LUnitIndex > High(Units) then
    LUnitIndex := High(Units);

  LSize := LSize / Power(1024, LUnitIndex);

  if LUnitIndex > 0 then
    Result := Format('%.2f %s', [LSize, Units[LUnitIndex]])
  else
    Result := Format('%d %s', [Round(LSize), Units[LUnitIndex]]);
end;

procedure SaveBase64ToFile(const ABase64String, AFilePath, AFileName: string);
var
  LBytes: TBytes;
  LFileStream: TFileStream;
  LCorrectBase64: string;
  PosComma: Integer;
begin
  if not DirectoryExists(AFilePath) then
    ForceDirectories(AFilePath);

  PosComma := Pos(',', ABase64String);
  if PosComma > 0 then
    LCorrectBase64 := Copy(ABase64String, PosComma + 1, Length(ABase64String))
  else
    LCorrectBase64 := ABase64String;

  try
    LBytes := TNetEncoding.Base64.DecodeStringToBytes(LCorrectBase64);
    LFileStream := TFileStream.Create(TPath.Combine(AFilePath, AFileName), fmCreate);
    try
      if Length(LBytes) > 0 then
        LFileStream.WriteBuffer(LBytes[0], Length(LBytes));
    finally
      LFileStream.Free;
    end;
  except
    on E: Exception do
    begin
      raise;
    end;
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser0WebMessageReceived(
  Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
var
  MessageData: PWideChar;
  jsonStringFromWebView, innerJsonString: string;
  jsonValueOuter, jsonValueInner: TJSONValue;
  LJsonObject: TJSONObject;
  LTypeVal, LDataVal, LMessageVal: TJSONValue;
  LTypeStr, LMessageUrl, LBase64Data, LPromptText: string;
  LMediaDataObj, LDataObj: TJSONObject;
  LPayloadToSend: TJSONObject;
begin
  jsonValueOuter := nil;
  jsonValueInner := nil;
  try
    Args.ArgsInterface.Get_webMessageAsJson(MessageData);
    if not Assigned(MessageData) then
      Exit;

    jsonStringFromWebView := MessageData;
    jsonValueOuter := TJSONObject.ParseJSONValue(jsonStringFromWebView);
    if not (Assigned(jsonValueOuter) and (jsonValueOuter is TJSONString)) then
      Exit;

    innerJsonString := (jsonValueOuter as TJSONString).Value;
    LSizeInBytes := Length(innerJsonString) * SizeOf(WideChar);

    var x: string := innerJsonString;
    if Length(x) > 1000 then
    begin
      SetLength(x, 1000);
      x := x + '...';
    end;
    caption:=x;


    jsonValueInner := TJSONObject.ParseJSONValue(innerJsonString);
    if not (Assigned(jsonValueInner) and (jsonValueInner is TJSONObject)) then
      Exit;

    LJsonObject := jsonValueInner as TJSONObject;

    if LJsonObject.TryGetValue('type', LTypeVal) and (LTypeVal is TJSONString) then
    begin
      LTypeStr := (LTypeVal as TJSONString).Value;

      if LJsonObject.TryGetValue('data', LDataVal) and (LDataVal is TJSONObject) then
      begin
        LDataObj := LDataVal as TJSONObject;
//==============================================================================
        if (LTypeStr = 'ZKeyMapperText') then
        begin
          if LDataObj.TryGetValue('text', LMessageVal) and (LMessageVal is TJSONString) then
          begin
            LMessageUrl := (LMessageVal as TJSONString).Value;
            if not LMessageUrl.IsEmpty then
            begin
              Navigate(activebrowser, LMessageUrl);
            end;
          end;
          Exit;
        end;
//==============================================================================
        if (LTypeStr = 'ZKernelLog') then
        begin
          if LJsonObject.TryGetValue('data', LDataVal) and (LDataVal is TJSONObject) then
          begin
            LDataObj := LDataVal as TJSONObject;
            if LDataObj.TryGetValue('message', LMessageVal) and (LMessageVal is TJSONString) then
            begin
              var LLogMessage := (LMessageVal as TJSONString).Value;
              if not LLogMessage.IsEmpty then
              begin
                zNotifier(Sender as TCustomEdgeBrowser, LLogMessage,5);
              end;
            end;
          end;
          Exit;
        end;
//==============================================================================
        if (LTypeStr = 'ZKeyMapperSettingsRequest') then
        begin
          if Panel3.Width <> 0 then
            //Panel3.Width := 0
          else
            //Panel3.Width := screen.Width div 2;
          Exit;
        end;
//==============================================================================
        if (LTypeStr = 'ZContextMenu2Send') then
        begin
          LBase64Data := '';
          LPromptText := '';

          if LDataObj.TryGetValue('text', LMessageVal) and (LMessageVal is TJSONString) then
          begin
            LPromptText := (LMessageVal as TJSONString).Value;
          end;

          if LDataObj.TryGetValue('mediaData', LMessageVal) and (LMessageVal is TJSONObject) then
          begin
            LMediaDataObj := LMessageVal as TJSONObject;
            if LMediaDataObj.TryGetValue('data', LMessageVal) and (LMessageVal is TJSONString) then
            begin
              LBase64Data := (LMessageVal as TJSONString).Value;
            end;
          end;

          if not LBase64Data.IsEmpty then
          begin
            LPayloadToSend := TJSONObject.Create;
            try
              LPayloadToSend.AddPair('image', TJSONString.Create(LBase64Data));
              LPayloadToSend.AddPair('prompt', TJSONString.Create(LPromptText));

              if Assigned(localbrowser) and Assigned(localbrowser.DefaultInterface) then
              begin
                localbrowser.DefaultInterface.PostWebMessageAsString(PWideChar(LPayloadToSend.ToString));
                zNotifier(Sender, 'Sent captured media and prompt to local browser.',1);
                zNotifier(localbrowser, 'Media and prompt received for processing.',1);
              end
              else
              begin
                 zNotifier(Sender, 'Error: Could not send to local browser.',1);
              end;
            finally
              LPayloadToSend.Free;
            end;
          end;
          Exit;
        end;
//==============================================================================
        if (LTypeStr = 'ZFaviconBarSwitch') then
        begin
          var LSlotId:integer;

          if LDataObj.TryGetValue('switchToId', LSlotId) then
          begin

           if (LSlotId>0) and (sender.tag <>LSlotId) then
           begin
             if assigned(edgebrowser[LSlotId]) then
             begin
             edgebrowser[LSlotId].Visible:=true;
             activebrowser:=edgebrowser[LSlotId];
             activebrowser.tag:=edgebrowser[LSlotId].tag;

              begin
                if not fileexists (DwebUI+'\LastUri'+activebrowser.tag.tostring+'.json') then
                begin
                 var BlankPagePath := DWebUI + '\private-local-server.html';
                 if not FileExists(BlankPagePath) then
                 TFile.WriteAllText(BlankPagePath, zprivatelocalserver);
                 Navigate(activebrowser, BlankPagePath);
                end
                else
                begin
                  var xx:=TFile.ReadAllText(DwebUI+'\LastUri'+activebrowser.tag.tostring+'.json');

                  if trim(xx)<>'' then
                  Navigate(activebrowser,xx);
                end;
              end;
             end;
           end;

           if (LSlotId=0) then
           begin
             edgebrowser0.Visible:=true;
             activebrowser:=edgebrowser0;;
           end;

           for var i := 1 to brcount do
            begin
            if LSlotId<>i then
            edgebrowser[i].Visible:=false;
            end;
          end;
          Exit;
        end;
//==============================================================================
      end;
    end;
  finally
    if Assigned(jsonValueInner) then
      jsonValueInner.Free;
    if Assigned(jsonValueOuter) then
      jsonValueOuter.Free;
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser0WebResourceRequested(
  Sender: TCustomEdgeBrowser; Args: TWebResourceRequestedEventArgs);
var
  resourceContext: COREWEBVIEW2_WEB_RESOURCE_CONTEXT;
  request: ICoreWebView2WebResourceRequest;
  uri: PWideChar;
  urlx: string;
begin
  tthread.Synchronize(nil,
  procedure
  begin
    Args.ArgsInterface.Get_ResourceContext(resourceContext);
    Args.ArgsInterface.Get_Request(request);

    request.Get_uri(uri);

    begin
      urlx := uri;

      if length(urlx)>100 then
      setlength(urlx,100);

      if BlackList.Count > 0 then
       begin
          if (resourceContext<> 0)
          and (resourceContext<> 1)
          and (resourceContext<> 6)
          and (resourceContext<> 7)
          then
          begin
                  var X: string;
                  for var i := 0 to BlackList.Count - 1 do
                  begin
                    X := (BlackList[i]);
                    if Length(X) > 48 then
                    SetLength(X, 48);

                    if (Pos(X, uri) <> 0)
                    and (Pos('loads', uri) = 0) then
                    begin
                      request.Set_uri(PWideChar(''));
                      Break;
                    end;
                  end;
          end;
       end;

     if sender.tag >= 0 then
     begin
        if (SUCCEEDED(Args.ArgsInterface.GetDeferral(Deferral))) and Assigned(request)
        then
        begin
            case resourceContext of
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_IMAGE:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_MEDIA:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_SCRIPT:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_XML_HTTP_REQUEST:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FETCH:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_STYLESHEET:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_TEXT_TRACK:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_WEBSOCKET:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_MANIFEST:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_SIGNED_EXCHANGE:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_PING:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_CSP_VIOLATION_REPORT:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_OTHER:
                begin
                end;
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_EVENT_SOURCE:
                begin
                end;
            else
              begin
              end;
            end;
            Deferral.Complete;
        end;
      end;
    END;
  end);
end;

procedure TOpenWebViewAI.EdgeBrowser2HistoryChanged(Sender: TCustomEdgeBrowser);
begin
  var startTime: Double;
  var endTime: Double;
  var SysTime: TSystemTime;
  var handler: ICoreWebView2ClearBrowsingDataCompletedHandler;
  var WebView213: ICoreWebView2_13;
  var Profile2: ICoreWebView2Profile;
  var Profile6: ICoreWebView2Profile6;

  GetSystemTime(SysTime);
  endTime := DateTimeToUnix(EncodeDateTime(
  SysTime.wYear, SysTime.wMonth, SysTime.wDay,
  SysTime.wHour, SysTime.wMinute, SysTime.wSecond, 0))+1;
  startTime := endTime - 2.0;

  ICoreWebView2_13(sender.DefaultInterface).Get_Profile(Profile2);
  if Supports(Profile2, ICoreWebView2Profile6, Profile6) then
  begin
    if profile6.ClearBrowsingDataInTimeRange($00001000, startTime, endTime, handler)=s_ok then
    begin
    end;
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser2NavigationCompleted(
  Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
  WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin
//
end;

procedure TOpenWebViewAI.EdgeBrowser2NavigationStarting(
  Sender: TCustomEdgeBrowser; Args: TNavigationStartingEventArgs);
begin
  var uri: PWideChar;
  var urlx: string;
  Args.ArgsInterface.Get_uri(uri);
  urlx := uri;

  if (historybrowser.LocationURL <> '')
  and (not urlx.StartsWith('data:text'))
  and (not urlx.StartsWith('edge://')) then
  begin
    Args.ArgsInterface.Set_Cancel(1);
    if (urlx) <> '' then
    begin
      Navigate(activebrowser,uri);
    end;
  end;
end;

procedure TOpenWebViewAI.EdgeBrowser2NewWindowRequested(
  Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
var
  Handled: Integer;
  uri: PWideChar;
  urlx:string;
begin
  Args.ArgsInterface.Get_Handled(Handled);
  Args.ArgsInterface.Get_uri(uri);
  urlx:=uri;
  Args.ArgsInterface.Set_Handled(1);

  if (sender.LocationURL <> '')
  and (not urlx.StartsWith('data:text'))
  and (not urlx.StartsWith('edge://')) then
  begin
    if (urlx) <> '' then
    begin
     Navigate(activebrowser,uri);
    end;
  end;
end;

procedure TOpenWebViewAI.FormActivate(Sender: TObject);
begin
 try
    if not FileExists('WebView2Loader.dll') then
    begin
      {$IFDEF WIN64}
      LoadDllFromHexString(dll64);
      {$ELSE}
      LoadDllFromHexString(dll32);
      {$ENDIF}
    end;
  finally
    LibHandle := SafeLoadLibrary('ntdll.dll');
    if LibHandle <> 0 then
    try
      @NtSuspendProcess := GetProcAddress(LibHandle, 'NtSuspendProcess');
      @NtResumeProcess := GetProcAddress(LibHandle, 'NtResumeProcess');
    finally
    end;
  end;

try
 EnPri(True);
 ListCreate;
 dircreate;
 ControlCreate;
finally

 if Panel3.Width <> 0 then
 Panel3.Width := screen.Width div 2;

 //activebrowser:=EdgeBrowser0;
 //activebrowser.navigate('about:blank');

 activebrowser := EdgeBrowser0;

 var BlankPagePath := DWebUI + '\private-local-server.html';
 if not FileExists(BlankPagePath) then
 TFile.WriteAllText(BlankPagePath, zprivatelocalserver);
 Navigate(activebrowser, BlankPagePath);

 localbrowser:=EdgeBrowser00;
 localbrowser.Navigate('http://127.0.0.1:8000');

 //localbrowser.Navigate('http://127.0.0.1:42003');
 end;
end;

procedure TOpenWebViewAI.FormCreate(Sender: TObject);
begin
  OpenWebViewAI.Align:=ALCLIENT;
end;

end.
