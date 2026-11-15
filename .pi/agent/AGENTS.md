# Global Rules (Pi)

## Language and Communication

- Respond in Russian by default. Write code, identifiers, and filenames in English; the language of
  comments and docstrings follows the project (see Comments and Docstrings).
- Keep explanations clear, concise, and practical.
- When explaining technical concepts, prefer examples over abstract descriptions.

## AGENTS.md Files

- **Never delegate a rule to another `AGENTS.md`.** No "see `../AGENTS.md`", no "details live in
  `~/.pi/agent/AGENTS.md`": an agent may read only the nearest file, so the pointer dangles where it
  matters. Either the rule applies here — state it in full, in this file's own words — or it does not
  apply here — then say nothing about it.
- **Naming a file to read is not the same as delegating a rule.** "Each submodule ships its own
  `AGENTS.md`; read it before changing code" is navigation and stays. "Suppression rules — see the
  global file" is delegation and goes.
- **No duplication for its own sake.** A rule stated one level up is not copied down verbatim; the
  nearest file carries only what its own scope needs, written out rather than referenced.

## Comments and Docstrings

First determine the documentation language of the project: look at docstrings and comments in
neighbouring modules, its `AGENTS.md`, its README — and write in that language. A Russian docstring in
an English package is foreign matter; English in a Russian one looks like a patch. For a new project
with no established style — Russian. Latin technical names (`payload`, `Structure`, `CANDIDATE_CAP`)
stay Latin either way.

Language-agnostic rules:

- **A comment explains "why", not "what".** What the line does is visible in the code; only the
  reason, the order of operations and the trap are worth writing down.
- **A docstring states the purpose** — it does not restate the signature and types.
- **Verify claims.** "Enabled by default" must match the code and the config, not the memory of how
  it used to be.
- **Split a dense function into sections**: a blank line and a one-line header each, so it can be
  skimmed diagonally. Section headers are the exception to "why not what" — they are the table of
  contents. **Do not number them** (`# 1. …`, `# 2. …`): a new step in the middle renumbers the rest,
  and any "see step 3" left in prose rots on the spot. Numbers are allowed only where order is the
  point and you never reference them elsewhere.
- **Justify every suppression.** Any switch that silences a linter or a type checker — `# noqa`,
  `# type: ignore`, `@ts-expect-error`, `// eslint-disable-next-line`, `//nolint`, `# rubocop:disable`,
  whatever the language calls it — carries a short reason, on the same line or the line above: without
  it nobody can tell whether the exception is still required, and a stale one is never removed.
- **Refer to code by function or module name** (`_list_payload`, `audit_delta.py`), never by line
  numbers ("lines 100–120") — those rot with the first edit.
- **Decode a domain term once**, where it first appears.
- **No history in the code.** No "before/after" snippets, no branch names, no ticket ids
  (`AS-2545`, `#1234`) in comments or docstrings: the reader has no way to check them, they name
  things that may be gone, and they outlive the reason they were written for. A comment describes
  the current rule; the *why* of the change belongs to the commit message and the plan.

When the text is Russian — published prose, not a chat message:

- **One concept — one term.** "Поиск", "фильтр" and "запрос" must not take turns meaning the same
  thing; a Latin identifier is quoted once (`CANDIDATE_CAP`) and then used unchanged.
- **Typography:** «ёлочки» for quotes, a long dash with spaces and a hyphen without, a non-breaking
  space before a dash and between a number and its unit, one space after a comma, no double spaces;
  «ё» and spellings stay consistent across the file.
- **No transliteration or calques.** Either the Latin term as is, or a Russian equivalent: "кап" →
  "предел `CANDIDATE_CAP`", "галка" → "явная выдача", "статы" → "счётчики", "дёрнуть" → "вызвать",
  "прокинуть" → "передать".
- **Do not decline Latin words with Russian case endings** ("капом", "фильтром из `filter`") —
  rephrase: "ограничивает выдачу пределом `CANDIDATE_CAP`".
- **Python docstrings**: the summary starts on the line with the opening `"""`, the closing `"""`
  goes on its own line, the first sentence is in the third person ("Собирает…", "Возвращает…").

### The essence

A comment says what the code cannot: why this way, which invariant holds, what breaks if changed. The
shape is PEP 257's — a one-line summary, a blank line, the body; the summary must stand alone in an
index or a tooltip. Delete the comment: if nothing non-obvious is lost, delete it for good. A comment
that contradicts the code is worse than none, so it changes in the same commit.

## Learning and Development

I am learning and exploring the following technologies:

- Programming languages: Go, Python, JavaScript/TypeScript, GDScript, Lua, Bash, PowerShell, C, and SQL.
- Game engine: Godot.
- 2D graphics and digital painting: Krita.
- 3D modeling: Blender.

The following learning-specific rules apply **only to projects and directories explicitly designated for learning**, such as `learn/`. They do not apply to regular projects or production code unless explicitly requested.

- In learning contexts, do not provide complete solutions by default.
- Teach through explanations, incremental hints, guiding questions, and code reviews.
- Provide complete implementations only when explicitly requested.
- Point out mistakes and explain the reasoning behind corrections rather than silently fixing everything.
- When explaining concepts or providing learning materials, prefer authoritative sources and official documentation.
- Verify that cited sources exist, are accessible, and support the information being presented.

## Planning and Execution

- For tasks involving more than a couple of steps, create or update a plan file before starting implementation. Create a separate `<slug>.md` file for each task.
- Use the nearest `plans/` directory found by walking upward from the current working directory. If none exists, use `~/.agents/plans/`. These are user-owned plans; read, create, and update them freely.
- After implementing a feature or making significant changes, run a separate subagent with the ["code-review"] skill to perform an independent review.
- Fix all critical and major issues identified during testing and review before considering the work complete.
- After completing implementation, testing, fixes, and review, explain how to verify the changes.

### Working with Plans

- If the user explicitly names a plan, read that plan first.
- Otherwise, when continuing existing work:
  1. List the headers of all active plans.
  2. Ask the user which plan to resume.
  3. Read only the selected plan.
- Do not load every plan's full contents unnecessarily.
- Every plan must follow this structure:

  Start with this YAML header:

  ```yaml
  status: active | paused | blocked | done
  updated: YYYY-MM-DD
  next: <one concrete next step>
  ```

  The body should contain:

  - **Goal:** What needs to be accomplished.
  - **Decisions:** Important decisions and the reasoning behind them.
  - **Steps:** Actionable tasks represented by `- [ ]` checkboxes.
  - **Dead ends:** Failed approaches and why they failed.
- Move completed plans into the `done/` subdirectory within the same plans directory.
- For tasks involving more than a couple of steps, create or update the plan before implementation.
- After each completed step:
  - Mark the corresponding checkbox as complete.
  - Record relevant decisions and their reasoning.
  - Document failed approaches and why they did not work.
  - Update the `updated` date and `next` action.
- Keep the plan sufficiently detailed for a fresh session to continue without access to the previous conversation.
- A step is complete only when the plan accurately reflects the current state of the work.

### Completing a Plan

- Verify the result and run relevant tests.
- Ensure all applicable steps are checked off.
- Move the completed plan into `done/`.
- Do not mark a plan as completed while unresolved issues remain.

## Testing

- For Python projects, use `pytest` when available.
- Python and JavaScript: prefer parameterized tests.
- Go: prefer table-driven tests.
- Use descriptive test case names.
- Run relevant tests after making changes.
- If tests fail, investigate and fix the underlying issues rather than treating the task as complete.
- Never claim that tests passed unless they were actually executed successfully.

## Safety and Permissions

Never perform the following actions without explicit confirmation:

- `git push` or any other operation that publishes changes remotely.
- Deleting files or directories.
- Editing `.env` files.
- Docker commands that delete or interrupt state (`rm -f`, `kill`, `stop`, any `prune`, `rmi`, `volume rm`, `compose down -v`): state what will be lost first; see the `docker-destructive-guardrails` skill.

Other local changes can be made as needed to complete the task.

## Knowledge and Research

When looking for information, follow this priority order:

1. Local wiki: `~/Wiki/index.md`.
2. Local documentation.
3. The internet.

- Prefer existing local knowledge over external sources.
- Prefer authoritative sources, such as official documentation, specifications, standards, and primary sources.
- Provide sources for factual claims and technical recommendations.
- Verify that cited sources actually exist and that their URLs are valid and accessible.
- Ensure that each source supports the specific claim it is cited for.
- Never invent URLs, references, documentation, or citations.
- Distinguish verified facts from assumptions and recommendations.
- If a source is unavailable or insufficient, proceed to the next source in the priority order.

