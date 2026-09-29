# Python Modules, Packages, and Libraries: A Practical Tutorial (with `uv`)

A from-the-ground-up guide to how Python code is organized — from a single `.py` file
to a package you publish for the world to `pip install` (or rather, `uv add`).

---

## 0. Terminology, precisely

These words get used loosely. Precision here will save you hours of confusion later.

| Term | Definition |
|---|---|
| **Module** | A single `.py` file. Its name is the filename without `.py`. |
| **Package** | A directory of modules containing an `__init__.py` (a "regular package"), or without one (a "namespace package" — advanced, covered briefly). Packages can contain subpackages. |
| **Distribution package** | The installable *thing* — a `.whl` or `.tar.gz` — that you `pip install` / `uv add`. It has a name on PyPI (e.g. `requests`) and can contain one or more *import* packages. |
| **Library** | Informal term for a distribution package meant to be imported and reused by other code (as opposed to an "application"). |

The key confusion to dissolve early: **the name you `import` and the name you `pip install` are not always the same string.** `pip install pyyaml` gives you `import yaml`. `pip install beautifulsoup4` gives you `import bs4`. Keep import-name and distribution-name mentally separate.

---

## 1. Setting up with `uv`

[`uv`](https://docs.astral.sh/uv/) is a modern, extremely fast replacement for `pip`, `venv`, `pip-tools`, `poetry`, and `pyenv`, written in Rust by Astral. We'll use it throughout instead of raw `pip`/`venv`.

### Install uv

```bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# or via pipx / pip if you already have Python
pipx install uv
```

Verify:

```bash
uv --version
```

### The core uv workflow

`uv` centers on a `pyproject.toml` file (no more juggling `requirements.txt` + `setup.py` + a manually-managed venv).

```bash
# Create a new application project
uv init myapp
cd myapp

# Create a new *library* project (adds src-layout + build backend — see Part 3)
uv init --lib mylib
```

`uv init myapp` produces:

```
myapp/
├── .gitignore
├── .python-version
├── main.py
├── pyproject.toml
└── README.md
```

Run code — **you rarely need to manually activate a venv with uv**:

```bash
uv run main.py
```

`uv run` transparently creates/reuses `.venv/`, resolves and installs dependencies from `pyproject.toml`, and executes the command inside it. This one command replaces "activate venv, then run script" in nearly every workflow below.

Add dependencies:

```bash
uv add requests          # adds to pyproject.toml, updates uv.lock, installs it
uv add --dev pytest ruff # a "dev" dependency group, not shipped to users
uv remove requests
uv sync                  # install exactly what's locked, e.g. after cloning a repo
```

If you truly want a classic activated shell:

```bash
uv venv               # create .venv
source .venv/bin/activate   # Linux/macOS
.venv\Scripts\activate      # Windows
```

We'll use `uv run` throughout since it's the idiomatic modern approach.

---

## 2. Modules: the atomic unit

A module is just a `.py` file. Create one:

```bash
uv init demo && cd demo
```

**`greetings.py`**
```python
# greetings.py
GREETING_PREFIX = "Hello"

def greet(name: str) -> str:
    return f"{GREETING_PREFIX}, {name}!"

def _internal_helper():
    """Leading underscore = 'private by convention'. Not enforced, but respected."""
    pass

if __name__ == "__main__":
    # Only runs when this file is executed directly, e.g. `uv run greetings.py`
    # NOT when it's imported by something else.
    print(greet("World"))
```

**`main.py`**
```python
import greetings

print(greetings.greet("Ada"))
print(greetings.GREETING_PREFIX)

# alternative import styles:
from greetings import greet
print(greet("Grace"))

from greetings import greet as say_hi
print(say_hi("Alan"))

import greetings as g
print(g.greet("Linus"))
```

```bash
uv run main.py
```

### What actually happens on `import`

1. Python checks `sys.modules` (a cache) — if `greetings` was already imported anywhere in this process, it reuses that same module object. **Modules are singletons per process.**
2. If not cached, Python searches `sys.path` (current script's directory, installed packages' locations, stdlib paths, `PYTHONPATH` if set) for a file/package matching the name.
3. It compiles and executes the module's code top-to-bottom, exactly once, populating a fresh module namespace.
4. That namespace object is bound to the name in the importing scope, and cached in `sys.modules`.

This is why side effects at module level (e.g. `print("loading!")` sitting outside any function) run only once no matter how many times the module is imported.

### The `if __name__ == "__main__":` idiom

Every module has a `__name__` attribute. When a file is run directly, Python sets `__name__ = "__main__"` for it. When the same file is *imported*, `__name__` is set to the module's actual name (`"greetings"`). This idiom lets a file act as *both* a reusable module and a runnable script, without the "runnable" part executing on import.

---

## 3. Packages: directories of modules

A package is a directory containing `__init__.py` (which can be empty) plus other modules or subpackages.

```
myproject/
├── main.py
└── shapes/
    ├── __init__.py
    ├── circle.py
    ├── square.py
    └── solids/
        ├── __init__.py
        └── sphere.py
```

**`shapes/circle.py`**
```python
import math

def area(radius: float) -> float:
    return math.pi * radius ** 2

def circumference(radius: float) -> float:
    return 2 * math.pi * radius
```

**`shapes/square.py`**
```python
def area(side: float) -> float:
    return side ** 2
```

**`shapes/solids/sphere.py`**
```python
import math

def volume(radius: float) -> float:
    return (4 / 3) * math.pi * radius ** 3
```

### Importing across this package, from outside it (e.g. from `main.py`)

Use **absolute imports** rooted at the top-level package name:

```python
# main.py
from shapes import circle, square
from shapes.solids import sphere

print(circle.area(2))
print(square.area(3))
print(sphere.volume(1))
```

### Importing *within* the same package (module-to-module)

This is the part people get wrong most often. Two valid styles:

**A) Absolute imports (recommended — explicit, unambiguous, IDE-friendly):**

```python
# shapes/solids/sphere.py, wanting something from shapes/circle.py
from shapes.circle import area as circle_area
```

**B) Relative imports (concise, package-internal, and won't break if the package is renamed):**

```python
# shapes/solids/sphere.py
from ..circle import area as circle_area   # .. = go up one package level
from . import sphere                        # . = current package
```

Relative import rules:
- `.` = current package, `..` = parent package, `...` = grandparent, etc.
- **Relative imports only work inside a module that Python knows is part of a package** — i.e. it was imported *as* a package member, not run directly as a script. Running `uv run shapes/solids/sphere.py` directly will raise `ImportError: attempted relative import with no known parent package`. Always run/import via the package's entry point (`main.py` or `python -m shapes.solids.sphere`) instead.

**Rule of thumb:** absolute imports inside application code and for anything that might get restructured; relative imports are fine and common for tight internal coupling within a library's own subpackages (this is what `requests`, `django`, etc. do internally).

### `__init__.py`: controlling the package's public surface

`__init__.py` runs when the package is first imported. Its most common job is to curate what's exposed at the package's top level, so users don't need to know your internal file layout.

```python
# shapes/__init__.py
from .circle import area as circle_area
from .square import area as square_area

__all__ = ["circle_area", "square_area"]  # what `from shapes import *` exports
```

Now callers can do:

```python
from shapes import circle_area, square_area
```

instead of reaching into `shapes.circle`. This is exactly how libraries like `numpy` let you write `numpy.array(...)` instead of `numpy.core.multiarray.array(...)`.

`__all__` also documents (and enforces) your intended public API — anything not listed there should be considered "not part of the contract," even if technically importable.

### Namespace packages (brief note)

If you omit `__init__.py` entirely, Python 3.3+ treats the directory as an **implicit namespace package** — used mainly to let a single logical package (e.g. a company's `acme` namespace) be split across multiple independently-installed distributions. This is a niche, advanced feature (Kubernetes' `kubernetes` client and Google's `google.cloud.*` packages use it). Default to regular packages (with `__init__.py`) unless you specifically need this.

---

## 4. Importing from other (third-party) packages

Once installed, third-party packages import exactly like stdlib or your own packages — there's no syntactic difference:

```bash
uv add httpx pydantic
```

```python
import httpx
from pydantic import BaseModel

class User(BaseModel):
    name: str
    age: int

resp = httpx.get("https://example.com")
```

`uv add` writes the dependency into `pyproject.toml`:

```toml
[project]
dependencies = [
    "httpx>=0.27.0",
    "pydantic>=2.7.0",
]
```

...and locks exact resolved versions (including transitive dependencies) into `uv.lock`, which should be committed to version control so every machine/CI run gets byte-identical dependency versions.

### `sys.path`, and why installed packages are just "found"

`import` searches, in order:
1. The directory of the script being run (or `''`/cwd for the REPL).
2. `PYTHONPATH` directories, if set.
3. The installed site-packages directory of the active environment (`.venv/lib/python3.X/site-packages` — this is where `uv add` puts things).
4. The standard library.

You can inspect this at runtime:

```python
import sys
print(sys.path)
```

This is *why* virtual environments work: each venv has its own `site-packages`, so different projects can depend on different versions of the same library without colliding.

---

## 5. Building your own library package (the real goal)

Let's build a small, genuinely reusable library: `textkit`, a tiny text-utilities package. This is the shape you'd use for an internal shared library *or* an open-source PyPI package — same structure either way.

### 5.1 Scaffold with uv

```bash
uv init --lib textkit
cd textkit
```

This generates a **src-layout** project:

```
textkit/
├── .gitignore
├── .python-version
├── pyproject.toml
├── README.md
└── src/
    └── textkit/
        ├── __init__.py
        └── py.typed
```

**Why `src/` layout, not a flat `textkit/` next to `pyproject.toml`?** With a flat layout, running tests from the project root can accidentally import your *uninstalled source directory* instead of the properly *installed* package — masking packaging bugs (missing files, bad entry points) until a user hits them. The `src/` layout forces tests and code to go through the real installed package, exactly as your users will experience it. This is now considered best practice and is uv's default for libraries.

### 5.2 Flesh it out

```
textkit/
├── pyproject.toml
├── README.md
├── LICENSE
├── src/
│   └── textkit/
│       ├── __init__.py
│       ├── py.typed
│       ├── casing.py
│       └── stats.py
└── tests/
    ├── test_casing.py
    └── test_stats.py
```

**`src/textkit/casing.py`**
```python
def to_snake_case(s: str) -> str:
    """Convert 'CamelCase' or 'kebab-case' to 'snake_case'."""
    import re
    s = re.sub(r"[-\s]+", "_", s)
    s = re.sub(r"(?<!^)(?=[A-Z])", "_", s)
    return s.lower()

def to_camel_case(s: str) -> str:
    parts = s.replace("-", "_").split("_")
    return parts[0].lower() + "".join(p.title() for p in parts[1:])
```

**`src/textkit/stats.py`**
```python
from collections import Counter

def word_frequencies(text: str) -> dict[str, int]:
    words = text.lower().split()
    return dict(Counter(words))

def most_common_word(text: str) -> str | None:
    freqs = word_frequencies(text)
    return max(freqs, key=freqs.get) if freqs else None
```

**`src/textkit/__init__.py`** — define the public API and package version:
```python
from .casing import to_snake_case, to_camel_case
from .stats import word_frequencies, most_common_word

__version__ = "0.1.0"

__all__ = [
    "to_snake_case",
    "to_camel_case",
    "word_frequencies",
    "most_common_word",
]
```

`py.typed` is an empty marker file that tells type checkers (mypy, pyright) "this package ships its own type hints, trust its annotations" (per [PEP 561](https://peps.python.org/pep-0561/)). Include it for any modern library.

### 5.3 `pyproject.toml` — the real heart of the package

```toml
[project]
name = "textkit"
version = "0.1.0"
description = "Small, dependency-free text utilities."
readme = "README.md"
license = "MIT"
requires-python = ">=3.10"
authors = [
    { name = "Your Name", email = "you@example.com" }
]
keywords = ["text", "utilities", "casing"]
classifiers = [
    "Programming Language :: Python :: 3",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
]
dependencies = []

[project.optional-dependencies]
# extras: `uv add "textkit[cli]"` pulls these in too
cli = ["typer>=0.12"]

[dependency-groups]
# dev-only, never shipped to consumers of the package
dev = ["pytest>=8.0", "ruff>=0.5", "mypy>=1.10"]

[project.urls]
Homepage = "https://github.com/yourname/textkit"
Repository = "https://github.com/yourname/textkit"
Issues = "https://github.com/yourname/textkit/issues"

[project.scripts]
# optional: creates a `textkit` CLI command on install
textkit = "textkit.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

Notes:
- **`[project]`** is [PEP 621](https://peps.python.org/pep-0621/) standard metadata — tool-agnostic, so any build tool or installer understands it.
- **`[build-system]`** declares *how* to actually build the distribution artifact. `uv init --lib` defaults to [Hatchling](https://hatch.pypa.io/), a clean, modern backend. (Alternatives: `setuptools`, `flit-core`, `pdm-backend` — largely interchangeable for pure-Python packages.)
- **`dependencies`** = required at install time for *anyone* using this as a library. Keep this list minimal — every dependency you add becomes every user's problem too.
- **`[dependency-groups]`** (dev, test, docs, etc.) are *not* installed for consumers of your package — only when you run `uv sync` inside this repo for development.
- **`[project.scripts]`** auto-generates a console command wired to a `main()` function — this is how CLI tools like `black`, `ruff`, `httpx` (their CLIs) work.

### 5.4 Run tests and lint with uv

```bash
uv sync                 # installs the project itself + dev group into .venv
uv run pytest
uv run ruff check .
uv run mypy src
```

**`tests/test_casing.py`**
```python
from textkit import to_snake_case, to_camel_case

def test_to_snake_case():
    assert to_snake_case("CamelCase") == "camel_case"
    assert to_snake_case("kebab-case") == "kebab_case"

def test_to_camel_case():
    assert to_camel_case("snake_case") == "snakeCase"
```

Because of the `src/` layout, `uv sync` installs `textkit` into the venv (in *editable* mode by default for the current project), so `from textkit import ...` in your tests exercises the real packaged import path, not a path hack.

---

## 6. Using your library in *other* projects

This is the payoff. There are four common distribution mechanisms, roughly in order of "how far this needs to travel."

### 6.1 Local path dependency (same machine, actively co-developing)

In another project's `pyproject.toml`, or via CLI:

```bash
cd ../my-other-app
uv add --editable ../textkit
```

This installs `textkit` in **editable mode** — Python resolves imports straight to your `textkit/src` directory, so any edit there is immediately visible in `my-other-app` with no reinstall step. Ideal while developing a shared library alongside its consumer(s).

`pyproject.toml` records this as:
```toml
[tool.uv.sources]
textkit = { path = "../textkit", editable = true }
```

### 6.2 Git dependency (shared internal library, no package registry needed)

Perfect for an internal/private shared library that lives in a company Git repo:

```bash
uv add "textkit @ git+https://github.com/yourorg/textkit.git"

# pin to a branch, tag, or commit for reproducibility:
uv add "textkit @ git+https://github.com/yourorg/textkit.git@v0.3.0"
uv add "textkit @ git+https://github.com/yourorg/textkit.git@a1b2c3d"
```

`uv.lock` records the exact resolved commit, so this is fully reproducible without needing any package index at all — a great fit for internal tooling.

### 6.3 A private package index (company-scale shared libraries)

For many internal consumers, host on a private index (e.g. AWS CodeArtifact, Google Artifact Registry, Azure Artifacts, JFrog Artifactory, or a self-hosted [`pypiserver`](https://github.com/pypiserver/pypiserver) / [`devpi`](https://github.com/devpi/devpi)):

```toml
# pyproject.toml, in the *consuming* project
[[tool.uv.index]]
name = "internal"
url = "https://pypi.mycompany.com/simple"
```

```bash
uv add textkit --index internal
```

This is the scalable answer once you have more than a couple of consuming projects or teams — it behaves exactly like PyPI, just private, and versioning/upgrades work with ordinary `uv add textkit==1.4.0` semantics.

### 6.4 Publishing to (public) PyPI — the open-source path

**Build the distribution artifacts** (a wheel `.whl` and a source distribution `.tar.gz`):

```bash
uv build
```

This produces:
```
dist/
├── textkit-0.1.0-py3-none-any.whl
└── textkit-0.1.0.tar.gz
```

**Publish:**

```bash
# First, get an API token from https://pypi.org/manage/account/token/
uv publish --token pypi-YOUR_TOKEN_HERE

# or, better in CI: set it as an env var
export UV_PUBLISH_TOKEN=pypi-YOUR_TOKEN_HERE
uv publish
```

Anyone, anywhere, can now do:

```bash
uv add textkit
# or plain pip:
pip install textkit
```

```python
from textkit import to_snake_case
```

**Best practice: dry-run against TestPyPI first**, so a naming mistake doesn't burn your real package name:

```bash
uv publish --index testpypi   # configured to https://test.pypi.org/legacy/
```

#### A minimal open-source checklist

- **`LICENSE`** — without one, your code is technically "all rights reserved" by default, regardless of being on GitHub. MIT and Apache-2.0 are the common permissive choices.
- **`README.md`** — shown on both GitHub and the PyPI project page. Include install instructions, a quick usage example, and a badge or two.
- **Semantic versioning** (`MAJOR.MINOR.PATCH`) — bump `version` in `pyproject.toml` and tag the matching commit (`git tag v0.2.0`) on every release; consumers pin against this.
- **`CHANGELOG.md`** — even a few bullet points per release saves your users (and you) real pain.
- **CI** (GitHub Actions etc.) running `uv sync && uv run pytest && uv run ruff check .` on every push/PR.
- **Automate releases**: a GitHub Actions workflow triggered on tag push that runs `uv build && uv publish` using a repository secret for the PyPI token, so releases are one `git tag` + `git push --tags` away.

Example minimal release workflow (`.github/workflows/release.yml`):
```yaml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
      - run: uv build
      - run: uv publish
        env:
          UV_PUBLISH_TOKEN: ${{ secrets.PYPI_TOKEN }}
```

---

## 7. Multiple import packages in one distribution (advanced)

A single distribution package *can* expose more than one top-level importable package — useful for a "meta" library, or a monorepo publishing related pieces separately from one build:

```
src/
├── textkit/
│   └── __init__.py
└── textkit_cli/
    └── __init__.py
```

Hatchling/setuptools will happily package both under one `pip install textkit`, giving users both `import textkit` and `import textkit_cli`. This is uncommon for small libraries but is exactly what, e.g., `python-dateutil` (distribution `python-dateutil`, imports as `dateutil`) and many "extras"-style packages do under the hood. Generally, prefer **one distribution → one top-level import package** unless you have a specific reason not to — it's what users expect.

---

## 8. Common pitfalls (a field guide)

| Symptom | Cause | Fix |
|---|---|---|
| `ModuleNotFoundError` for a module clearly sitting right there | Ran the script directly from inside a package dir, so its parent isn't on `sys.path` as expected | Run from the project root via `uv run main.py`, or `uv run python -m package.module` |
| `ImportError: attempted relative import with no known parent package` | Ran a file containing relative imports directly (`python shapes/solids/sphere.py`) | Only invoke it via an entry point, or with `-m` |
| Circular import (`ImportError: cannot import name 'X' from partially initialized module`) | Module A imports module B at *module level*, and B imports A back, at module level | Restructure to remove the cycle; or move one of the imports inside the function that needs it (deferred/local import) |
| Editing your library's code doesn't seem to change behavior in the app using it | Installed as a *non-editable* dependency (a built wheel was cached) | Use `uv add --editable ../path` during development, or `uv sync --reinstall` |
| `pip install mypkg` works but `import mypkg` fails | Distribution name ≠ import name — you're calling the wrong name | Check the library's docs/`__init__.py`; e.g. `pyyaml` → `import yaml` |
| Package works on your machine, breaks for a colleague/CI | Flat layout let tests silently import uninstalled source instead of the real installed package | Use `src/` layout (uv's `--lib` default handles this) |
| Two versions of the same library needed by two projects clash | No isolated environment | Always use a per-project `uv` venv (`uv run` does this automatically) |

---

## 9. Quick-reference cheat sheet

```bash
# --- project setup ---
uv init myapp                 # new application
uv init --lib mylib           # new library (src-layout, buildable)
uv run main.py                # run, auto-managing venv + deps
uv sync                        # install deps to match pyproject.toml/uv.lock exactly

# --- dependencies ---
uv add requests                       # add a runtime dependency
uv add --dev pytest ruff              # add a dev-only dependency
uv add --editable ../otherlib         # local, live-editable dependency
uv add "lib @ git+https://..."        # git dependency
uv remove requests

# --- building & publishing ---
uv build                       # produce dist/*.whl and *.tar.gz
uv publish                     # upload to PyPI (or --index for a private one)

# --- running tools inside the project's env ---
uv run pytest
uv run ruff check .
uv run mypy src
```

```python
# --- import cheat sheet ---
import module                      # module.name
import module as m                 # m.name
from module import name            # name (bare)
from module import name as alias
from package import module         # package/module.py
from package.sub import module     # package/sub/module.py
from . import sibling_module       # relative: same package
from .. import cousin_package      # relative: parent package
from .sibling import thing         # relative: from a sibling module
```

---

## 10. Summary: mental model

1. **Module** = one file, one namespace, imported once per process (cached).
2. **Package** = a directory of modules with an `__init__.py`, which also defines the package's *public* surface.
3. **Within** a package, use absolute imports by default; relative imports (`.`, `..`) are fine for tightly-coupled internals, but only work when the file is imported as part of the package (never run directly).
4. **Distribution package** (what you build/publish) can differ in name from the **import package** (what you type after `import`) — always check both.
5. `uv` replaces the old pip+venv+twine dance: `uv init --lib`, `uv add`, `uv run`, `uv build`, `uv publish` cover the entire lifecycle from "first file" to "on PyPI," with `uv.lock` guaranteeing everyone (and CI) gets identical dependency resolutions.
6. Distribution paths scale up naturally: **local editable path** → **git dependency** → **private index** → **public PyPI**, and it's the same `pyproject.toml`-based package the whole way — you're just changing *where* it's fetched from, not how it's built.
