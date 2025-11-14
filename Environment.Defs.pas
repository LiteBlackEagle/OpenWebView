unit Environment.Defs;

interface

const
  PYTHON_VERSION = '3.11.9';
  PYTHON_VERSION_SHORT = '311';
  CUDA_VERSION = 'cu128';

  GET_PIP_URL = 'https://bootstrap.pypa.io/get-pip.py';

type
  TRuntimeDependency = record
    URL: string;
    FileName: string;
    ExtractTarget: string;
    InstallFlag: string;
  end;

const
  PYTHON_DEP: TRuntimeDependency = (
    URL: 'https://www.python.org/ftp/python/' + PYTHON_VERSION + '/python-' + PYTHON_VERSION + '-embed-amd64.zip';
    FileName: 'python.zip';
    ExtractTarget: 'engine_core\python_runtime';
    InstallFlag: 'engine_core\python_runtime\python.exe'
  );

  GIT_DEP: TRuntimeDependency = (
    URL: 'https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/MinGit-2.45.2-64-bit.zip';
    FileName: 'git.zip';
    ExtractTarget: 'engine_core\git_runtime';
    InstallFlag: 'engine_core\git_runtime\git.exe'
  );

 GH_CLI_DEP: TRuntimeDependency = (
    URL: 'https://github.com/cli/cli/releases/download/v2.80.0/gh_2.80.0_windows_amd64.zip';
    FileName: 'gh_cli.zip';
    ExtractTarget: 'engine_core\gh_cli_runtime';
    InstallFlag: 'engine_core\gh_cli_runtime\gh.exe'
  );

  PYTHON_PTH_FILENAME = 'python' + PYTHON_VERSION_SHORT + '._pth';
  PYTHON_STDLIB_ZIP = 'python' + PYTHON_VERSION_SHORT + '.zip';

  PIP_ACCELERATOR = 'uv';

  DOWNLOAD_ACCELERATOR_PACKAGE = 'hf-transfer';

  CORE_PYTHON_PACKAGES = 'rich tqdm psutil fastapi uvicorn flask virtualenv uv';
  //ACCELERATION_PACKAGES = 'xformers bitsandbytes accelerate ' + DOWNLOAD_ACCELERATOR_PACKAGE;
  ACCELERATION_PACKAGES = 'spaces transformers gradio hf-xet ' + DOWNLOAD_ACCELERATOR_PACKAGE;
  PYTORCH_PACKAGES = 'torch torchvision torchaudio --index-url https://download.pytorch.org/whl/' + CUDA_VERSION;


  VENV_DIR = '.venv';
  ENGINE_CORE_DIR_NAME = 'engine_core';
  PROJECTS_DIR_NAME = 'projects';
  CACHE_DIR_NAME = '.cache';
  TEMP_SUBDIR_NAME = '.temp';


  HUGGINGFACE_CACHE_DIR_NAME = '.huggingface';
  PIP_CACHE_DIR_NAME = '.pip';
  TORCH_CACHE_DIR_NAME = '.torch';
  MATPLOTLIB_CACHE_DIR_NAME = '.matplotlib';
  UV_CACHE_DIR_NAME = '.uv';
  SETUP_COMPLETE_FLAG = '.setup_complete';

  ENV_VAR_HF_HOME = 'HF_HOME';
  ENV_VAR_PIP_CACHE_DIR = 'PIP_CACHE_DIR';
  ENV_VAR_TORCH_HOME = 'TORCH_HOME';
  ENV_VAR_MPLCONFIGDIR = 'MPLCONFIGDIR';
  ENV_VAR_TEMP = 'TEMP';
  ENV_VAR_TMP = 'TMP';
  ENV_VAR_UV_CACHE_DIR = 'UV_CACHE_DIR';
  ENV_VAR_PYTHONUNBUFFERED = 'PYTHONUNBUFFERED';

implementation

end.
