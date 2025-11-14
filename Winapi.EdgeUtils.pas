{*******************************************************}
{                                                       }
{           CodeGear Delphi Runtime Library             }
{                                                       }
{ Copyright(c) 1995-2024 Embarcadero Technologies, Inc. }
{              All rights reserved                      }
{                                                       }
{   Copyright and license exceptions noted in source    }
{                                                       }
{*******************************************************}

unit Winapi.EdgeUtils;

interface

uses
  Winapi.Windows, Winapi.ActiveX, Winapi.WebView2;

type
  TCbStdProc1<T1> = reference to function(const P1: T1): HResult stdcall;
  TCbStdProc2<T1, T2> = reference to function(const P1: T1; const P2: T2): HResult stdcall;
  TCbStdProc3<T1, T2> = reference to function(P1: T1; P2: T2): HResult stdcall;
  TCbStdMethod1<T1> = function(P1: T1): HResult of object stdcall;
  TCbStdMethod2<T1, T2> = function(P1: T1; const P2: T2): HResult of object stdcall;

  // Helper types used to work with WinRT event interfaces
  Callback<T1, T2> = record
    type
      TStdProc1 = TCbStdProc1<T1>;
      TStdProc2 = TCbStdProc2<T1, T2>;
      TStdProc3 = TCbStdProc3<T1, T2>;
      TStdMethod1 = TCbStdMethod1<T1>;
      TStdMethod2 = TCbStdMethod2<T1, T2>;
    class function CreateAs<INTF>(P: TStdProc1): INTF; overload; static;
    class function CreateAs<INTF>(P: TStdProc2): INTF; overload; static;
    class function CreateAs<INTF>(P: TStdProc3): INTF; overload; static;
    class function CreateAs<INTF>(P: TStdMethod1): INTF; overload; static;
    class function CreateAs<INTF>(P: TStdMethod2): INTF; overload; static;
  end;

  // Microsoft's default implementation of ICoreWebView2EnvironmentOptions et al is in WebView2EnvironmentOptions.h
  TCoreWebView2EnvironmentOptions = class(TInterfacedObject, ICoreWebView2EnvironmentOptions)
  private
    FAdditionalBrowserArguments: string;
    FLanguage: string;
    FTargetCompatibleBrowserVersion: string;
    FAllowSingleSignOnUsingOSPrimaryAccount: BOOL;
    class function AllocCOMString(const DelphiString: string): PChar; static;
    class function BOOLToInt(Value: BOOL): Integer; inline; static;
  public
    // ICoreWebView2EnvironmentOptions
    function Get_AdditionalBrowserArguments(out value: PWideChar): HResult; stdcall;
    function Set_AdditionalBrowserArguments(value: PWideChar): HResult; stdcall;
    function Get_Language(out value: PWideChar): HResult; stdcall;
    function Set_Language(value: PWideChar): HResult; stdcall;
    function Get_TargetCompatibleBrowserVersion(out value: PWideChar): HResult; stdcall;
    function Set_TargetCompatibleBrowserVersion(value: PWideChar): HResult; stdcall;
    function Get_AllowSingleSignOnUsingOSPrimaryAccount(out allow: Integer): HResult; stdcall;
    function Set_AllowSingleSignOnUsingOSPrimaryAccount(allow: Integer): HResult; stdcall;
  end;

function SetWebView2Path(const APath: string): string;
function CheckWebView2Loaded: Boolean;
function IsEdgeSupported: Boolean;
function IsEdgeAvailable: Boolean;

// WebView2 loader DLL
function CreateCoreWebView2EnvironmentWithOptions(
  BrowserExecutableFolder, UserDataFolder: LPCWSTR; const EnvironmentOptions: ICoreWebView2EnvironmentOptions;
  const Environment_created_handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HRESULT; stdcall;

function CreateCoreWebView2Environment(
  const Environment_created_handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HRESULT; stdcall;

function GetCoreWebView2BrowserVersionString(BrowserExecutableFolder: LPCWSTR; var VersionInfo: LPWSTR): HRESULT; stdcall;

function CompareBrowserVersions(Version1, Version2: LPCWSTR; var AResult: Integer): HRESULT; stdcall;

implementation

uses
  System.SysUtils;

type
  TCreateCoreWebView2EnvironmentWithOptions = function(
    browserExecutableFolder, userDataFolder: LPCWSTR; const environmentOptions: ICoreWebView2EnvironmentOptions;
    const environment_created_handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HRESULT; stdcall;
  TCreateCoreWebView2Environment = function(
    const environment_created_handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HRESULT; stdcall;
  TGetCoreWebView2BrowserVersionInfo = function(browserExecutableFolder: LPCWSTR;
    var versionInfo: LPWSTR): HRESULT; stdcall;
  TCompareBrowserVersions = function (version1, version2: LPCWSTR; var result: Integer): HRESULT; stdcall;

var
  sWebView2Path: string = 'WebView2Loader.dll';
  hWebView2: THandle;
  _CreateCoreWebView2EnvironmentWithOptions: TCreateCoreWebView2EnvironmentWithOptions;
  _CreateCoreWebView2Environment: TCreateCoreWebView2Environment;
  _GetCoreWebView2BrowserVersionString: TGetCoreWebView2BrowserVersionInfo;
  _CompareBrowserVersions: TCompareBrowserVersions;

{ Callback<T1, T2> }

class function Callback<T1, T2>.CreateAs<INTF>(P: TStdProc1): INTF;
type
  PIntf = ^INTF;
begin
  Result := PIntf(@P)^;
end;

class function Callback<T1, T2>.CreateAs<INTF>(P: TStdProc2): INTF;
type
  PIntf = ^INTF;
begin
  Result := PIntf(@P)^;
end;

class function Callback<T1, T2>.CreateAs<INTF>(P: TStdProc3): INTF;
type
  PIntf = ^INTF;
begin
  Result := PIntf(@P)^;
end;

class function Callback<T1, T2>.CreateAs<INTF>(P: TStdMethod1): INTF;
begin
  Result := CreateAs<INTF>(
    function(const P1: T1): HResult stdcall
    begin
      Result := P(P1)
    end);
end;

class function Callback<T1, T2>.CreateAs<INTF>(P: TStdMethod2): INTF;
begin
  Result := CreateAs<INTF>(
    function(const P1: T1; const P2: T2): HResult stdcall
    begin
      Result := P(P1, P2)
    end);
end;

{ Routines }

function SetWebView2Path(const APath: string): string;
begin
  Result := sWebView2Path;
  sWebView2Path := APath;
end;

function CheckWebView2Loaded: Boolean;
begin
  if hWebView2 = 0 then
  begin
    hWebView2 := LoadLibrary(PChar(sWebView2Path));
    if hWebView2 = 0 then
      Exit(False);

    @_CreateCoreWebView2EnvironmentWithOptions := GetProcAddress(hWebView2, 'CreateCoreWebView2EnvironmentWithOptions');
    @_CreateCoreWebView2Environment := GetProcAddress(hWebView2, 'CreateCoreWebView2Environment');
    @_GetCoreWebView2BrowserVersionString := GetProcAddress(hWebView2, 'GetCoreWebView2BrowserVersionString');
    @_CompareBrowserVersions := GetProcAddress(hWebView2, 'CompareBrowserVersions');
  end;
  Result := True;
end;

function CreateCoreWebView2EnvironmentWithOptions(
  BrowserExecutableFolder, UserDataFolder: LPCWSTR; const EnvironmentOptions: ICoreWebView2EnvironmentOptions;
  const Environment_created_handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HRESULT; stdcall;
begin
  if CheckWebView2Loaded then
    Result := _CreateCoreWebView2EnvironmentWithOptions(
      BrowserExecutableFolder, UserDataFolder, EnvironmentOptions, Environment_created_handler)
  else
    Result := E_FAIL;
end;

function CreateCoreWebView2Environment(
  const Environment_created_handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HRESULT; stdcall;
begin
  if CheckWebView2Loaded then
    Result := _CreateCoreWebView2Environment(Environment_created_handler)
  else
    Result := E_FAIL;
end;

function GetCoreWebView2BrowserVersionString(BrowserExecutableFolder: LPCWSTR; var VersionInfo: LPWSTR): HRESULT; stdcall;
begin
  if CheckWebView2Loaded then
    Result := _GetCoreWebView2BrowserVersionString(BrowserExecutableFolder, VersionInfo)
  else
    Result := E_FAIL;
end;

function CompareBrowserVersions(Version1, Version2: LPCWSTR; var AResult: Integer): HRESULT; stdcall;
begin
  if CheckWebView2Loaded then
    Result := _CompareBrowserVersions(Version1, Version2, AResult)
  else
    Result := E_FAIL;
end;

function IsEdgeSupported: Boolean;
begin
  // Microsoft Edge browser only works on Windows 7 and above
  Result := TOSVersion.Check(6, 1);
end;

function IsEdgeAvailable: Boolean;
begin
  Result := IsEdgeSupported and CheckWebView2Loaded;
end;

{ TCoreWebView2EnvironmentOptions }

class function TCoreWebView2EnvironmentOptions.BOOLToInt(Value: BOOL): Integer;
begin
  // BOOL aka LongBool uses 0 for False and non-zero for True.
  // Specifically Delphi will assign the value of -1 (VARIANT_TRUE in C) for True when assigning to LongBool.
  // Note that WebView2 likes a BOOL value of TRUE to be 1, so we must take care not to cast BOOL to Integer.
  // See also: https://devblogs.microsoft.com/oldnewthing/20041222-00/?p=36923
  if Value then
    Result := 1
  else
    Result := 0;
end;

class function TCoreWebView2EnvironmentOptions.AllocCOMString(const DelphiString: string): PChar;
begin
  // In this class the caller (WebView2) will free the allocated memory
  var DelphiStringLength := Succ(DelphiString.Length);
  Result := CoTaskMemAlloc(DelphiStringLength * SizeOf(Char));
  StringToWideChar(DelphiString, Result, DelphiStringLength);
end;

function TCoreWebView2EnvironmentOptions.Get_AdditionalBrowserArguments(out value: PWideChar): HResult;
begin
  try
    value := AllocCOMString(FAdditionalBrowserArguments);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Get_Language(out value: PWideChar): HResult;
begin
  try
    value := AllocCOMString(FLanguage);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Get_TargetCompatibleBrowserVersion(out value: PWideChar): HResult;
begin
  try
    value := AllocCOMString(FTargetCompatibleBrowserVersion);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Get_AllowSingleSignOnUsingOSPrimaryAccount(out allow: Integer): HResult;
begin
  try
    allow := BOOLToInt(FAllowSingleSignOnUsingOSPrimaryAccount);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Set_AdditionalBrowserArguments(value: PWideChar): HResult;
begin
  try
    FAdditionalBrowserArguments := string(value);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Set_Language(value: PWideChar): HResult;
begin
  try
    FLanguage := string(value);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Set_TargetCompatibleBrowserVersion(value: PWideChar): HResult;
begin
  try
    FTargetCompatibleBrowserVersion := string(value);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

function TCoreWebView2EnvironmentOptions.Set_AllowSingleSignOnUsingOSPrimaryAccount(allow: Integer): HResult;
begin
  try
    FAllowSingleSignOnUsingOSPrimaryAccount := BOOL(allow);
    Result := S_OK
  except
    Result := E_FAIL
  end;
end;

initialization
  FSetExceptMask(femALLEXCEPT);

finalization
  if hWebView2 <> 0 then
  begin
    FreeLibrary(hWebView2);
    hWebView2 := 0;
  end;


end.
