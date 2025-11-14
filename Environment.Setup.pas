unit Environment.Setup;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.IOUtils, Environment.Defs;

type
  TEnvironmentSetup = class
  private
    FAppRootPath: string;
    FVenvPath: string;
    FEngineCorePath: string;
    FTempPath: string;
    FSetupScriptPath: string;

    function GetFullPath(const ASubDirConst: string): string;
    function GetCachePath(const ACacheSubDirConst: string): string;

    // REFACTOR: Helper to generate common script headers
    procedure GenerateBatchScriptHeader(const AContent: TStringList; ATitle: string; AIncludeColors: Boolean = False);

    procedure GenerateRunEngineScript;
    // REFACTOR: Merged into GenerateSetupScript
    // procedure GeneratePythonDependenciesInstaller;
    procedure GenerateSetupScript;

  public
    constructor Create(const AAppRootPath: string);
    function PrepareAndCreateAllScripts(const AServerPyContent: string;
      const APIHost: string; const APIPort: Integer): Boolean;
    function GetSetupScriptPath: string;
  end;

implementation

uses
  System.StrUtils;

constructor TEnvironmentSetup.Create(const AAppRootPath: string);
begin
  inherited Create;
  FAppRootPath := AAppRootPath;
  FVenvPath := TPath.Combine(FAppRootPath, VENV_DIR);
  FEngineCorePath := TPath.Combine(FVenvPath, ENGINE_CORE_DIR_NAME);
  FTempPath := TPath.Combine(FVenvPath, CACHE_DIR_NAME, TEMP_SUBDIR_NAME);
  FSetupScriptPath := TPath.Combine(FVenvPath, 'setup.bat');
end;

function TEnvironmentSetup.GetFullPath(const ASubDirConst: string): string;
begin
  Result := TPath.Combine(FEngineCorePath, ASubDirConst);
end;

function TEnvironmentSetup.GetCachePath(const ACacheSubDirConst: string): string;
begin
  Result := TPath.Combine(FVenvPath, CACHE_DIR_NAME, ACacheSubDirConst);
end;

function TEnvironmentSetup.PrepareAndCreateAllScripts(
  const AServerPyContent: string; const APIHost: string;
  const APIPort: Integer): Boolean;
var
  ServerPyContent: string;
  Paths: TArray<string>;
  I: Integer;
begin
  Result := False;
  try
    ServerPyContent := StringReplace(AServerPyContent, '__API_HOST__', APIHost, [rfReplaceAll]);
    ServerPyContent := StringReplace(ServerPyContent, '__API_PORT__', IntToStr(APIPort), [rfReplaceAll]);

    Paths := [
      FVenvPath, FEngineCorePath, FTempPath,
      GetCachePath(HUGGINGFACE_CACHE_DIR_NAME),
      GetCachePath(PIP_CACHE_DIR_NAME),
      GetCachePath(TORCH_CACHE_DIR_NAME),
      GetCachePath(MATPLOTLIB_CACHE_DIR_NAME),
      GetCachePath(UV_CACHE_DIR_NAME)
    ];
    for I := 0 to High(Paths) do
      ForceDirectories(Paths[I]);

    TFile.WriteAllText(TPath.Combine(FEngineCorePath, 'server.py'), ServerPyContent, TEncoding.UTF8);

    GenerateRunEngineScript;
    // REFACTOR: This is now part of GenerateSetupScript
    // GeneratePythonDependenciesInstaller;
    GenerateSetupScript;
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

procedure TEnvironmentSetup.GenerateBatchScriptHeader(const AContent: TStringList; ATitle: string; AIncludeColors: Boolean);
var
  PythonRuntimePath, GitBinPath, GHBinPath: string;
begin
  PythonRuntimePath := GetFullPath(PYTHON_DEP.ExtractTarget);
  GitBinPath := TPath.Combine(GetFullPath(GIT_DEP.ExtractTarget), 'cmd');
  GHBinPath := TPath.Combine(GetFullPath(GH_CLI_DEP.ExtractTarget), 'bin');

  AContent.AddStrings([
    '@echo off',
    'chcp 65001 > nul',
    'pushd "%~dp0"',
    'title ' + ATitle,
    'setlocal enabledelayedexpansion'
  ]);

  if AIncludeColors then
  begin
    AContent.Add('for /f "tokens=1,2 delims= " %%a in (''"prompt $E$S & echo on & for %%b in (1) do rem"'') do set "ESC=%%a"');
    AContent.Add('set "GREEN=%ESC%[92m" & set "CYAN=%ESC%[96m" & set "YELLOW=%ESC%[93m" & set "RED=%ESC%[91m" & set "DIM=%ESC%[2m" & set "RESET=%ESC%[0m"');
  end;

  AContent.AddStrings([
    'set "PYTHON_ROOT=' + PythonRuntimePath + '"',
    'set "PATH=%PYTHON_ROOT%;%PYTHON_ROOT%\Scripts;' + GitBinPath + ';' + GHBinPath + ';%PATH%"',
    'set "HF_HUB_OFFLINE=0"',
    'set "' + ENV_VAR_PYTHONUNBUFFERED + '=1"',
    'set "' + ENV_VAR_HF_HOME + '=' + GetCachePath(HUGGINGFACE_CACHE_DIR_NAME) + '"',
    'set "' + ENV_VAR_PIP_CACHE_DIR + '=' + GetCachePath(PIP_CACHE_DIR_NAME) + '"',
    'set "' + ENV_VAR_UV_CACHE_DIR + '=' + GetCachePath(UV_CACHE_DIR_NAME) + '"',
    'set "' + ENV_VAR_TORCH_HOME + '=' + GetCachePath(TORCH_CACHE_DIR_NAME) + '"',
    'set "' + ENV_VAR_MPLCONFIGDIR + '=' + GetCachePath(MATPLOTLIB_CACHE_DIR_NAME) + '"',
    'set "' + ENV_VAR_TEMP + '=' + FTempPath + '"',
    'set "' + ENV_VAR_TMP + '=' + FTempPath + '"'
  ]);
end;

procedure TEnvironmentSetup.GenerateRunEngineScript;
var
  Content: TStringList;
begin
  Content := TStringList.Create;
  try
    GenerateBatchScriptHeader(Content, 'AGI Kernel', False);
    Content.Add('set "HF_HUB_ENABLE_HF_TRANSFER=0"');
    Content.Add('call "%PYTHON_ROOT%\python.exe" "server.py" %*');
    Content.Add('popd');
    TFile.WriteAllText(TPath.Combine(FEngineCorePath, 'run_engine.bat'), Content.Text);
  finally
    Content.Free;
  end;
end;

procedure TEnvironmentSetup.GenerateSetupScript;
var
  Content: TStringList;
  PythonExePath, PipFlagPath, UVFlagPath: string;
begin
  Content := TStringList.Create;
  try
    PythonExePath := TPath.Combine(GetFullPath(PYTHON_DEP.ExtractTarget), 'python.exe');
    PipFlagPath := TPath.Combine(FEngineCorePath, 'pip_installed.flag');
    UVFlagPath := TPath.Combine(FEngineCorePath, 'uv_installed.flag');

    GenerateBatchScriptHeader(Content, 'AGI Environment Setup', True);

    Content.AddStrings([
      'cls',
      'echo %DIM%                                                                   %RESET%',
      'echo %CYAN%    █████╗  ██████╗   ██╗     ██████╗  ██████╗  ██████╗ ████████╗ %RESET%',
      'echo %CYAN%   ██╔══██╗ ██╔════╝  ██║     ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝ %RESET%',
      'echo %CYAN%   ███████║ ██║  ███╗ ██║     ██████╔╝██║   ██║██║   ██║   ██║    %RESET%',
      'echo %CYAN%   ██╔══██║ ██║   ██║ ██║     ██╔══██╗██║   ██║██║   ██║   ██║    %RESET%',
      'echo %CYAN%   ██║  ██║ ╚██████╔╝ ██╗     ██████╔╝╚██████╔╝╚██████╔╝   ██║    %RESET%',
      'echo %CYAN%   ╚═╝  ╚═╝  ╚═════╝  ╚═╝     ╚═════╝  ╚═════╝  ╚═════╝    ╚═╝    %RESET%',
      'echo %DIM%                                       B O O T S T R A P P E R %RESET%',
      'echo %DIM%                                                                   %RESET% & echo.',
      'set "PYTHON_EXE=' + PythonExePath + '"'
    ]);

    Content.Add('if exist "' + TPath.Combine(FVenvPath, SETUP_COMPLETE_FLAG) + '" (');
    Content.Add('  call :print_progress_ok "Setup flag found. Launching Kernel."');
    Content.Add('  cls');
    Content.Add('  goto :launch_engine');
    Content.Add(')');

    Content.Add('call :print_stage "STAGE 0: SYSTEM ANALYSIS"');
    Content.Add('call :print_progress_ok "Directory structure is nominal." & echo.');

    Content.Add('call :print_stage "STAGE 1: Runtime Core"');
    Content.Add('call :check_dependency "Python Runtime" "' + GetFullPath(PYTHON_DEP.InstallFlag) + '" "call :install_python" || exit /b 1');
    Content.Add('call :check_dependency "Git CLI" "' + GetFullPath(GIT_DEP.InstallFlag) + '" "call :install_git" || exit /b 1');
    Content.Add('call :check_dependency "GitHub CLI" "' + GetFullPath(GH_CLI_DEP.InstallFlag) + '" "call :install_gh_cli" || exit /b 1');

    Content.Add('call :print_stage "STAGE 2: Dependency Managers"');
    Content.Add('call :check_dependency "Pip Base Tools" "' + PipFlagPath + '" "call :install_base_pip" || exit /b 1');
    Content.Add('call :check_dependency "UV Accelerator" "' + UVFlagPath + '" "call :install_uv_accelerator" || exit /b 1');

    Content.Add('call :print_stage "STAGE 3: Python Core Dependencies (Self-Healing)"');
    Content.Add('call :install_python_dependencies || exit /b 1');

    Content.Add('echo OK > "' + TPath.Combine(FVenvPath, SETUP_COMPLETE_FLAG) + '"');
    Content.Add('call :print_progress_ok "Bootstrap complete. Launching AGI Kernel..."');
    Content.Add('cls');

    Content.Add(':launch_engine');
    Content.Add('call "' + TPath.Combine(FEngineCorePath, 'run_engine.bat') + '" %*');
    Content.Add('goto :eof');

    Content.Add(':print_stage');
    Content.Add('echo !CYAN!┌─ %~1 !RESET!');
    Content.Add('goto :eof');

    Content.Add(':print_progress_ok');
    Content.Add('echo   !GREEN![✔ ]!RESET! %~1');
    Content.Add('goto :eof');

    Content.Add(':print_progress_fail');
    Content.Add('echo   !RED![✖ ]!RESET! %~1');
    Content.Add('goto :eof');

    Content.Add(':print_progress');
    Content.Add('echo   !YELLOW!»!RESET! %~1');
    Content.Add('goto :eof');

    Content.Add(':check_dependency');
    Content.Add('call :print_progress "%~1"');
    Content.Add('if exist "%~2" ( call :print_progress_ok "%~1 already installed." ) else ( %~3 )');
    Content.Add('goto :eof');

    Content.Add(':download_file');
    Content.Add('call :print_progress "Downloading %~1..."');
    Content.Add('mkdir "' + TPath.GetDirectoryName('%~3') + '" > nul 2>&1');
    Content.Add('curl -sS -L "%~2" -o "%~3"');
    Content.Add('if errorlevel 1 ( call :print_progress_fail "Download failed for %~1." & if exist "%~3" ( del "%~3" ) & exit /b 1 )');
    Content.Add('call :print_progress_ok "%~1 downloaded."');
    Content.Add('goto :eof');

    Content.Add(':extract_zip');
    Content.Add('call :print_progress "%~1"');
    Content.Add('mkdir "%~3" > nul 2>&1');
    Content.Add('tar -xf "%~2" -C "%~3" %4');
    Content.Add('if errorlevel 1 ( call :print_progress_fail "Extraction failed for %~2." & if exist "%~2" ( del "%~2" ) & exit /b 1 )');
    Content.Add('goto :eof');

    Content.Add(':install_python');
    Content.Add('call :download_file "Python" "' + PYTHON_DEP.URL + '" "' + TPath.Combine(FTempPath, PYTHON_DEP.FileName) + '" || exit /b 1');
    Content.Add('call :extract_zip "Extracting Python..." "' + TPath.Combine(FTempPath, PYTHON_DEP.FileName) + '" "' + GetFullPath(PYTHON_DEP.ExtractTarget) + '" || exit /b 1');
    Content.Add('(echo ' + PYTHON_STDLIB_ZIP + ' & echo . & echo Lib\site-packages & echo import site) > "' + TPath.Combine(GetFullPath(PYTHON_DEP.ExtractTarget), PYTHON_PTH_FILENAME) + '"');
    Content.Add('call :print_progress_ok "Portable Python runtime installed."');
    Content.Add('goto :eof');

    Content.Add(':install_git');
    Content.Add('call :download_file "Git" "' + GIT_DEP.URL + '" "' + TPath.Combine(FTempPath, GIT_DEP.FileName) + '" || exit /b 1');
    Content.Add('call :extract_zip "Extracting Git..." "' + TPath.Combine(FTempPath, GIT_DEP.FileName) + '" "' + GetFullPath(GIT_DEP.ExtractTarget) + '" "--strip-components=1" || exit /b 1');
    Content.Add('call :print_progress_ok "Portable Git installed."');
    Content.Add('goto :eof');

    Content.Add(':install_gh_cli');
    Content.Add('call :download_file "GitHub CLI" "' + GH_CLI_DEP.URL + '" "' + TPath.Combine(FTempPath, GH_CLI_DEP.FileName) + '" || exit /b 1');
    Content.Add('call :extract_zip "Extracting GitHub CLI..." "' + TPath.Combine(FTempPath, GH_CLI_DEP.FileName) + '" "' + GetFullPath(GH_CLI_DEP.ExtractTarget) + '" "--strip-components=1" || exit /b 1');
    Content.Add('call :print_progress_ok "Portable GitHub CLI installed."');
    Content.Add('goto :eof');

    Content.Add(':install_base_pip');
    Content.Add('call :print_progress "Bootstrapping Pip..."');
    Content.Add('echo %CYAN%[CMD]%RESET% Getting pip using !PYTHON_EXE!');
    Content.Add('curl -s -L "' + GET_PIP_URL + '" | "!PYTHON_EXE!" - --no-warn-script-location');
    Content.Add('if errorlevel 1 ( call :print_progress_fail "Failed to bootstrap Pip." & exit /b 1 )');
    Content.Add('echo OK > "' + PipFlagPath + '"');
    Content.Add('call :print_progress_ok "Base Pip installed."');
    Content.Add('goto :eof');

    Content.Add(':install_uv_accelerator');
    Content.Add('call :print_progress "Upgrading Pip/Setuptools..."');
    Content.Add('!PYTHON_EXE! -m pip install --upgrade pip setuptools wheel --quiet || exit /b 1');
    Content.Add('call :print_progress "Installing Download Accelerator (' + PIP_ACCELERATOR + ')..."');
    Content.Add('!PYTHON_EXE! -m pip install ' + PIP_ACCELERATOR + ' || exit /b 1');
    Content.Add('echo OK > "' + UVFlagPath + '"');
    Content.Add('call :print_progress_ok "Accelerator installed."');
    Content.Add('goto :eof');

    Content.Add(':install_python_dependencies');
    Content.Add('call :print_progress "Installing/Updating Core Packages (uvicorn, fastapi, etc.)..."');
    Content.Add('set "PACKAGES=' + CORE_PYTHON_PACKAGES + '"');
    Content.Add('echo %CYAN%[CMD]%RESET% !PYTHON_EXE! -m ' + PIP_ACCELERATOR + ' pip install !PACKAGES! --upgrade');
    Content.Add('!PYTHON_EXE! -m ' + PIP_ACCELERATOR + ' pip install !PACKAGES! --upgrade');
    Content.Add('if errorlevel 1 ( call :print_progress_fail "Core package installation failed." & exit /b 1 )');
    Content.Add('call :print_progress_ok "Core packages updated."');
    Content.Add('echo.');
    Content.Add('call :print_progress "Installing Acceleration Packages (torch, etc.)..."');
    Content.Add('set "PACKAGES=' + ACCELERATION_PACKAGES + '"');
    Content.Add('echo %CYAN%[CMD]%RESET% !PYTHON_EXE! -m ' + PIP_ACCELERATOR + ' pip install !PACKAGES! --upgrade');
    Content.Add('!PYTHON_EXE! -m ' + PIP_ACCELERATOR + ' pip install !PACKAGES! --upgrade');
    Content.Add('if errorlevel 1 ( call :print_progress_fail "Acceleration package installation failed." & exit /b 1 )');
    Content.Add('call :print_progress_ok "Acceleration packages updated."');
    Content.Add('goto :eof');

    Content.Add(':eof');
    Content.Add('endlocal');
    Content.Add('popd');

    TFile.WriteAllText(FSetupScriptPath, Content.Text);
  finally
    Content.Free;
  end;
end;


function TEnvironmentSetup.GetSetupScriptPath: string;
begin
  Result := FSetupScriptPath;
end;

end.
