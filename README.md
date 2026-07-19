# creature

**A living terminal. The vessel before the soul.** — [soulsin.dev](https://soulsin.dev)

`creature` is an AI-agnostic terminal that runs language models — **your** models. It runs them
in-process on Apple Silicon (no Ollama, no LM Studio, no server), or connects to any
OpenAI-compatible endpoint. Bring your own soul(s).

---

> ### ⚠️ Early days — this needs willing guinea pigs
>
> This is pre-v1 and has been used seriously by roughly one person. If you try it, you are a
> tester, not a customer. Nothing here is polished and some of it will break in ways I haven't
> seen yet. That's the trade: you get it free and early, I get to find out what's wrong.
>
> **What actually works today**
> - macOS on Apple Silicon: builds, runs its own model in-process, chats, indexes a codebase.
> - Indexing across ~43 languages, and "earned green" compile-readiness for the languages whose
>   checker you have installed.
> - Linux: builds and runs, verified in a container. There it drives a local
>   [Ollama](https://ollama.com) instead of running the model itself.
>
> **What doesn't, or is unproven**
> - **Windows is untested.** It should build — nothing Apple-specific is left in the core — but
>   nobody has run it. If you try, I want to hear either way.
> - **The IDE is early.** The file tree, status and chat work; the editor is currently
>   **read-only** — no editing, no syntax highlighting.
> - **Nothing is notarised or signed** with an Apple Developer ID, so macOS will warn you about
>   the `.app`. The command-line tool is unaffected.
> - **No Homebrew tap or installer yet** — those exist in this repo but aren't published, so
>   build from source for now.
> - Only Swift and Python get real AST-quality indexing. Every other language is regex-level, and
>   deliberately reports UNKNOWN rather than claiming green.
>
> **If you hit something,** open an issue with what you ran and what happened. Rough edges are
> expected and useful; silent breakage is not.

---

## What it is

The creature has two cognitive slots — a **conscious** slot (reasoning, explanation, conversation)
and an **unconscious** slot (coding, logic) — and a calibration handshake that adapts to whatever
pair of models you plug in. Local models, remote endpoints, or a mix.

- **Runs its own model.** In-process inference via [MLX](https://github.com/ml-explore/mlx-swift)
  on Apple Silicon — the model runs inside `creature`, not a separate app.
- **Bring your own soul(s).** Any MLX-format model, or any OpenAI-compatible endpoint
  (Ollama, LM Studio, hosted APIs).
- **Private by default.** With in-process models, nothing leaves your machine.

## Requirements

- macOS 14+
- Apple Silicon (for in-process MLX models; remote endpoints work regardless)
- ~2 GB free disk for the default model on first run

## Build and run

One command. Requires **full Xcode** (not just the Command Line Tools), Apple Silicon, macOS 14+.

```sh
./build.sh
./bin/creature local "hello"
```

`build.sh` checks your toolchain, builds, and verifies the binary can actually generate before
telling you it's ready. First run downloads the default model (~1.6 GB) to `~/.cache/huggingface`.

Then:

```sh
./bin/creature chat                  # persistent multi-turn conversation
./bin/creature chat --context .      # ...grounded in this codebase
./bin/creature check .               # is this workspace green?
```

> **Don't use `swift build` for a binary you intend to run.** It compiles and passes the tests,
> but MLX's Metal shaders can't be built by SwiftPM, so the resulting binary cannot run a model.
> `swift build` / `swift test` are fine for compiling and testing — just use `./build.sh` to get
> something runnable. (If you do run a `swift build` binary, it tells you this rather than
> crashing.)

<details>
<summary>Homebrew / curl (not published yet)</summary>

The tap and installer are written and tested but **not live** — the public repos don't exist yet,
so these will 404 until release:

```sh
brew install Souls-in-Development/tap/creature
curl -fsSL https://soulsin.dev/install.sh | sh
```

Both install a pre-built binary. Neither sets macOS's quarantine flag, so there's no Gatekeeper
prompt. See `packaging/` and `scripts/`.

</details>

## Quickstart

```sh
creature config      # choose your models (local or remote), per slot — local is the default
creature chat        # start a conversation
creature ask "..."   # one-shot
```

## Commands

| Command | Does |
|---|---|
| `creature config` | Set up the conscious/unconscious slots (local model or remote endpoint) |
| `creature calibrate` | Run the sync handshake between the two models |
| `creature chat` | Persistent multi-turn conversation (Ctrl-D or `:quit` to exit) |
| `creature ask <prompt>` | One-shot |
| `creature status` | Show the current sync profile |
| `creature --version` | Print the version |

## Models

`creature` runs MLX-format models (from [`mlx-community`](https://huggingface.co/mlx-community)),
downloaded and cached on first use. The default pair is Apache-2.0 licensed:

- Conscious: `mlx-community/Qwen2.5-3B-Instruct-4bit`
- Unconscious: `mlx-community/Qwen2.5-Coder-3B-Instruct-4bit`

Bring any others you like (7B variants for more capable machines), or point a slot at a remote
OpenAI-compatible endpoint.

## License

AGPLv3 — see [LICENSE](LICENSE). Free to use, modify, and share; if you run a modified version
as a network service, you must make your changes available under the same terms.

`creature` is free. If it's useful to you, you can support development at
[soulsin.dev](https://soulsin.dev).

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Contributions require agreeing
to a lightweight Contributor License Agreement so the project can be sustainably licensed.
