# AGENTS.md

Canonical instructions for AI coding agents working in this repository.

This file is **agent state**, not user documentation. The user-facing site is
`docs/` (Docusaurus). What is left to do lives in GitHub Issues; what was
already decided, and why, lives in [decisions/](decisions/README.md).

## 1. Start of session, in this order

1. `gh issue list` — what is outstanding. Items labelled `verify` need the user
   at the machine and cannot be closed by an agent.
2. [decisions/README.md](decisions/README.md) — what was already settled, and
   why. Check this before proposing a change that may contradict a record.
3. The `README.md` of the directory you are about to touch. They are the
   explanation layer and they are long on purpose.

## 2. Project context

- CachyOS, Hyprland, **Lua** config — `hypr/hyprland.lua` and `hypr/config/*.lua`,
  not `hyprland.conf`. Dispatchers are Lua: `hyprctl dispatch 'hl.dsp.dpms({action = "on"})'`.
- 8 GB RAM, Intel iGPU, laptop. **Lightweight is a hard constraint**, not a
  preference: systemd-oomd has killed the whole desktop twice. See
  `system/README.md`.
- Working directory is `~/MyArch`; the remote is `CachyOS_dotfiles`. The repo is
  **public**.
- `install.sh` both installs and audits. Config is symlinked into `~/.config`,
  so edits in the repo are live.

## 3. Source of truth, highest authority first

1. **The running system** — `hyprctl getoption`, `hyprctl monitors -j`,
   `systemctl show`, `busctl get-property`, `pacman -Qo`, `/sys`, `/proc`.
2. The config files in this repo.
3. The ADRs in `decisions/`.
4. Prose in the READMEs.

Verify against the system before claiming anything about it. A README can be
out of date; `/sys` cannot.

## 4. Evidence rules

These are not style advice. Each one is here because ignoring it caused a real
failure in this repository.

- **An exit code of 0 or a printed `ok` is not evidence.**
  `hyprctl dispatch 'hl.dsp.dpms()'` with no arguments and
  `hl.dsp.dpms("bogus")` both print `ok`. Trusting that put a command that
  *switches the display off* into hypridle's `after_sleep_cmd` for two days.
  Read the state back: `hyprctl monitors -j | jq '.[].dpmsStatus'`.
- **Never say "done", "fixed" or "it works" without showing the command and its
  output.** If you could not run it, say so and say why.
- **Label claims.** `[Verified: how]` or `[Unverified: from memory]`. For
  unverified ones, say what would confirm them.
- **Measure before optimising.** Suspicions have been wrong here more than once:
  `zinit load` versus `light` made no difference (216.7 ms versus 215.2 ms), and
  `intel_lpmd` was exonerated by one line of its own config.
- **On pushback, re-check first.** Change position only on evidence, and say "I
  was wrong" plainly when that is the answer.

## 5. Verification

- `./install.sh --check` is the audit. Run it after any change. It must stay at
  **0 missing**.
- When you fix something that failed silently, add a row to the audit so it
  cannot regress unnoticed.
- `--dry-run` shows what the installer would do without doing it.

## 6. Privileges

- **`sudo` does not work in the agent's shell.** The user runs privileged
  commands themselves with the `! ` prefix.
- Give those as **short, separate** commands. Long chained ones break on
  terminal wrapping.
- Do not change `logind` or other system behaviour without asking; it needs
  root and it alters how the hardware responds.

## 7. Documentation layout

- Per-directory `README.md` files are the explanation layer. They stay **next to
  the code** they describe — `cd hypr && cat README.md` is how they get read. Do
  not centralise them into `docs/`.
- `docs/` is the Docusaurus site: user-facing, published to GitHub Pages. It is
  not agent state and not the place for decisions.
- `decisions/` holds MADR records. Write one when a choice had real
  alternatives. The ADR owns the decision, the alternatives and the
  consequences; the README keeps the mechanism and the measurements and links to
  the ADR. One fact, one owner.
- Tasks, roadmaps and known issues belong in GitHub Issues, never in Markdown.
- A README past roughly 300 lines, or covering two subjects, should be split.

## 8. Secrets

- Never commit credentials, and never put one in an issue, a PR or a commit
  message. This repository is public.
- **Treat shell history as a secret store.** A WPA password reached
  `~/.config/zsh/.zsh_history` through an `nmcli` command line. `zsh/.zsh_history*`
  is gitignored and the file is mode 0600; keep it that way.
- If you find a leaked secret, report it and stop. Do not work around it.

## 9. Scope

- Make the smallest change that satisfies the request.
- Follow the conventions already in the file you are editing.
- Do not add a dependency or a tool without a named problem it solves — see the
  8 GB constraint in section 2.
- Do not modify anything outside this repository unless asked.
