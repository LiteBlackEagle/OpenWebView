unit AI.Engine.Script.Core;

interface

uses
  System.SysUtils;

const
  PYTHON_CORE_TEMPLATE: string =
    '';

implementation

const
  PYTHON_BLOCK_0_HEADER_IMPORTS =
'''
import os, sys, subprocess, json, re, tempfile, uuid, threading, runpy, inspect, shutil, traceback, platform, glob, ast, time, asyncio, logging, textwrap, hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Set, Tuple, Any, Dict

try:
    import uvicorn
    from fastapi import FastAPI, Request
    from contextlib import asynccontextmanager
    from pydantic import BaseModel, Field
    from rich.console import Console
    from rich.panel import Panel
    from rich.markup import escape
    from rich.rule import Rule
    from rich.table import Table
    from rich.syntax import Syntax
    from rich.theme import Theme as RichTheme
    from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn, TimeRemainingColumn
    from rich.status import Status
    from rich.tree import Tree
    from rich.live import Live

except ImportError:
    class MockObject:
        def __init__(self, *args, **kwargs): pass
        def __call__(self, *args, **kwargs): return self
        def __getattr__(self, name): return self
    BaseModel, Field, FastAPI, Request, Console, Panel, Rule, Table, Syntax, RichTheme, Progress, Status, Tree, Live = [MockObject] * 16
    asynccontextmanager = lambda f: f
'''
;


const
  PYTHON_BLOCK_1_CONFIG_THEME_STATE =
'''
class ExecutionPayload(BaseModel):
    code: str
    original_input: Optional[str] = None
    script_dir: Optional[str] = None
    task_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    enable_tracer: bool = False

API_HOST = "__API_HOST__"
API_PORT = int("__API_PORT__")
CUDA_VERSION = 'cu128'
PIP_ACCELERATOR = 'uv'
PROTECTED_PACKAGES_NAMES = {'torch', 'torchvision', 'torchaudio', 'virtualenv', 'pip', 'setuptools', 'wheel'}

class Theme:
    PRIMARY = "#89b4fa"; SECONDARY = "#cba6f7"; SUCCESS = "#a6e3a1"; WARNING = "#f9e2af"
    ERROR = "#f38ba8"; PINK = "#f5c2e7"; TEAL = "#8bd5ca"; PEACH = "#fab387"; MAROON = "#eba0ac"
    SUBTEXT = "#a6adc8"; OVERLAY = "#939ab7"
    PHASE = SECONDARY; INFO = PRIMARY; EXEC = SUBTEXT; DURATION = PEACH
    SECURITY = PINK; HIGHLIGHT = TEAL; DEBUG = MAROON; TRACE = PINK; PROGRESS = TEAL; DOWNLOAD = PEACH

class EnvState:
    NEEDS_INIT = 0; NEEDS_REPAIR = 1; READY = 2
''';

const
  PYTHON_BLOCK_2_LOGGER =
'''
class KernelLogger:
    # =========================================================================
    # ## SỬA LỖI TẠI ĐÂY (PHẦN 1/3) ##
    # Thay đổi __init__ để lưu mốc thời gian bắt đầu của toàn bộ session
    # trong một biến mới là `self.session_start_time`.
    # =========================================================================
    def __init__(self, console: Console):
        self.console = console
        self.session_start_time = time.perf_counter()

    def _format_timedelta(self, td: float) -> str:
        mins, secs = divmod(td, 60)
        return f"{int(mins):02}:{int(secs):02}"

    def _log(self, level: str, message: Any, color: str, is_rule: bool = False):
        # =========================================================================
        # ## SỬA LỖI TẠI ĐÂY (PHẦN 2/3) ##
        # Thay đổi `self.phase_start_time` thành `self.session_start_time`
        # để bộ đếm thời gian tính toán dựa trên mốc toàn cục, không bị reset.
        # =========================================================================
        elapsed_s = time.perf_counter() - self.session_start_time
        elapsed = f"([{Theme.DURATION}]+{self._format_timedelta(elapsed_s)}s[/])"
        tag = f"[bold {color}]{level.upper():<8}[/]"
        if is_rule: self.console.print(Rule(f"{elapsed} [bold {color}]{message}[/]", style=color, align="left"))
        elif level == 'EXEC': self.console.print(f"  [{Theme.EXEC}]> {message}[/]")
        elif level == 'PATH': self.console.print(f"  [bold {Theme.HIGHLIGHT}]{message[0]:<20}[/] [{Theme.SUBTEXT}]{message[1]}[/]")
        elif level == 'TRACE': self.console.print(f"{tag} [bold]{message['func']}[/] [{Theme.OVERLAY}]at {message['file']}:{message['line']}[/]")
        else: self.console.print(f"{elapsed} {tag} {message}")

    def start_phase(self, name: str):
        # =========================================================================
        # ## SỬA LỖI TẠI ĐÂY (PHẦN 3/3) ##
        # Loại bỏ dòng `self.phase_start_time = time.perf_counter()`
        # để mốc thời gian không còn bị reset nữa.
        # =========================================================================
        self._log('PHASE', name, Theme.PHASE, is_rule=True)

    def info(self, m: str): self._log('INFO', m, Theme.INFO)
    def warning(self, m: str): self._log('WARNING', m, Theme.WARNING)
    def security(self, m: str): self._log('SECURITY', m, Theme.SECURITY)
    def exec(self, context: str, message: str): self._log('EXEC', f"[{context}] {message}", Theme.EXEC)
    def progress(self, m: str): self._log('PROGRESS', m, Theme.PROGRESS)
    def download(self, m: str): self._log('DOWNLOAD', m, Theme.DOWNLOAD)
    def install(self, m: str): self._log('INSTALL', m, Theme.SUCCESS)
    def path(self, name: str, path_obj: Path): self._log('PATH', (name, str(path_obj)), None)
    def trace(self, func: str, file: str, line: int): self._log('TRACE', {'func': func, 'file': file, 'line': line}, Theme.TRACE)
    def error(self, m: str, exc_info: bool = False):
        self._log('ERROR', m, Theme.ERROR)
        if exc_info: self.console.print(Panel(escape(traceback.format_exc()), title=f"[bold {Theme.ERROR}]Traceback[/]", border_style=Theme.ERROR))
''';


const
  PYTHON_BLOCK_3_TRACER_DEBUGGER =
'''
class GeniusTracer:
    def __init__(self, project_root: Path, logger: KernelLogger):
        self.project_root = project_root.resolve()
        self.log = logger
        self.original_trace_function = sys.gettrace()
    def _get_short_path(self, path_str: str) -> str:
        try: return str(Path(path_str).relative_to(self.project_root))
        except ValueError: return path_str
    def _trace_function(self, frame, event, arg):
        if event == 'call':
            code = frame.f_code
            filename = code.co_filename
            if str(filename).startswith(str(self.project_root)):
                self.log.trace(code.co_name, self._get_short_path(filename), frame.f_lineno)
        return self._trace_function
    def start(self):
        self.log.console.rule(f"[bold {Theme.SECONDARY}]Genius Tracer Activated[/]", style=Theme.SECONDARY)
        sys.settrace(self._trace_function)
    def stop(self):
        sys.settrace(self.original_trace_function)
        self.log.console.rule(f"[bold {Theme.SECONDARY}]Genius Tracer Deactivated[/]", style=Theme.SECONDARY)
''';

const
  PYTHON_BLOCK_4_POLICY_ENGINE =
'''
class PolicyEngine:
    COMMAND_BLOCKLIST = ['rm', 'del', 'format', 'shutdown', 'taskkill', 'net', 'user', 'group', 'sudo', 'chown', 'chgrp', 'psexec', 'powershell', 'cmd']
    @staticmethod
    def validate_command(command_list: list[str]) -> bool:
        if not command_list: return True
        command_name = Path(command_list[0]).name.lower()
        if command_name in PolicyEngine.COMMAND_BLOCKLIST: return False
        is_pkg_mgr = 'pip' in command_list or 'uv' in command_list
        if not is_pkg_mgr:
            if re.search(r"\\s+(&&|;|\\|)\\s+", " ".join(command_list)): return False
        return True
''';

const
  PYTHON_BLOCK_5_COMMAND_RUNNER =
'''
class CommandRunner:
    def __init__(self, logger: KernelLogger, live_status: 'LiveStatus'):
        self.log = logger
        self.live_status = live_status
        self.ansi_escape_pattern = re.compile(r'\\x1b\\[\\[()#;?]*[0-9]*[ -/]*[@-~]')
    def strip_ansi(self, text: str) -> str:
        return self.ansi_escape_pattern.sub('', text)

    async def execute(self, command: list[str] | str, context_name: str, python_executable: Optional[Path] = None, cwd: Optional[Path] = None, capture_output: bool = False) -> Tuple[bool, str]:
        command_list = command if isinstance(command, list) else command.split()
        if command_list[0] in ['pip', PIP_ACCELERATOR]:
            command_list = [str(python_executable or sys.executable), '-m'] + command_list
        if not PolicyEngine.validate_command(command_list):
            self.log.security(f"Blocking dangerous command: {' '.join(command_list)}")
            return False, "Command blocked by policy"

        self.live_status.pause()

        self.log.console.print(Rule(f"[bold {Theme.HIGHLIGHT}]Running: {context_name}[/]", align="left", style=Theme.HIGHLIGHT))
        self.log.info(f"Command: [bold cyan]{' '.join(command_list)}[/bold cyan]")

        env = os.environ.copy()
        env['PYTHONUNBUFFERED'] = "1"; env['TQDM_MININTERVAL'] = "0.5"

        try:
            if capture_output:
                process = await asyncio.create_subprocess_exec(
                    *command_list, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                    cwd=str(cwd) if cwd else None, env=env
                )
                stdout, stderr = await process.communicate()
                output = stdout.decode('utf-8', errors='replace') + stderr.decode('utf-8', errors='replace')
                if process.returncode != 0:
                    self.log.error(f"Command '{context_name}' failed with exit code {process.returncode}.")
                    return False, output
                self.log.info(f"[bold {Theme.SUCCESS}]'{context_name}' completed successfully.[/]")
                return True, output
            else:
                process = await asyncio.create_subprocess_exec(
                    *command_list, stdout=sys.stdout, stderr=sys.stderr,
                    cwd=str(cwd) if cwd else None, env=env
                )
                return_code = await process.wait()
                self.log.console.print()
                if return_code != 0:
                    self.log.error(f"Command '{context_name}' failed with exit code {return_code}.")
                    return False, ""
                self.log.info(f"[bold {Theme.SUCCESS}]'{context_name}' completed successfully.[/]")
                return True, ""
        except Exception as e:
            self.log.error(f"Unexpected error in CommandRunner: {e}", exc_info=True)
            return False, str(e)
        finally:
            self.live_status.resume()
'''
;



const
  PYTHON_BLOCK_6_PACKAGE_MANAGER =
'''
class PackageManager:
    IMPORT_TO_PACKAGE_MAP = {
        'cv2': 'opencv-python', 'skimage': 'scikit-image', 'sklearn': 'scikit-learn', 'PIL': 'Pillow', 'yaml': 'PyYAML',
        'sfast': 'git+https://github.com/chengzeyi/sfast.git@main',
        'gradio_promptweighting': 'gradio-prompt-weighting-spt',
        'safety_checker': 'deep-safety-checker', 'stable_fast': 'stable-fast'
    }

    def __init__(self, runner: CommandRunner, logger: KernelLogger, console: Console):
        self.runner = runner; self.log = logger; self.console = console; self.installed_cache: Optional[Set[str]] = None

    def _normalize(self, name: str) -> str: return name.lower().replace('_', '-')

    @staticmethod
    def _get_git_pkg_flag_name(git_url: str) -> str:
        return f".git_pkg_{hashlib.sha1(git_url.encode('utf-8')).hexdigest()[:12]}.flag"

    async def _get_installed(self, python_exe: Path) -> Set[str]:
        if self.installed_cache is not None: return self.installed_cache
        try:
            success, output = await self.runner.execute([str(python_exe), '-m', 'pip', 'list'], "Get Installed", capture_output=True)
            if success:
                self.installed_cache = {self._normalize(line.split()[0]) for line in output.splitlines()[2:]}
                return self.installed_cache
        except Exception: pass
        return set()

    async def get_missing(self, python_exe: Path, required: List[str]) -> List[str]:
        installed_pypi = await self._get_installed(python_exe)
        site_packages_path = python_exe.parent.parent / "Lib" / "site-packages"
        missing = []
        for req in required:
            if req.startswith('git+'):
                flag_name = self._get_git_pkg_flag_name(req)
                if not (site_packages_path / flag_name).exists():
                    missing.append(req)
            else:
                pkg_name = self._normalize(re.split(r'[=<>!~]', req)[0].strip())
                if pkg_name not in installed_pypi:
                    missing.append(req)
        return list(set(missing))

    def resolve_requirements(self, context_dir: Path, script_file: Optional[Path]) -> List[str]:
        self.log.info("Scanning project for Python imports and requirements...")
        reqs: Set[str] = set()
        PLATFORM_BLOCKLIST = {'nvidia-nccl-cu12', 'nvidia-tensorrt', 'tensorrt', 'triton'}
        for req_file in context_dir.glob('**/requirements*.txt'):
            filename_lower = req_file.name.lower()
            if any(keyword in filename_lower for keyword in ['docker', 'linux', 'dev', 'test']): continue
            try:
                with open(req_file, 'r', encoding='utf-8') as f: reqs.update(line.strip() for line in f if line.strip() and not line.startswith('#'))
            except Exception: pass

        project_imports: Set[str] = set()
        EXCLUDED_SCAN_DIRS_NAMES = {'.agi_venv', 'venv', '.venv', '__pycache__', 'site-packages', 'Scripts', 'Lib'}

        self.log.info("Building a map of local project modules to avoid external installation...")
        project_modules: Set[str] = set()
        py_files_to_scan: List[Path] = []
        all_paths = list(context_dir.glob('**/*'))
        for path in all_paths:
            if any(part in EXCLUDED_SCAN_DIRS_NAMES for part in path.relative_to(context_dir).parts):
                continue
            if path.is_dir():
                project_modules.add(path.name)
            elif path.is_file() and path.suffix == '.py':
                py_files_to_scan.append(path)
                if path.name != '__init__.py':
                    project_modules.add(path.stem)

        self.log.info(f"Identified {len(project_modules)} potential local modules (e.g., mmgp, shared).")

        stdlib_names = sys.stdlib_module_names if hasattr(sys, 'stdlib_module_names') else set()
        for py_file in py_files_to_scan:
            try:
                code = py_file.read_text('utf-8', errors='ignore')
                for node in ast.walk(ast.parse(code)):
                    module_name = None
                    if isinstance(node, ast.Import):
                        for alias in node.names: module_name = alias.name.split('.')[0]
                    elif isinstance(node, ast.ImportFrom) and node.module: module_name = node.module.split('.')[0]
                    if module_name and not module_name.startswith('_') and module_name not in stdlib_names and module_name not in project_modules:
                        project_imports.add(module_name)
            except Exception: pass

        for imp in project_imports: reqs.add(self.IMPORT_TO_PACKAGE_MAP.get(imp, imp))

        final_reqs_list = [req for req in reqs if (norm_req := self._normalize(re.split(r'[=<>!~ +]', req)[0].strip())) and norm_req not in PROTECTED_PACKAGES_NAMES and norm_req not in PLATFORM_BLOCKLIST]
        if final_reqs_list:
            self.log.info(f"Resolved {len(final_reqs_list)} unique external dependencies to install.")
            self.log.console.print(f"  [dim]Dependencies: {', '.join(sorted(final_reqs_list))}[/dim]")
        else:
            self.log.info("No new external dependencies identified.")
        return final_reqs_list

    async def provision(self, python_exe: Path, reqs: List[str], context_dir: Path, upgrade: bool = False, name: str = "Install Project Deps", extra_index_url: Optional[str] = None) -> Tuple[bool, str]:
        if not reqs: return True, "No packages to install."
        site_packages_path = python_exe.parent.parent / "Lib" / "site-packages"

        git_reqs = [r for r in reqs if r.startswith('git+')]
        special_reqs = [r for r in reqs if ' ' in r and not r.startswith('git+')]
        normal_reqs = [r for r in reqs if not r.startswith('git+') and ' ' not in r]
        overall_success = True
        base_cmd = [PIP_ACCELERATOR, 'pip', 'install', '--no-cache']

        if extra_index_url:
            base_cmd.extend(['--extra-index-url', extra_index_url])

        async def install_batch(packages: List[str], description: str, is_individual: bool = False):
            nonlocal overall_success
            if not packages: return

            if is_individual:
                for pkg in packages:
                    cmd = base_cmd[:]
                    if upgrade: cmd.append('--upgrade')
                    cmd.extend(pkg.split())
                    success, _ = await self.runner.execute(cmd, f"Install: {pkg}", python_executable=python_exe, cwd=context_dir)
                    if success:
                        if pkg.startswith('git+'):
                            flag_name = self._get_git_pkg_flag_name(pkg)
                            (site_packages_path / flag_name).touch()
                    else:
                        overall_success = False
            else:
                cmd = base_cmd[:]
                if upgrade: cmd.append('--upgrade')
                cmd.extend(packages)
                success, _ = await self.runner.execute(cmd, f"Install {description} Batch", python_executable=python_exe, cwd=context_dir)
                if not success: overall_success = False

        await install_batch(normal_reqs, "standard")
        await install_batch(git_reqs, "git-based", is_individual=True)
        await install_batch(special_reqs, "special-flag", is_individual=True)

        self.installed_cache = None
        if overall_success:
            msg = "Dependency provisioning completed."
            self.log.info(msg)
            return True, msg
        else:
            msg = "Dependency provisioning completed with errors."
            self.log.warning(msg)
            return False, msg

    async def log_installed_packages(self, python_exe: Path, context_dir: Path):
        self.log.info("Generating final environment snapshot...")
        try:
            success, output = await self.runner.execute([str(python_exe), '-m', 'pip', 'list', '--format', 'json'], "List Packages", capture_output=True, cwd=context_dir)
            if not success:
                self.log.warning(f"Could not list packages: {output}")
                return
            packages_data = json.loads(output)
            if not packages_data: return
            packages_data.sort(key=lambda p: p['name'].lower())
            terminal_width = self.console.width
            max_name_len = max(len(p['name']) for p in packages_data) if packages_data else 20
            column_width = max_name_len + 10 + 4
            num_columns = max(1, terminal_width // column_width)
            table = Table(box=None, show_header=False, pad_edge=False)
            for _ in range(num_columns):
                table.add_column("Package", style=Theme.PRIMARY, no_wrap=True)
                table.add_column("Version", style=Theme.SUBTEXT, no_wrap=True)
            num_rows = (len(packages_data) + num_columns - 1) // num_columns
            for row_index in range(num_rows):
                row_items = []
                for col_index in range(num_columns):
                    pkg_index = row_index + col_index * num_rows
                    if pkg_index < len(packages_data):
                        pkg = packages_data[pkg_index]
                        row_items.extend([pkg['name'], pkg['version']])
                    else:
                        row_items.extend(["", ""])
                table.add_row(*row_items)
            self.console.print(Panel(table, title=f"[bold {Theme.HIGHLIGHT}]Final Environment ({len(packages_data)} packages)[/]", border_style=Theme.HIGHLIGHT))
        except Exception as e:
            self.log.warning(f"Could not generate environment snapshot: {e}", exc_info=True)
'''
;

const
  PYTHON_BLOCK_7_VENV_MANAGER =
'''
class VenvManager:
    INTEGRITY_STAMP = ".agi_integrity_v95.ok"

    CORE_PACKAGES_TO_INSTALL = [
        'virtualenv', 'rich', 'tqdm', 'safetensors', 'accelerate', 'transformers==4.45.2', 'diffusers',
        'hf-xet', 'huggingface-hub', 'packaging', 'xformers', 'bitsandbytes', 'PEFT', 'ninja', 'spaces',
        'gradio', 'Pillow'
    ]
    # FIX: Buộc PyTorch về phiên bản 2.8.0. Loại bỏ --upgrade ở Stage 1 để đảm bảo tính chính xác
    PYTORCH_TORCH_INSTALL = f'torch==2.8.0 --index-url https://download.pytorch.org/whl/{CUDA_VERSION}'
    # Aux packages không cố định version, để chúng tự động tìm phiên bản mới nhất tương thích với 2.8.0
    PYTORCH_AUX_INSTALL = 'torchvision torchaudio'


    def __init__(self, runner: CommandRunner, pkg_manager: PackageManager, logger: KernelLogger):
        self.runner = runner; self.pkg_manager = pkg_manager; self.log = logger

    @staticmethod
    def get_py_exe(env_path: Path) -> Path:
        return env_path / ("Scripts" if platform.system() == "Windows" else "bin") / "python.exe"

    @staticmethod
    def _get_core_packages_hash() -> str:
        all_packages = sorted(VenvManager.CORE_PACKAGES_TO_INSTALL + [VenvManager.PYTORCH_TORCH_INSTALL, VenvManager.PYTORCH_AUX_INSTALL])
        package_string = "".join(all_packages).encode('utf-8')
        return hashlib.sha1(package_string).hexdigest()

    def invalidate_stamp(self, env_path: Path):
        stamp_file = env_path / self.INTEGRITY_STAMP
        if stamp_file.exists():
            self.log.warning("Core integrity stamp invalidated."); stamp_file.unlink()

        project_deps_stamp = env_path / ".agi_project_deps.ok"
        if project_deps_stamp.exists():
            project_deps_stamp.unlink()

    async def check_integrity(self, env_path: Path) -> Tuple[int, Optional[Path]]:
        py_exe = self.get_py_exe(env_path)
        stamp_file = env_path / self.INTEGRITY_STAMP
        if not py_exe.exists(): return EnvState.NEEDS_INIT, None
        if stamp_file.exists():
            try:
                stamp_hash = stamp_file.read_text().strip()
                current_hash = self._get_core_packages_hash()
                if stamp_hash == current_hash:
                    self.log.info(f"Core integrity stamp is valid. Environment assumed [bold {Theme.SUCCESS}]READY[/].")
                    return EnvState.READY, py_exe
                else:
                    self.log.warning("Core package definition has changed. Environment requires repair.")
                    self.invalidate_stamp(env_path)
                    return EnvState.NEEDS_REPAIR, py_exe
            except Exception:
                self.log.warning("Could not read integrity stamp. Assuming repair is needed.")
                self.invalidate_stamp(env_path)
                return EnvState.NEEDS_REPAIR, py_exe
        self.log.warning("No integrity stamp found. Environment requires full check/provisioning.")
        return EnvState.NEEDS_REPAIR, py_exe

    async def provision(self, env_path: Path, needs_init: bool) -> Tuple[bool, Optional[Path]]:
        self.invalidate_stamp(env_path)
        if needs_init:
            if env_path.exists(): shutil.rmtree(env_path, ignore_errors=True)
            success, _ = await self.runner.execute([sys.executable, '-m', 'virtualenv', str(env_path)], "Create Virtualenv")
            if not success: return False, None
        py_exe = self.get_py_exe(env_path)
        self.log.start_phase("Provisioning Core Environment")
        self.pkg_manager.installed_cache = None
        bootstrap_cmd = ['pip', 'install', '--upgrade', 'pip', PIP_ACCELERATOR]
        success, _ = await self.runner.execute(bootstrap_cmd, f"Bootstrap {PIP_ACCELERATOR}", python_executable=py_exe)
        if not success:
            self.log.error(f"FATAL: Bootstrap of {PIP_ACCELERATOR} failed. Cannot proceed.")
            return False, None

        # STAGE 1: Cài đặt torch core (buộc version, không upgrade để duy trì tính chính xác)
        self.log.info(f"Installing CRITICAL Acceleration Packages (PyTorch {CUDA_VERSION}, Stage 1/3: Torch core)...")
        torch_success, _ = await self.pkg_manager.provision(py_exe, [self.PYTORCH_TORCH_INSTALL], env_path, upgrade=False, name=f"Install Torch Core")
        if not torch_success:
             self.log.error(f"FATAL: Critical Torch core installation failed.")
             self.invalidate_stamp(env_path)
             return False, py_exe

        # STAGE 2: Cài đặt torchvision và torchaudio (không cố định version, không upgrade)
        # Vì torch đã được cài, uv sẽ tự động tìm version mới nhất tương thích với torch==2.8.0
        self.log.info(f"Installing CRITICAL Acceleration Packages (PyTorch {CUDA_VERSION}, Stage 2/3: Aux packages)...")
        aux_success, _ = await self.pkg_manager.provision(py_exe, [self.PYTORCH_AUX_INSTALL], env_path, upgrade=False, name=f"Install Torch Aux")
        if not aux_success:
             self.log.error(f"FATAL: Critical torchvision/torchaudio installation failed.")
             self.invalidate_stamp(env_path)
             return False, py_exe


        self.log.info("Installing remaining API Core Packages (Stage 3/3)...")

        GPU_CORE_PACKAGES = {'torch', 'torchvision', 'torchaudio'}
        filtered_core_deps = [
            pkg_spec for pkg_spec in self.CORE_PACKAGES_TO_INSTALL
            if re.split(r'[=<>!~]', pkg_spec)[0].strip().lower() not in GPU_CORE_PACKAGES
        ]

        PYTORCH_INDEX_URL = f'https://download.pytorch.org/whl/{CUDA_VERSION}'

        # Sử dụng upgrade=False và extra_index_url để ngăn chặn tải xuống CPU và xung đột.
        core_success, _ = await self.pkg_manager.provision(
            py_exe,
            filtered_core_deps,
            env_path,
            upgrade=False,
            name="Install Other Core Packages (Stage 3)",
            extra_index_url=PYTORCH_INDEX_URL
        )

        if not core_success:
            self.log.error("FATAL: Core package provisioning failed. The environment may be unstable.")
            self.invalidate_stamp(env_path)
            return False, py_exe

        self.log.info("Core provisioning finished successfully. Creating integrity stamp with new hash.")
        current_hash = self._get_core_packages_hash()
        (env_path / self.INTEGRITY_STAMP).write_text(current_hash)
        return True, py_exe
'''
;


const
  PYTHON_BLOCK_8_WORKSPACE_AND_PATCHER =
'''
class DirectoryTreeLogger:
    @staticmethod
    def log_tree(root_path: Path, console: Console, logger: KernelLogger):
        logger.info("Project Structure Scan (Root Files/Folders):")
        rich_tree = Tree(f"[bold {Theme.HIGHLIGHT}]{root_path.name}/[/bold {Theme.HIGHLIGHT}]", guide_style=Theme.SUBTEXT)
        EXCLUDED_DIRS = ['venv', '.venv', '.agi_venv', 'cache', 'site-packages', 'loras']
        EXCLUDED_FILES = ['.gitignore', '.setup_complete', 'clarity_patcher.py', 'requirements.txt', 'readme.md', 'license.txt']
        try:
            contents = sorted([p for p in root_path.iterdir() if not p.name.startswith('.')])
        except Exception:
            return
        for item in contents:
            name_lower = item.name.lower()
            if name_lower in EXCLUDED_FILES or any(name_lower.endswith(e) for e in EXCLUDED_FILES): continue
            if item.is_dir():
                if name_lower in [d.lower() for d in EXCLUDED_DIRS]:
                    rich_tree.add(f"[dim]{item.name}/ (Aux)[/dim]")
                else:
                    rich_tree.add(f"[bold {Theme.HIGHLIGHT}]{item.name}/[/bold {Theme.HIGHLIGHT}]")
            else:
                rich_tree.add(f"{item.name}")
        console.print(rich_tree)
'''
;

const
  PYTHON_BLOCK_8a_LIVE_STATUS =
'''
class LiveStatus:
    def __init__(self, console: Console):
        self.console = console
        self._live: Optional[Live] = None
        self._current_message: str = "Initializing..."
        self._start_time: float = time.perf_counter()
        self._is_active: bool = False

    def _format_elapsed_time(self) -> str:
        elapsed = time.perf_counter() - self._start_time
        hours, rem = divmod(elapsed, 3600)
        minutes, seconds = divmod(rem, 60)
        return f"+{int(hours):02}:{int(minutes):02}:{seconds:06.3f}s"

    def _create_renderable(self) -> Panel:
        timer_str = self._format_elapsed_time()
        return Panel(
            f"[bold][magenta]Status[/]: {self._current_message} ([{Theme.DURATION}]{timer_str}[/])...[/]",
            border_style=Theme.OVERLAY,
            padding=(0, 1)
        )

    def start(self, initial_message: str):
        if self._is_active: return
        self.console.print()
        self._current_message = initial_message
        # =========================================================================
        # ## SỬA LỖI TẠI ĐÂY ##
        # Thay đổi `transient=True` thành `transient=False` để giữ lại
        # dòng trạng thái cuối cùng trên màn hình sau khi tác vụ hoàn tất.
        # =========================================================================
        self._live = Live(self._create_renderable(), console=self.console, refresh_per_second=10, transient=False)
        self._live.start()
        self._is_active = True

    def stop(self):
        if not self._is_active: return
        self._live.stop()
        # Không cần in thêm gì ở đây, vì trạng thái cuối cùng đã được giữ lại.
        # self.console.print(f"[dim]Status display stopped.[/]")
        self._is_active = False

    def update(self, message: str):
        if not self._is_active: return
        self._current_message = message
        self._live.update(self._create_renderable())

    def pause(self):
        if not self._is_active: return
        self._live.stop()
        self._is_active = False

    def resume(self):
        self.start(self._current_message)
'''
;




const
  PYTHON_BLOCK_9_SESSION_HANDLER =
'''
class PythonSession:
    EXCLUDED_SCAN_DIRS_NAMES = {'.agi_venv', 'venv', '.venv', '__pycache__'}

    def __init__(self, task: ExecutionPayload, logger: KernelLogger, console: Console):
        self.task = task; self.log = logger; self.console = console
        self.live_status = LiveStatus(console)
        self.runner = CommandRunner(logger, self.live_status)
        self.pkg_manager = PackageManager(self.runner, logger, console)
        self.venv_manager = VenvManager(self.runner, self.pkg_manager, logger)
        self.engine_core_path = Path(os.path.abspath(__file__)).parent
        self.venv_path = self.engine_core_path.parent
        self.projects_path = self.venv_path / "projects"

    def _classify_input(self, inp: str) -> str:
        stripped_input = inp.strip()
        if Path(stripped_input).exists() and Path(stripped_input).is_absolute():
            if Path(stripped_input).is_file() and stripped_input.lower().endswith('.py'): return 'filepath'
            if Path(stripped_input).is_dir(): return 'dirpath'
        if stripped_input.startswith('git clone ') or stripped_input.endswith('.git') or stripped_input.startswith('git@'): return 'clone'
        if len(stripped_input.splitlines()) > 1 or any(c in stripped_input for c in ['&&', 'cd ', 'pip install']):
             return 'script'
        try:
            ast.parse(stripped_input)
            return 'code'
        except (SyntaxError, TypeError):
            return 'script'

    def _find_entry_point(self, directory: Path) -> Optional[Path]:
        self.log.info(f"Initiating Genius Scan in [cyan]{directory}[/cyan]...")

        candidates = [
            f for f in directory.iterdir()
            if f.is_file() and f.suffix == '.py' and f.name not in ['setup.py', '__init__.py']
        ]

        if not candidates:
            self.log.warning("No potential Python entry point files found in the root directory.")
            return None

        if len(candidates) == 1:
            entry_point = candidates[0]
            self.log.info(f"Genius Scan HIT (Lone Wolf): Found single candidate [bold green]{entry_point.name}[/].")
            return entry_point

        scores = {}
        DEFAULT_ENTRY_FILES = ['main.py', 'app.py', 'run.py', 'launch.py', 'start.py', 'webui.py']

        self.log.info("Multiple candidates found. Scoring based on name and content...")

        table = Table(title="Entry Point Scoring", show_header=True, header_style="bold magenta")
        table.add_column("File Name", style="cyan")
        table.add_column("Name Score", justify="right")
        table.add_column("Content Score", justify="right")
        table.add_column("Total Score", justify="right", style="bold")

        for f_path in candidates:
            name_score = 0
            content_score = 0

            if f_path.name.lower() in DEFAULT_ENTRY_FILES:
                name_score = 100

            try:
                content = f_path.read_text(encoding='utf-8', errors='ignore')
                if 'if __name__ == "__main__":' in content or "if __name__ == '__main__':" in content:
                    content_score = 200
            except Exception:
                pass

            total_score = name_score + content_score
            scores[f_path] = total_score
            table.add_row(f_path.name, str(name_score), str(content_score), str(total_score))

        self.console.print(table)

        if not scores or max(scores.values()) == 0:
             self.log.warning("Scoring complete, but no clear entry point identified (all scores are zero).")
             return None

        best_candidate = max(scores, key=scores.get)
        self.log.info(f"Genius Scan HIT (Scoring): Best candidate is [bold green]{best_candidate.name}[/] with a score of {scores[best_candidate]}.")
        return best_candidate

    def _log_source(self, script_file: Path, is_temp: bool):
        try:
            code = script_file.read_text(encoding='utf-8', errors='ignore')
            title = "Ephemeral Script" if is_temp else f"Entry Point: {script_file.name}"
            syntax = Syntax(code, "python", theme="monokai", line_numbers=True, word_wrap=False)
            self.console.print(Panel(syntax, title=f"[bold {Theme.DEBUG}]Source Code: {title}[/]", border_style=Theme.DEBUG))
        except Exception as e: self.log.warning(f"Could not display source code: {e}")

    def _cleanup_caches(self, ctx_dir: Path):
        self.log.start_phase("Cleaning Up Caches")
        cache_dirs_to_clean = [ ctx_dir / ".temp", ctx_dir / ".cache" ]
        for cache_dir in cache_dirs_to_clean:
            if cache_dir.is_dir():
                self.log.info(f"Cleaning contents of [cyan]{cache_dir}[/]")
                shutil.rmtree(cache_dir, ignore_errors=True)
        self.log.info("Cache cleanup complete.")

    def _get_unified_deps_hash(self, ctx_dir: Path) -> str:
        hasher = hashlib.sha1()

        req_files = sorted(list(ctx_dir.glob('**/requirements*.txt')))
        for req_file in req_files:
            try: hasher.update(req_file.read_bytes())
            except Exception: pass

        py_files = [
            p for p in ctx_dir.glob('**/*.py')
            if not any(part in self.EXCLUDED_SCAN_DIRS_NAMES for part in p.relative_to(ctx_dir).parts)
            and not p.name.startswith('temp_script_')
            and not p.name.startswith('launch_script_')
        ]

        for py_file in sorted(py_files):
            try:
                hasher.update(py_file.read_bytes())
            except Exception: pass

        core_hash = self.venv_manager._get_core_packages_hash()
        hasher.update(core_hash.encode('utf-8'))

        return hasher.hexdigest()

    def _sanitize_python_code(self, code: str) -> str:
        windows_path_pattern = re.compile(r"""(r?['"])([a-zA-Z]:\\)([^'"]*?)(['"])""")
        def replacer(match):
            prefix, drive, rest, quote = match.groups()
            if 'r' in prefix or '\\\\' in rest: return match.group(0)
            sanitized_rest = rest.replace('\\', '\\\\')
            return f"{prefix}{drive}{sanitized_rest}{quote}"
        sanitized_lines = [windows_path_pattern.sub(replacer, line) for line in code.splitlines()]
        return "\n".join(sanitized_lines)

    async def _prepare_workspace(self, inp: str, inp_type: str) -> Tuple[Path, Optional[Path]]:
        if inp_type == 'filepath':
            script_file = Path(inp).resolve()
            return script_file.parent, script_file
        if inp_type == 'dirpath':
            return Path(inp).resolve(), None
        self.projects_path.mkdir(parents=True, exist_ok=True)
        if inp_type == 'clone':
            repo_url = inp.split()[-1]
            repo_name = repo_url.split('/')[-1].replace('.git', '')
            ctx_dir = self.projects_path / repo_name
            if not ctx_dir.exists():
                clone_cmd = ['git', 'clone', '--depth', '1', repo_url, str(ctx_dir)]
                if not (await self.runner.execute(clone_cmd, "Git Clone", cwd=self.projects_path))[0]:
                    raise Exception("Git clone failed")
            return ctx_dir, None
        ctx_dir = self.projects_path / "test"
        ctx_dir.mkdir(parents=True, exist_ok=True)
        python_code = inp
        if inp_type == 'script':
            for line in inp.splitlines():
                cmd = line.strip()
                if not (cmd.startswith('git ') or cmd.startswith('cd ') or cmd.startswith('pip ')): continue
                await self.runner.execute(cmd.split(), "Setup Command", cwd=ctx_dir)
            python_code_lines = [line for line in inp.splitlines() if not (line.strip().startswith('git ') or line.strip().startswith('cd ') or line.strip().startswith('pip '))]
            python_code = "\n".join(python_code_lines)
        if not python_code.strip():
            return ctx_dir, None

        sanitized_code = self._sanitize_python_code(python_code)
        temp_file = ctx_dir / f"temp_script_{uuid.uuid4().hex[:8]}.py"
        temp_file.write_text(sanitized_code, encoding='utf-8')
        return ctx_dir, temp_file

    async def run(self) -> bool:
        self.live_status.start("Initializing session")
        initial_cwd = Path.cwd()
        ctx_dir: Optional[Path] = None
        temp_code_file: Optional[Path] = None
        try:
            inp = (self.task.original_input or self.task.code).strip()
            inp_type = self._classify_input(inp)
            self.live_status.update("Preparing workspace")
            self.log.start_phase("Workspace Preparation")
            self.log.info(f"Input classified as [bold magenta]{inp_type.upper()}[/].")

            if inp_type == 'filepath':
                script_file = Path(inp)
                ctx_dir = script_file.parent
                os.chdir(ctx_dir)
            else:
                ctx_dir, script_file = await self._prepare_workspace(inp, inp_type)
                os.chdir(ctx_dir)

            if script_file and "temp_script" in script_file.name:
                temp_code_file = script_file

            self.log.path("Final Context Dir", ctx_dir)

            self.live_status.update("Provisioning environment")
            self.log.start_phase("Environment Provisioning")
            env_path = ctx_dir / ".agi_venv"
            self.log.path("Venv Path", env_path)
            state, py_exe = await self.venv_manager.check_integrity(env_path)
            if state != EnvState.READY:
                success, py_exe_new = await self.venv_manager.provision(env_path, needs_init=(state == EnvState.NEEDS_INIT))
                if not success or not py_exe_new: return False
                py_exe = py_exe_new
                (env_path / ".agi_project_deps.ok").unlink(missing_ok=True)

            self.live_status.update("Resolving dependencies")
            self.log.start_phase("Dependency Resolution")
            deps_stamp_file = env_path / ".agi_project_deps.ok"
            current_deps_hash = self._get_unified_deps_hash(ctx_dir)
            skip_all_dep_checks = False
            did_install_packages = False
            if deps_stamp_file.exists():
                try:
                    if deps_stamp_file.read_text().strip() == current_deps_hash:
                        self.log.info("Unified dependency fingerprint is valid. Skipping all checks.")
                        skip_all_dep_checks = True
                except Exception: pass
            if not skip_all_dep_checks:
                self.log.info("Fingerprint invalid or missing. Running full dependency resolution...")
                reqs = self.pkg_manager.resolve_requirements(ctx_dir, script_file)
                if inp_type == 'script':
                    reqs.extend(p for line in inp.splitlines() if 'pip install' in line for p in line.split('pip install')[1].strip().split() if not p.startswith('-'))
                missing = await self.pkg_manager.get_missing(py_exe, list(set(reqs)))
                if missing:
                    did_install_packages = True
                    self.live_status.update(f"Installing {len(missing)} dependencies")
                    self.log.info(f"Found {len(missing)} missing project dependencies to install.")
                    await self.pkg_manager.provision(py_exe, missing, ctx_dir)
                else:
                    self.log.info("All project dependencies are already installed.")
                deps_stamp_file.write_text(current_deps_hash)

            self.live_status.update("Preparing for execution")
            self.log.start_phase("Execution")
            entry_point = script_file or self._find_entry_point(ctx_dir)
            DirectoryTreeLogger.log_tree(ctx_dir, self.console, self.log)
            if did_install_packages:
                await self.pkg_manager.log_installed_packages(py_exe, ctx_dir)
            if not entry_point:
                self.log.info(f"[{Theme.SUCCESS}]Setup complete. No entry point found.[/]");
                self.live_status.update("Setup complete, no entry point")
                return True
            self.log.path("Executing Entry Point", entry_point)
            self._log_source(entry_point, is_temp=(temp_code_file is not None))

            # Simplified, direct command execution
            cmd = [str(py_exe), str(entry_point)]

            os.environ['GRADIO_ALLOWED_PATHS'] = f"{str(ctx_dir.resolve())}{os.pathsep}{str(Path(tempfile.gettempdir()).resolve())}"
            self.live_status.update(f"Running entry point: {entry_point.name}")
            execution_success, _ = await self.runner.execute(cmd, f"{entry_point.name}", cwd=ctx_dir)
            self.live_status.update("Execution finished")
            return execution_success
        except Exception as e:
            self.log.error(f"Session failed: {e}", exc_info=True)
            self.live_status.update("Session failed with an error")
            return False
        finally:
            self.live_status.stop()
            if ctx_dir: self._cleanup_caches(ctx_dir)
            os.chdir(initial_cwd)
            if temp_code_file and temp_code_file.exists(): temp_code_file.unlink(missing_ok=True)
'''
;



const
  PYTHON_BLOCK_10_API_SERVER_AND_MAIN =
'''
async def _run_sandbox_session(task_file: str):
    console = Console(force_terminal=True, no_color=False, record=True)
    logger = KernelLogger(console)
    try:
        with open(task_file, 'r', encoding='utf-8') as f: task = ExecutionPayload(**json.load(f))
        logger.console.print(Rule(f"[bold {Theme.INFO}]Starting Sandbox Session[/]", style=Theme.INFO))
        logger.info(f"Dispatching task to Python session handler.")
        session = PythonSession(task, logger, console)
        success = await session.run()
        color = Theme.SUCCESS if success else Theme.ERROR
        status = "finished successfully" if success else "failed"
        logger.console.print(Rule(f"[bold {color}]Sandbox for task {task.task_id} {status}.[/]", style=color))
        sys.exit(0 if success else 1)
    except Exception:
        logger.error("Fatal error in sandbox initialization", exc_info=True); sys.exit(3)

async def worker(queue: asyncio.Queue, logger: KernelLogger):
    while True:
        task = await queue.get()
        temp_file = Path(tempfile.gettempdir()) / f'agi_task_{task.task_id}.json'
        try:
            with open(temp_file, 'w', encoding='utf-8') as f: f.write(task.model_dump_json())
            logger.console.print(Rule(f"[bold {Theme.INFO}]Starting sandbox for task: {task.task_id}[/]", style=Theme.INFO))
            env = os.environ.copy(); env.update({'PYTHONUTF8': '1', 'UV_NO_CACHE': '1'})
            proc = await asyncio.create_subprocess_exec(
                sys.executable, os.path.abspath(__file__), '--sandbox_mode', '--task_file', str(temp_file),
                stdout=sys.stdout, stderr=sys.stderr, env=env
            )
            await proc.wait()
            color = Theme.SUCCESS if proc.returncode == 0 else Theme.ERROR
            status = "finished successfully" if proc.returncode == 0 else f"failed with code {proc.returncode}"
            logger.console.print(Rule(f"[bold {color}]Sandbox for task {task.task_id} {status}.[/]", style=color))
        finally:
            temp_file.unlink(missing_ok=True); queue.task_done()

@asynccontextmanager
async def lifespan(app: FastAPI):
    console = Console(force_terminal=True, record=True, theme=RichTheme({"info": Theme.INFO, "warning": Theme.WARNING, "error": Theme.ERROR, "success": Theme.SUCCESS, "highlight": Theme.HIGHLIGHT, "debug": Theme.DEBUG}))
    logger = KernelLogger(console)
    task_queue = asyncio.Queue()
    logger.start_phase("AGI Core v92.4 'Phoenix' Initializing")
    asyncio.create_task(worker(task_queue, logger))
    logger.start_phase(f"API Ready on http://{API_HOST}:{API_PORT}")
    yield {"task_queue": task_queue, "logger": logger}
    logger.info("Server shutting down.")

def main():
    app = FastAPI(lifespan=lifespan)
    @app.post("/execute")
    async def execute_code(payload: ExecutionPayload, request: Request):
        state = request.state._state
        task_queue = state["task_queue"]
        await task_queue.put(payload)
        return {"status": "queued", "task_id": payload.task_id}
    uvicorn.run(app, host=API_HOST, port=API_PORT, log_level="warning")

if __name__ == "__main__":
    if '--sandbox_mode' in sys.argv:
        try:
            task_file_path = sys.argv[sys.argv.index('--task_file') + 1]
            asyncio.run(_run_sandbox_session(task_file_path))
        except Exception: sys.exit(4)
    else:
        main()
'''
;

const
  PYTHON_CORE_TEMPLATE_IMPL =
    PYTHON_BLOCK_0_HEADER_IMPORTS + #13#10 +
    PYTHON_BLOCK_1_CONFIG_THEME_STATE + #13#10 +
    PYTHON_BLOCK_2_LOGGER + #13#10 +
    PYTHON_BLOCK_3_TRACER_DEBUGGER + #13#10 +
    PYTHON_BLOCK_4_POLICY_ENGINE + #13#10 +
    PYTHON_BLOCK_5_COMMAND_RUNNER + #13#10 +
    PYTHON_BLOCK_6_PACKAGE_MANAGER + #13#10 +
    PYTHON_BLOCK_7_VENV_MANAGER + #13#10 +
    PYTHON_BLOCK_8_WORKSPACE_AND_PATCHER + #13#10 +
    PYTHON_BLOCK_8a_LIVE_STATUS + #13#10 +
    PYTHON_BLOCK_9_SESSION_HANDLER + #13#10 +
    PYTHON_BLOCK_10_API_SERVER_AND_MAIN;
initialization
  PString(@PYTHON_CORE_TEMPLATE)^ := PYTHON_CORE_TEMPLATE_IMPL;

end.





