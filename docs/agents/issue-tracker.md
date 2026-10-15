# Issue tracker: GitHub

Issues and specs live in z0n/plasma-applet-display-config-switcher's
GitHub Issues. Use `gh` from this checkout.

- Publish: `gh issue create --title "..." --body-file <file>`
- Read: `gh issue view <number> --json number,title,body,labels,comments`
- List: `gh issue list --state open --json number,title,body,labels`
- Comment: `gh issue comment <number> --body-file <file>`
- Label: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding

A map is an issue labelled `wayfinder:map`. Link child tickets using
GitHub sub-issues; if unavailable, use a task list in the map and
`Part of #<map>` in each child.

Use `wayfinder:<type>` labels (`research`/`prototype`/`grilling`/`task`).
Represent blockers with native issue dependencies, falling back to
`Blocked by: #<number>` in the child body.

Choose the first open, unassigned child in map order whose blockers
are all closed. Claim with `gh issue edit <number> --add-assignee @me`.
On resolution, comment with the answer, close the ticket, and append
a summary and link to the map's Decisions-so-far.
