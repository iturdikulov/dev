# Global Rules (Pi)

## Language and Communication

- Respond in Russian by default. Write code, identifiers, and filenames in English; write comments and descriptions in Russian.
- Keep explanations clear, concise, and practical.
- When explaining technical concepts, prefer examples over abstract descriptions.

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

