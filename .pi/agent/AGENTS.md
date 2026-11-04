# Global rules (pi)

## Plans

Work that outlives one session is driven by a **plan file**, so a new
session resumes from the plan instead of from a long chat history.

- Plans dir: the nearest `plans/` walking up from the cwd (e.g.
  `~/az/plans/`); with none on the way up, `~/.agents/plans/`. One task
  per file, `<slug>.md`; closed plans move to `done/` inside that dir.
  These are the user's own plans: read, create and update them freely.
- Each plan starts with a header:

  ```
  status: active | paused | blocked
  updated: YYYY-MM-DD
  next: <one concrete next step>
  ```

  Body: goal, decisions (with the why), steps as `- [ ]` checkboxes,
  dead ends ("tried X — failed because Y").
- Session start: when the user names a plan, read that one. Otherwise,
  for continuing work, list the headers of active plans and ask which
  one — read only the chosen file.
- Task longer than a couple of steps: write the plan first, then work.
- After each finished step, update the plan: tick steps, record
  decisions and dead ends, refresh `updated` and `next`. A step is done
  when the plan alone is enough for a fresh session to continue.
