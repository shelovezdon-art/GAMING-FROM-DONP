# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Project**: ALLSTAR WORLD (multiplayer sports universe — football first)
- **Engine**: **Roblox**
- **Language**: **Luau**
- **Version Control**: Git with trunk-based development. Game code lives in
  Roblox Studio; this repo is the design, planning and QA record. Optional Rojo
  sync can bring scripts into the repo later.
- **Build System**: Roblox Studio publish (no external build step)
- **Asset Pipeline**: Roblox Studio — custom meshes, imported FBX/animations,
  Studio-generated materials

> **Engine note**: Roblox is NOT one of the three engines this template ships
> support for. The Godot, Unity and Unreal specialist agents, the engine-specific
> code-root and test-root rules, the engine reference under
> `docs/engine-reference/`, and the CI commands in `coding-standards.md` all
> **do not apply to this project** — ignore them rather than following them.
>
> What DOES apply: the design, production, QA and review skills and agents
> (game-designer, systems-designer, network-programmer, ux-designer,
> economy-designer, qa-lead, security-engineer, producer, art-director and the
> rest), the GDD section standards, and the collaboration protocol below.
>
> Roblox-specific authority model and module layout for the football core:
> `design/gdd/football-core.md` §6.
>
> **The project's own practice replaces the engine-specific parts. Read it before changing the game:**
> - `docs/practice/ROBLOX-PRACTICE.md`: where code lives (Studio, no Rojo yet), the save-to-Roblox gate,
>   scoped and reversible edits, the verification order (`loadstring` compile → evaluate without `require` →
>   harness → playtest + console → retained screenshot), measure-don't-infer, and units (1 stud = 0.35 m).
> - `docs/practice/DEFINITION-OF-DONE.md`: what a story and a sport must prove before being called done.
>   Placeholder or partial work is Partial, never Done.
> - Roblox rows/sections now exist in `.claude/docs/directory-structure.md`, `.claude/docs/run-and-observe.md`
>   and the CI note in `.claude/docs/coding-standards.md` (there is no headless CI).

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- ENGINE-REFERENCE-IMPORT: the line below is engine-specific. /setup-engine
     rewrites it to @docs/engine-reference/<engine>/VERSION.md for the chosen
     engine, so a Unity or Unreal project stops loading the Godot reference every
     session. It defaults to Godot (the template's example engine); skills that
     need the pinned version read docs/engine-reference/<engine>/VERSION.md on
     demand regardless of this import.

     ROBLOX PROJECT: the import is removed on purpose. Roblox has no pinned
     version reference here and the Godot snapshot under docs/engine-reference/
     is unused, so loading it every session would only mislead. Verify uncertain
     Roblox API behaviour in Studio rather than from memory; the current open API
     questions are listed in design/gdd/football-core.md section E. -->


## Technical Preferences

`project.yaml` at the repo root is the primary config store — engine, specialists,
naming, platform, performance, modes. Skills resolve it via `resolve_config`
(see `.claude/docs/config-resolution.md`).

`.claude/docs/technical-preferences.md` is the **legacy fallback**, read on demand
when a key is absent from `project.yaml`. It is not imported here: before
`/setup-engine` runs it is almost entirely `[TO BE CONFIGURED]` placeholders, and
after it runs `project.yaml` holds the real values.

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
  (exempt: `active.md` appends, agent memory, a subagent's new file at the path
  its orchestrating skill named; see `.claude/rules/agent-memory.md`)
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction
- A skipped or dismissed question is not an answer: act on nothing, re-ask in
  plain text and wait
- Started outside this file's folder? Warn first: hooks, deny rules and the
  ask-first mode load only when Claude Code starts here

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

Read `.claude/docs/context-management.md` on demand — it is a reference, not
session context. Two of its conventions are load-bearing and cited by name
elsewhere in the repo, so they are restated here rather than lost:

- **`production/session-state/active.md` is the session checkpoint.** The file is
  the memory, not the conversation. Read it first after any compaction, crash, or
  `/clear`.
- **Helpers in `.claude/scripts/` emit observations, never verdicts.** A script
  that scores or judges will eventually contradict a mode or override it cannot
  see. (Cited by `artifact-check.sh` and `adr-dep-graph.sh`.)
