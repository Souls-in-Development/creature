# Contributing to creature

Thanks for your interest in improving `creature`.

## Contributor License Agreement (CLA)

`creature` is licensed under **AGPLv3**. To keep the project sustainably licensed — including the
ability to offer it under other terms — all contributions must be made under a Contributor License
Agreement. **You keep the copyright in your contribution**; the CLA is a licence grant, not an
assignment. It gives the maintainers the right to sublicense your contribution under other terms,
which is what makes dual-licensing possible.

The full text is in **[CLA.md](CLA.md)** — please read it before your first pull request.

By opening a pull request you agree to it. To leave an explicit record, sign off your commits:

```sh
git commit -s -m "your message"
```

(A CLA bot will be wired into pull requests later; until then, opening a PR constitutes agreement.)

## Development

- **Requirements:** macOS 14+, Xcode 26+, Apple Silicon.
- **Library + tests:** `swift build` and `swift test`.
- **Runnable binary** (MLX Metal shaders are built by Xcode, not SwiftPM):
  ```sh
  xcodebuild build -scheme creature -configuration Release -destination 'platform=macOS'
  ```

## Guidelines

- Keep the spine (`CreatureSpine`) dependency-light — inference engines live in `CreatureInference`.
- Run `swift test` before submitting; keep it green.
- Match the surrounding code's style and idiom.
