#!/usr/bin/env bash
#
# WSL2 dev environment setup — modern C++ (CMake/vcpkg) & modern Python (uv)
# Linux-side only. Skips everything that must happen on the Windows host
# (installing WSL2 itself, WSL Settings/.wslconfig tuning, installing VS Code,
# and Windows Terminal font configuration) — do those manually first per
# wsl2-cpp-python-dev-setup.md, Part 1.
#
# Safe to re-run: package installs are naturally idempotent, and anything that
# appends to ~/.bashrc or clones a repo is guarded so it won't duplicate.

set -euo pipefail

# --- Edit these before running -----------------------------------------
GIT_USER_NAME="dmak007"
GIT_USER_EMAIL="dmitrey.makarov-paton@myob.com"
# -------------------------------------------------------------------------

# Small helper: append a line to ~/.bashrc only if it isn't already there.
append_bashrc_once() {
  local line="$1"
  grep -qxF "$line" ~/.bashrc 2>/dev/null || echo "$line" >> ~/.bashrc
}

echo "==> Part 1.3 — /etc/wsl.conf (systemd + Linux permission metadata on Windows mounts)"
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true

[automount]
options = "metadata,noatime"
EOF
echo "    wsl.conf written. Run 'wsl --shutdown' from PowerShell and reopen your terminal"
echo "    for this to take effect (can't be done from inside this script)."

echo "==> Part 1.4 — project directory (keep code on the Linux filesystem, not /mnt/c)"
mkdir -p ~/dev

echo "==> Part 2 — base packages"
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y build-essential git curl wget unzip zip pkg-config \
  software-properties-common ca-certificates gnupg lsb-release

echo "==> Part 2.1 — core CLI / developer tools"
sudo apt install -y \
  git git-lfs gh \
  tmux neovim \
  ripgrep fd-find fzf jq tree \
  htop ncdu file less man-db shellcheck valgrind \
  openssh-client

git lfs install

# Ubuntu ships fd-find as `fdfind`; symlink it to the usual `fd` name.
mkdir -p ~/.local/bin
ln -sf "$(command -v fdfind)" ~/.local/bin/fd
append_bashrc_once 'export PATH="$HOME/.local/bin:$PATH"'

echo "==> Part 3.1 — C++ compilers (GCC + Clang side by side)"
sudo apt install -y gcc g++ clang clangd clang-format clang-tidy lld gdb lldb

echo "==> Part 3.2 — build tools (Ninja, ccache, CMake)"
sudo apt install -y ninja-build ccache cmake
append_bashrc_once 'export PATH="/usr/lib/ccache:$PATH"'

echo "==> Part 3.3 — vcpkg (manifest mode package management)"
if [ ! -d ~/dev/vcpkg ]; then
  git clone https://github.com/microsoft/vcpkg.git ~/dev/vcpkg
  ~/dev/vcpkg/bootstrap-vcpkg.sh
fi
append_bashrc_once 'export VCPKG_ROOT=$HOME/dev/vcpkg'
append_bashrc_once 'export PATH=$VCPKG_ROOT:$PATH'

echo "==> Part 3.4 — smoke test the compiler and memory checks"
cat > /tmp/hello.cpp <<'EOF'
#include <iostream>

int main() {
  std::cout << "Hello from WSL C++\n";
}
EOF
g++ -std=c++20 -Wall -Wextra -Wpedantic /tmp/hello.cpp -o /tmp/hello
/tmp/hello
valgrind --leak-check=full /tmp/hello
rm -f /tmp/hello.cpp /tmp/hello

echo "==> Part 4.1 — uv (fast Python toolchain: replaces pyenv + venv + pip + pipx)"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
# Make uv available in this script's current shell without a full reload.
export PATH="$HOME/.local/bin:$PATH"
uv --version

echo "==> Part 4.2 — Python versions (no separate pyenv needed)"
uv python install 3.12 3.13

echo "==> Part 4.4 — global CLI tools, isolated from any project venv"
uv tool install httpie
uv tool install cookiecutter

echo "==> Part 5.1 — .NET SDK (10.0, current LTS for Ubuntu 24.04)"
sudo apt update
sudo apt install -y dotnet-sdk-10.0
dotnet --info

echo "==> Part 6 — VS Code extensions (server-side, via Remote-WSL)"
# Requires VS Code + the Remote-WSL extension already installed on Windows,
# and that this shell has been opened at least once via 'code .' so the
# 'code' CLI shim is on PATH. Skipped otherwise.
if command -v code >/dev/null 2>&1; then
  code --install-extension llvm-vs-code-extensions.vscode-clangd
  code --install-extension ms-vscode.cmake-tools
  code --install-extension ms-vscode.cpptools           # optional: only needed for its debugger if you disable clangd IntelliSense
  code --install-extension ms-vscode.makefile-tools     # optional: only needed for Makefile-based (non-CMake) repos
  code --install-extension ms-python.python
  code --install-extension ms-python.vscode-pylance
  code --install-extension charliermarsh.ruff
  code --install-extension ms-dotnettools.csdevkit
  code --install-extension ms-dotnettools.csharp
  code --install-extension ms-dotnettools.vscode-dotnet-runtime
  code --install-extension patcx.vscode-nuget-gallery
  code --install-extension ms-azuretools.vscode-docker
  code --install-extension ms-vscode-remote.remote-containers
  code --install-extension github.vscode-pull-request-github
else
  echo "    'code' CLI not found — open this WSL folder in VS Code once (code .)"
  echo "    from Windows first, then re-run this script to install extensions."
fi

echo "==> Part 7 — Git identity and SSH key"
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main

if [ ! -f ~/.ssh/id_ed25519 ]; then
  ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -N "" -f ~/.ssh/id_ed25519
  echo "    New SSH key generated. Add this public key to GitHub/GitLab:"
  cat ~/.ssh/id_ed25519.pub
else
  echo "    ~/.ssh/id_ed25519 already exists, skipping key generation."
fi

echo "    Run 'gh auth login' manually — it's interactive and shouldn't run unattended."

echo "==> Part 7.1 — Starship prompt (Bash only; add Zsh yourself if you want it too)"
if ! command -v starship >/dev/null 2>&1; then
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi
append_bashrc_once 'eval "$(starship init bash)"'
mkdir -p ~/.config
[ -f ~/.config/starship.toml ] || starship preset nerd-font-symbols -o ~/.config/starship.toml
echo "    Select a Nerd Font (e.g. CaskaydiaCove Nerd Font) for the Ubuntu profile"
echo "    in Windows Terminal, or prompt symbols will render as empty boxes."

echo "==> Part 8 — Docker Engine, native inside WSL2 (skip if you use Docker Desktop instead)"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  echo "    Added $USER to the docker group — open a new shell before running docker commands."
else
  echo "    docker already installed, skipping."
fi

echo ""
echo "==> Setup complete. Next steps:"
echo "    1. Run 'wsl --shutdown' from PowerShell and reopen your terminal (applies wsl.conf)."
echo "    2. Run 'exec bash' or open a new terminal to pick up PATH/env changes and Starship."
echo "    3. Run 'gh auth login' to authenticate the GitHub CLI."
echo "    4. Add the printed SSH public key to GitHub/GitLab if one was generated."
