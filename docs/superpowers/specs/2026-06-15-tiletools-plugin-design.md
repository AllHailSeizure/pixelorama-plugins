# TileTools — Pixelorama Extension Design

## Overview

A Pixelorama extension for tileset workflows. Adds a **Tile Select** tool that divides the canvas into a configurable grid and provides grid-snapped selection and selection-scoped tiling.

**Motivation:** Working with tilesets in Pixelorama requires manually drawing precise rectangle selections and creating separate canvases for tiling. TileTools eliminates both pain points.

## Target Platform

- Pixelorama 0.11.x+ (Extensions API version 4)
- Godot Engine (GDScript)
- Exported as `.pck` file

## Plugin Structure

```
TileTools/
├── extension.json
├── Main.tscn
├── Main.gd              # Entry point, registers/unregisters the tool
├── TileSelectTool.gd    # Tool logic: input handling, grid math, selection
└── TileSelectSettings.gd # Tool settings UI (grid width/height)
```

### extension.json

```json
{
  "name": "TileTools",
  "display_name": "TileTools",
  "description": "Grid-based tile selection and selection-scoped tiling for tileset workflows",
  "author": "AllHailSeizure",
  "version": "0.1",
  "supported_api_versions": [4],
  "license": "MIT",
  "nodes": ["Main.tscn"]
}
```

## Feature 1: Tile Select Tool

### Grid System

- Canvas is divided into a fixed grid anchored at origin (0,0).
- Default cell size: 20x20 pixels.
- Cell size is adjustable via tool settings (width and height independently).
- Grid overlay is drawn on the canvas while the tool is active and while a Tile Select selection exists (so it remains visible during drawing with other tools).

### Selection Behavior

| Input | Behavior |
|---|---|
| Click | Select the grid cell under the cursor. Replaces existing selection. |
| Click + drag | Freeform — every cell the cursor enters is added. Replaces existing selection. |
| Shift + click | Additive — adds to existing selection using the same click rules. |
| Shift + click + drag | Additive. Freeform by default. While shift is held during drag, selects the rectangle defined by the extremities of mouse movement during the shift-held period. |
| Click without shift | Clears previous selection, starts fresh. |

### Selection Mechanics

- Selections use Pixelorama's native selection/marching-ants system so that cut, copy, paste, delete, and all other selection operations work as expected.
- Moving selected content snaps to the grid (move delta rounds to nearest grid increment).
- Multiple rectangles can be composed via repeated shift+click/drag operations.

## Feature 2: Selection-Scoped Tiling

### Behavior

When a Tile Select selection exists, any drawing tool wraps within the bounding box of the selection — identical to Pixelorama's canvas tiling, but scoped to the selection bounds instead of the canvas edges.

- Wraps in all four directions (up, down, left, right).
- Active automatically when a Tile Select selection exists; no separate toggle.
- Deselecting disables the tiling.

### Bounding Box Rules

- Single cell selected: tiling wraps within that cell's bounds.
- Multiple cells selected (contiguous or not): tiling wraps within the full bounding box of all selected cells.

## Implementation Strategy

### Approach: Custom Tool (Approach A)

Register Tile Select as a custom tool in Pixelorama's toolbox via the Extensions API. It appears alongside existing selection tools with its own settings panel.

### Tool Registration

- `Main.gd._enter_tree()` registers the tool.
- `Main.gd._exit_tree()` unregisters and cleans up.
- If the Extensions API does not support full tool registration, fall back to input event interception with a toolbar button to activate/deactivate.

### Draw Pipeline Interception (for tiling)

- Hook into the drawing pipeline to detect strokes outside the selection bounding box.
- Wrap stroke coordinates back into the bounding box using modulo arithmetic on the selection bounds.
- Must work with any drawing tool (pencil, brush, line, shape, eraser, etc.).

### Grid Snap (for move)

- Intercept move behavior when a Tile Select selection is active.
- Snap the move delta to the nearest grid cell increment.

## Risks and Unknowns

1. **API surface for tool registration** — The Extensions API may not expose enough to register a proper custom tool. Needs Pixelorama source inspection to confirm. Fallback: input interception with a toggle button.
2. **Draw pipeline interception** — If hooking into the draw pipeline isn't feasible, tiling may need a different approach (e.g., operating on a hidden buffer and stamping results back).
3. **Compatibility with all drawing tools** — Tiling needs to wrap strokes from pencil, brush, shapes, lines, etc. Each may handle coordinates differently.

## Out of Scope (for now)

- Tile palette/library management
- Tilemap export formats
- Auto-tiling / rule-based tile placement
- Animation frame integration
