# Project Agent Contract

<!-- brain:begin agents-contract -->
Use this file as a Brain-managed project context entrypoint for `editor-thingy`.

Read the linked context files before substantial work. Prefer the `brain` skill and `brain` CLI for project memory, retrieval, and durable context updates.

## Table Of Contents

- [Overview](./.brain/context/overview.md)
- [Architecture](./.brain/context/architecture.md)
- [Standards](./.brain/context/standards.md)
- [Workflows](./.brain/context/workflows.md)
- [Memory Policy](./.brain/context/memory-policy.md)
- [Current State](./.brain/context/current-state.md)
- [Policy](./.brain/policy.yaml)

## Required Workflow

1. If no validated session is active, run `brain session start --task "<task>"`.
2. If a session is already active, run `brain session validate` before substantial work.
3. Read this file and the linked context files needed for the task.
4. Compile the smallest justified working set with `brain context compile --task "<task>"`.
5. Retrieve project memory with `brain find editor-thingy` or `brain search "editor-thingy <task>"` when the compiled packet is not enough.
6. Use `brain edit` for durable context updates to AGENTS.md, docs, or .brain notes.
7. Use `brain session run -- <command>` for required verification commands.
8. Finish with `brain session finish` so policy checks can enforce verification and surface promotion review when durable follow-through is still needed.
<!-- brain:end agents-contract -->

## Local Notes

- Primary app entrypoint: `main.odin`.
- Core runtime code lives under `core/`.
- Current renderer path on Linux uses SDL3 + Vulkan.
- Shader sources live in `core/shaders/`.
- Generated shader binaries `*.spv` are currently needed before `odin run .` succeeds.
- Odin vendor STB native libs may also need compilation on a fresh toolchain install.
- Layout hotkeys:
  - Plain `S` toggles between editor-only and split.
  - `Ctrl+S` toggles Codex fullscreen and restores the previous non-fullscreen layout.
