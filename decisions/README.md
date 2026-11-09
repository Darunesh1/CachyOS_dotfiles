# Architecture decisions

Records follow [MADR](https://adr.github.io/madr/) 4.0.0. Do not invent another
format.

These live at the repository root rather than under `docs/` on purpose:
`docs/` is the Docusaurus site, and `.github/workflows/deploy.yml` triggers on
`paths: docs/**`, so an ADR there would rebuild and redeploy the website every
time a decision was recorded.

## When a decision deserves a record

When real alternatives existed and the choice is not obvious from reading the
code. Measurements, rejected options and the cost of being wrong go here.

A record that just restates what the code does is not worth writing.

## Ownership — read before adding one

The ADR owns the **decision, the alternatives and the consequences**. The
per-directory `README.md` keeps the **mechanism and the measurements** and links
here. One fact, one owner: if a README already argues the choice, move that
argument into the ADR and leave a link behind.

## Writing a record

1. Copy [0000-template.md](0000-template.md) to `NNNN-short-title-with-dashes.md`.
2. Use the next unused four-digit number.
3. Fill in the sections and remove the optional ones you do not need.
4. Set `status` in the record's own front matter: proposed, rejected, accepted,
   deprecated, or superseded by ADR-NNNN.
5. Add one row to the register below.

## Changing a decision

- Never edit an accepted record to change its meaning.
- Write a new record and set the old one's status to `superseded by ADR-NNNN`.
- Status lives only in the record. The register does not repeat it.

## Register

| No | Title | Link |
|---|---|---|
| 0000 | Template (not a decision) | [0000-template.md](0000-template.md) |
| 0001 | Keep systemd-oomd, but move its monitoring and prefer `avoid` | [0001-oomd-avoid-over-omit.md](0001-oomd-avoid-over-omit.md) |
| 0002 | Drop the `completion` zsh-autosuggest strategy | [0002-drop-completion-suggest-strategy.md](0002-drop-completion-suggest-strategy.md) |
| 0003 | Drive Ventoy through its web UI, not the GTK GUI | [0003-ventoy-web-ui.md](0003-ventoy-web-ui.md) |
| 0004 | Let the brightness key reach zero, restore a floor on wake | [0004-brightness-zero-with-wake-floor.md](0004-brightness-zero-with-wake-floor.md) |
| 0005 | One lock owner, a replaceable lock, and an upstream idle staircase | [0005-single-lock-owner-and-idle-staircase.md](0005-single-lock-owner-and-idle-staircase.md) |
| 0006 | External displays mirror by default; rescue the panel by reloading | [0006-mirror-by-default-and-panel-rescue.md](0006-mirror-by-default-and-panel-rescue.md) |
