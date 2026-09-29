# WSL2 Dev Environment Playbook — Modern C++ & Python

**Scope:** clean Windows 11 machine → fully working WSL2 environment for modern C++ (C++20/23, CMake, vcpkg) and modern Python (uv-based), wired into VS Code.
**Time:** ~45–60 minutes end to end.

---

## Prerequisites

- Windows 11, or Windows 10 21H2+ (build 19041+), with admin rights
- Virtualization enabled in BIOS/UEFI (on by default on most machines; `systeminfo` in PowerShell shows "Virtualization Enabled In Firmware: Yes" if you need to check)
- ~20 GB free disk space

---

## Part 1 — WSL2 Foundation

### 1.1 Install WSL2 + Ubuntu

In an **admin PowerShell**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot if prompted, then let Ubuntu finish first boot and set your Linux username/password. Confirm you're on WSL2 with a current kernel:

```powershell
wsl -l -v      # should show Ubuntu-24.04, VERSION 2
wsl --update
wsl --version
```

### 1.2 Windows-side tuning — WSL Settings

On current Windows 11 and WSL releases, open **WSL Settings** from the Start menu. Use it to configure the WSL virtual machine's memory, processors, swap, and networking mode. This is preferable to editing a configuration file because the settings are validated and the available options match the installed WSL version.

For a Windows 11 machine, use mirrored networking if you need WSL services to be reachable through the host network or regularly work behind VPNs. Keep the default NAT mode if your network does not need mirrored mode or if you are on Windows 10.

Use `%USERPROFILE%\.wslconfig` only for settings not exposed by the GUI. For example:

```ini
[experimental]
sparseVhd=true
autoMemoryReclaim=gradual
```

Notes:
- Set `memory`/`processors` to roughly 70–80% of your host, not 100% — leave Windows room to breathe.
- `sparseVhd` applies automatically to newly created virtual disks; it does not convert existing disks.
- `autoMemoryReclaim` and `sparseVhd` are experimental settings and may not appear in WSL Settings.
- `localhostForwarding` is unnecessary when mirrored networking is enabled, and `dnsTunneling`, `firewall`, and `autoProxy` are already enabled by default on current WSL releases.
- Apply file changes with `wsl --shutdown` from PowerShell, then reopen your terminal. GUI changes may also require a WSL restart.

### 1.3 Linux-side tuning — `/etc/wsl.conf`

Inside Ubuntu:

```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true

[automount]
options = "metadata,noatime"
EOF
```

- `systemd=true` is enabled by default in current Ubuntu images, but setting it explicitly makes the requirement visible for Docker and other services that use `systemctl`.
- `metadata` enables Linux permission metadata on Windows-mounted files. Keep active projects in the Linux filesystem as described below; this option does not make `/mnt/c` perform like a native Linux filesystem.
- Do not add a `[user]` block unless you deliberately need to change the default login user. The user created during Ubuntu's first launch is already the default.
- Apply: `wsl --shutdown` (from PowerShell), reopen. Verify with `systemctl list-unit-files --type=service | head`.

### 1.4 Where your code lives — this matters more than anything else here

Keep every project under the Linux filesystem (`~/dev/...`). **Never** `/mnt/c/...`. Cross-filesystem I/O between Windows and the WSL2 VM is the single biggest cause of "WSL is slow" complaints, and it hits C++ compiles (thousands of small header reads) and Python (large `site-packages` trees) especially hard.

---

## Part 2 — Base Linux Setup

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y build-essential git curl wget unzip zip pkg-config \
  software-properties-common ca-certificates gnupg lsb-release
mkdir -p ~/dev
```

### 2.1 Core CLI and developer tools

Install the everyday tools used by the rest of this guide and by most development workflows:

```bash
sudo apt install -y \
  git git-lfs gh \
  tmux neovim \
  ripgrep fd-find fzf jq tree \
  htop ncdu file less man-db shellcheck valgrind \
  openssh-client

git lfs install
```

Useful notes for Ubuntu package names:

- `fd-find` installs the `fdfind` command. Add a personal alias if you prefer the usual `fd` name:

  ```bash
  mkdir -p ~/.local/bin
  ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  ```

- Ubuntu's `bat` package, when available, installs the `batcat` command. It is optional; `less` is sufficient for this guide.
- `neovim` is the package name for Neovim. Launch it with `nvim`.
- `gh auth login` authenticates GitHub CLI independently of your SSH key. Use SSH for Git remotes if you want your key to be used for clone/push operations.

Check the core installation:

```bash
git --version
gh --version
tmux -V
nvim --version | head -n 1
rg --version
fdfind --version
valgrind --version
```

---

## Part 3 — Modern C++ Toolchain

### 3.1 Compilers — GCC and Clang side by side

```bash
sudo apt install -y gcc g++ clang clangd clang-format clang-tidy lld gdb lldb
```

The Ubuntu packages provide stable C++20 support and the C++23 features supported by the installed compiler. Use the compiler version from `gcc --version` or `clang --version` rather than hard-coding a major version into the guide. Add the Ubuntu Toolchain PPA or LLVM's official repository only when a project requires a newer compiler than Ubuntu provides.

### 3.2 Build tools

```bash
sudo apt install -y ninja-build ccache cmake
echo 'export PATH="/usr/lib/ccache:$PATH"' >> ~/.bashrc
```

### 3.3 Package management — vcpkg, manifest mode

```bash
git clone https://github.com/microsoft/vcpkg.git ~/dev/vcpkg
~/dev/vcpkg/bootstrap-vcpkg.sh
cat >> ~/.bashrc <<'EOF'
export VCPKG_ROOT=$HOME/dev/vcpkg
export PATH=$VCPKG_ROOT:$PATH
EOF
source ~/.bashrc
```

Per project:

```bash
mkdir -p ~/dev/my-project/src && cd ~/dev/my-project
vcpkg new --application               # scaffolds vcpkg.json
vcpkg add port fmt spdlog gtest
```

`CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.25)
project(my_project CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)   # clangd needs this

find_package(fmt CONFIG REQUIRED)
add_executable(my_project src/main.cpp)
target_link_libraries(my_project PRIVATE fmt::fmt)
```

`CMakePresets.json` (ties vcpkg + Ninja together so `cmake --preset default` just works):

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "default",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build",
      "toolchainFile": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
      "cacheVariables": { "CMAKE_CXX_COMPILER": "clang++" }
    }
  ]
}
```

Build:

```bash
cmake --preset default
cmake --build build
```

### 3.4 Smoke test the compiler and memory checks

Before troubleshooting VS Code, confirm the Linux toolchain works directly in the terminal:

```bash
cat > /tmp/hello.cpp <<'EOF'
#include <iostream>

int main() {
  std::cout << "Hello from WSL C++\\n";
}
EOF

g++ -std=c++20 -Wall -Wextra -Wpedantic /tmp/hello.cpp -o /tmp/hello
/tmp/hello
valgrind --leak-check=full /tmp/hello
```

`build-essential` already provides `make`, so simple or legacy repositories can use a `Makefile` directly. For modern projects, prefer CMake presets because they describe the compiler, generator, dependencies, and build directory in the repository.

---

## Part 4 — Modern Python Toolchain

`uv` (Astral) provides fast replacements for the usual pyenv + venv + pip + pip-tools + pipx workflow. It reads existing `pyproject.toml` / `.python-version` files directly, making it a good fit if you're already thinking in PEP 517/pyproject terms.

### 4.1 Install

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"
uv --version
```

If the installer reports a different environment-file path, open a new shell or source the path it prints. Do not install `uv` with `sudo`; it should remain a user-owned tool.

### 4.2 Python versions — no separate pyenv needed

```bash
uv python install 3.12 3.13
```

### 4.3 New project

```bash
uv init --python 3.12 ~/dev/my-python-project
cd ~/dev/my-python-project
uv python pin 3.12
uv add requests rich
uv add --dev pytest ruff mypy
```

`uv init` sets `requires-python` in the generated `pyproject.toml` to the newest Python it finds installed (e.g. `>=3.13` if you've also installed 3.13). If you skip `--python` here and later run `uv python pin 3.12` on its own, it fails with "requested Python version `3.12` is incompatible with the project `requires-python` value of `>=3.13`". Pass `--python` on `uv init` as shown, or edit `requires-python` in `pyproject.toml` before pinning an older interpreter.

`uv sync` (or the first `uv add`/`uv run`) creates `.venv` and `uv.lock` for you. Run everything through `uv run` — no manual activation:

```bash
uv run pytest
uv run ruff check .
uv run ruff format .
uv run mypy .
```

If some tool insists on `pip` existing inside the venv (uv omits it by default): `uv venv --seed`.

### 4.4 Global CLI tools, isolated from any project venv

```bash
uv tool install httpie
uv tool install cookiecutter
```

---

## Part 5 — .NET and C# Toolchain

### 5.1 Install the latest .NET SDK

For Ubuntu 24.04, install the current .NET 10 SDK from the Ubuntu package feed. The SDK includes the .NET runtime and the ASP.NET Core runtime needed for development:

```bash
sudo apt update
sudo apt install -y dotnet-sdk-10.0

dotnet --info
dotnet --list-sdks
```

Create and run a test application:

```bash
mkdir -p ~/dev/my-dotnet-app
cd ~/dev/my-dotnet-app
dotnet new console
dotnet run
```

For an ASP.NET Core application:

```bash
dotnet new webapi -n MyApi
cd MyApi
dotnet run
```

Use a `global.json` file when a repository must pin a specific SDK feature band. Do not install multiple .NET package feeds for the same version; mixing Ubuntu and Microsoft feeds can cause package conflicts. .NET 9 is the current supported non-LTS release; install it only when a project targets it:

```bash
sudo apt install -y dotnet-sdk-9.0
```

### 5.2 .NET project commands

```bash
dotnet restore
dotnet build
dotnet test
dotnet format
```

For NuGet tools, install them as local tools in the repository when possible:

```bash
dotnet new tool-manifest
dotnet tool install dotnet-ef
dotnet tool restore
```

### 5.3 C# and .NET VS Code extensions

Install these in the Remote-WSL window so language services and debugging run inside WSL:

| Extension | ID | Why |
|---|---|---|
| C# Dev Kit | `ms-dotnettools.csdevkit` | C# solutions, projects, navigation, testing, and debugging |
| C# | `ms-dotnettools.csharp` | C# language service used by C# Dev Kit |
| .NET Runtime Install Tool | `ms-dotnettools.vscode-dotnet-runtime` | Helps provide a supported runtime for VS Code tooling |
| NuGet Gallery | `patcx.vscode-nuget-gallery` | Browse and manage NuGet packages from VS Code |

C# Dev Kit may install the C# extension and .NET runtime support automatically. Keep the explicit IDs here as a reference, and avoid installing multiple competing C# language extensions for the same workspace.

---

## Part 6 — Editor Integration (VS Code + Remote-WSL)

Install VS Code on **Windows**, not inside Linux. Then, from inside a WSL project folder:

```bash
code .
```

This installs the VS Code Server on the Linux side automatically. Add these extensions (search for them inside the Remote-WSL window so they install server-side):

| Extension | ID | Why |
|---|---|---|
| WSL | `ms-vscode-remote.remote-wsl` | The bridge everything else depends on |
| clangd | `llvm-vs-code-extensions.vscode-clangd` | Pairs with the LLVM toolchain from Part 3 |
| CMake Tools | `ms-vscode.cmake-tools` | Configure/build/debug from the UI |
| C/C++ (optional) | `ms-vscode.cpptools` | Microsoft debugger integration; disable its IntelliSense when using clangd |
| Makefile Tools (optional) | `ms-vscode.makefile-tools` | Build and debug repositories that use Makefiles instead of CMake |
| Python + Pylance | `ms-python.python`, `ms-python.vscode-pylance` | Core Python support |
| Ruff | `charliermarsh.ruff` | Real-time lint/format matching your `uv run ruff` setup |
| C# Dev Kit + C# | `ms-dotnettools.csdevkit`, `ms-dotnettools.csharp` | C# project management, IntelliSense, testing, and debugging |
| .NET Runtime Install Tool | `ms-dotnettools.vscode-dotnet-runtime` | Runtime support for .NET tooling |
| NuGet Gallery | `patcx.vscode-nuget-gallery` | Browse and manage NuGet packages from VS Code |
| Docker / Container Tools | `ms-azuretools.vscode-docker` | Dockerfile, Compose, images, containers, and registries |
| Dev Containers | `ms-vscode-remote.remote-containers` | Reopen a project inside a reproducible development container |
| GitHub Pull Requests | `github.vscode-pull-request-github` | Review and manage GitHub pull requests in VS Code |

If you install both `clangd` and Microsoft's C/C++ extension, disable one IntelliSense engine. To keep clangd as the engine, install the Microsoft C/C++ extension only if you need its debugger integration, then use:

`.vscode/settings.json`:

```json
{
  "C_Cpp.intelliSenseEngine": "disabled",
  "clangd.path": "/usr/bin/clangd",
  "clangd.arguments": ["--compile-commands-dir=build", "--header-insertion=never"],
  "cmake.generator": "Ninja"
}
```

For a CMake project, use the CMake status-bar controls or the Command Palette commands **CMake: Select Configure Preset**, **CMake: Build**, and **CMake: Debug**. For a Makefile project, use Makefile Tools or run `make` from the integrated WSL terminal. Avoid the generic Code Runner extension for C++ projects because it commonly bypasses the project's CMake/Make configuration, compiler flags, and dependency setup.

For Python, run `uv sync` once in the project and select the resulting `.venv` with **Python: Select Interpreter** if the Python extension does not detect it automatically. Keep the VS Code window connected to WSL so terminals, extensions, compilers, and interpreters all run on the Linux side.

---

## Part 7 — Git, SSH, Shell

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main

ssh-keygen -t ed25519 -C "you@example.com"
cat ~/.ssh/id_ed25519.pub    # add this to GitHub/GitLab

gh auth login
```

### 7.1 Shell prompt — Starship

Starship is a fast, cross-shell prompt that shows useful context such as the current Git branch, changes, Python environment, .NET SDK, and command duration. It is the part that makes the terminal look polished without loading a large shell framework.

```bash
curl -sS https://starship.rs/install.sh | sh

# Enable Starship in Bash.
grep -qxF 'eval "$(starship init bash)"' ~/.bashrc || \
  echo 'eval "$(starship init bash)"' >> ~/.bashrc

# Optional: install Zsh and enable Starship there too.
sudo apt install -y zsh
grep -qxF 'eval "$(starship init zsh)"' ~/.zshrc 2>/dev/null || \
  echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# Optional: make Zsh the default shell.
chsh -s "$(command -v zsh)"

# Use a readable preset with Nerd Font symbols.
mkdir -p ~/.config
starship preset nerd-font-symbols -o ~/.config/starship.toml
```

Close and reopen the terminal, or reload the current shell with `exec bash` or `exec zsh`. In Windows Terminal, install and select a Nerd Font such as **CaskaydiaCove Nerd Font** or **JetBrainsMono Nerd Font** under the Ubuntu profile's font settings; otherwise the prompt symbols may appear as empty boxes. The font is configured in Windows Terminal, not inside Ubuntu.

For a simpler setup, install Starship and enable it only in Bash. Do not install both Oh My Zsh and Starship unless you specifically want Oh My Zsh's plugins; they are separate layers and can make shell startup slower.

---

## Part 8 — Containers (optional)

Pick one approach and do not run both Docker daemons for the same workflow:

- **Docker Desktop for Windows**, with WSL2 integration enabled (Settings → Resources → WSL Integration) — simplest, one daemon shared across all your distros.
- **Docker Engine natively inside WSL2**, no Docker Desktop, with systemd enabled:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
sudo systemctl enable --now docker
```

The convenience script installs Docker's current packages and is appropriate for a personal development machine. For managed or production-like environments, follow Docker's official Ubuntu repository instructions instead. Start a new shell after changing the `docker` group, then verify with `docker run hello-world`.

### 8.1 Docker tools in VS Code

The Microsoft Docker extension is now named **Container Tools** in its marketplace description, but its extension ID remains `ms-azuretools.vscode-docker`. It provides Dockerfile and Compose IntelliSense, image/container/volume management, registry access, and Docker commands from the Command Palette.

Install **Dev Containers** as well when a project contains `.devcontainer/devcontainer.json` or when you want the full compiler and SDK environment isolated inside a container. From a WSL folder in VS Code, use **Dev Containers: Reopen in Container**. Keep source code under `~/dev`, not `/mnt/c`, for good filesystem performance.

Verify Docker and Compose:

```bash
docker version
docker compose version
docker run --rm hello-world
```

For Docker Desktop, enable **Use the WSL 2 based engine** and enable the Ubuntu distribution under **Settings > Resources > WSL Integration**. Do not install or start a second Docker daemon inside Ubuntu when using Docker Desktop.

---

## Part 9 — Verification

**C++:**

```bash
cmake --preset default && cmake --build build && ./build/my_project
```

**Python:**

```bash
cd ~/dev/my-python-project
uv run python -c "import sys; print(sys.version)"
uv run pytest
```

**.NET:**

```bash
cd ~/dev/my-dotnet-app
dotnet build
dotnet test
dotnet run
```

If both run clean, the environment is good.

---

## Part 10 — Ongoing maintenance

- `wsl --shutdown` (PowerShell) every so often to reclaim memory and flush the VM
- `sudo apt update && sudo apt full-upgrade -y` monthly
- Update WSL with `wsl --update` and update Ubuntu packages with `sudo apt update && sudo apt full-upgrade -y`
- Update `uv` with `uv self update` when installed by the uv installer; if it was installed another way, use that package manager
- Keep the compiler toolchain current through Ubuntu package updates. Use a newer LLVM or GCC repository only when a project requires it
- If the `.vhdx` balloons over time: `wsl --shutdown`, then compact it via `diskpart` (`select vdisk file="..."` → `compact vdisk`) or `Optimize-VHD` if Hyper-V tools are installed

---

## Quick-reference cheat sheet

| Task | Command |
|---|---|
| Shut down WSL | `wsl --shutdown` (PowerShell) |
| List distros/versions | `wsl -l -v` |
| New C++ project | `vcpkg new --application` → edit `CMakeLists.txt` → `cmake --preset default` |
| New Python project | `uv init && uv add <pkgs> && uv run <cmd>` |
| Add a Python version | `uv python install 3.13` |
| Open project in VS Code | `code .` (from inside WSL) |
