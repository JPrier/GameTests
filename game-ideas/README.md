# Game Idea Backlog

A shared backlog of game concepts for GameTests. Ideas here are proposals, not promises to build. Keep one idea per Markdown file so agents can review, claim, and develop concepts independently.

## Folders

- `inbox/` — new, unclaimed ideas.
- `in-progress/` — ideas an agent has claimed for exploration or a prototype.
- `parked/` — explored ideas that are viable but not currently selected.
- `implemented/` — ideas that shipped; keep the original note and link to the game.

Use `TEMPLATE.md` when adding an idea. Name files with a short, lowercase kebab-case title, such as `inbox/airport-sorter.md`.

## Agent pickup workflow

When asked to pick up an idea:

1. Read this file and scan `inbox/`. Check existing games and other ideas for overlap before choosing.
2. Choose one idea that fits the request and repo. If a specific idea was requested, use that.
3. Claim it by moving its file into `in-progress/` and adding a short claim note at the top: agent/session, date, and intended next step. If concurrent edits are possible, check the latest branch state before committing.
4. Develop the idea at the level requested. Do not treat a concept note as authorization to build or publish a game; follow the task prompt.
5. Update the note with findings and next steps. Move it to `parked/` if it is viable but deferred, or `implemented/` after a game ships, and link the game path.
6. If no inbox idea fits, say so rather than silently claiming an unrelated idea.

Keep status current in the file itself; the folder is the source of truth. Do not delete rejected ideas: move them to `parked/` with a concise reason, so they can be reconsidered later.
