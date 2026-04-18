# Project Architecture

<!-- brain:begin project-doc-architecture -->
Use this file for the structural shape of the repository.

## Architecture Notes

- Keep repo boundaries explicit and document key entrypoints in this file.
- Update this file when runtime architecture or integration boundaries change.
<!-- brain:end project-doc-architecture -->

## Local Notes

- SDL3 owns windowing and event intake.
- Vulkan backend currently renders colored fullscreen panes per view.
- Shader sources live in `core/shaders/`; pipeline creation expects compiled SPIR-V artifacts.
