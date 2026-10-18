# Entity programs

[Русский](entity-programs.md)

The assistant reads `creation.program_schema`, checks its source with `creation.validate_program`, and proposes an object with a `program` field. The player reviews geometry and logic together. A `behavior` project with `object_id` can attach or revise a program on an existing object. When `id` equals `object_id`, it replaces that object's program without recreating its model. Existing state values are retained by default.

Programs use a bounded JSON interpreter, with no GDScript execution. They compose new rules from the available operations; they cannot invent missing engine capabilities.

## Counter example

```json
{
  "version": 1,
  "state": {"count": 0},
  "events": [{"name": "pulse", "type": "tick", "seconds": 1}],
  "handlers": {
    "pulse": [{"set": "state.count", "value": {"op": "+", "args": [{"get": "state.count"}, 1]}}]
  },
  "ui": {"fields": [{"label": {"ru": "Импульсы", "en": "Pulses"}, "path": "state.count"}]}
}
```

`state` persists with the campaign. `event` contains event data; `self` contains the object ID and body. Variables declared by `let` or a call's `store` are available directly by name and through `local.name`. These temporary variables exist only within a handler.

## Events, expressions and statements

- `tick` uses scene seconds, including while the calendar is paused. `day_change` follows the actual game day.
- `interaction` runs when a `ui.buttons` button names that event.
- `plane_cross` and `sphere_enter` detect actual ship crossings or volume entry. The current `dyson` adapter requires Dyson Sphere Program. Centres, normals and radii are object-relative kilometres. The assistant writes hull-clearance, energy and other conditions.
- Statements: `let`, `set`, `if`/`then`/`else`, `for`/`in`/`do`, `while`/`do`, `call`, `return`. Assignment is limited to `state.*`; optional `key` provides a computed dictionary key.
- Expressions: `get` with optional `default`, `literal`, arithmetic, comparisons, logic, `min`, `max`, `clamp`, `len`, `concat`, `at`, `vadd`, `vscale`, `dot`, `distance`. Read-only host queries may also appear in expressions.

The complete field requirements and examples are returned by `creation.program_schema`, so the model can discover the exact format.

## General world operations

| Operation | Result |
| --- | --- |
| `body.read` | Actual native population, colony status and climate of a discovered body |
| `body.set` | Changes climate parameters on an approved artificial body or shell |
| `actor.read`, `actors.list` | Actual player ship data, including health, cargo and position |
| `actor.spawn` | Produces an actual Dyson Sphere Program ship; the program defines costs, queues and timing |
| `actor.move` | Relocates the same ship to a point near a discovered body; retains cargo, troops, health and owner, cancels previous orders |
| `actor.set` | Changes health or shields within native maxima |
| `object.read` | Position, axes and definition of an approved object |
| `object.move` | Moves an authored object and persists its transform |
| `object.damage` | Removes a bounded region of a destructible voxel object |
| `resource.add` | Changes existing native resource stock in an actual colony |
| `resource.read` | Reads actual stocks for cost and power checks |
| `ui.message` | Writes a program log message |

`actor.move.position_km` is body-centred, in world axes. Internally the held pose and heading persist in the body frame, so scene reorientation on load retains the same planet-relative location. To calculate an exit-relative offset, read `object.read`, scale its chosen axis by the distance, then add its position. The runtime does not assume an object is a gate: the program defines the sensor, conditions and destination.

The separate `ship_flight` project moves an actual ship along object-relative 3D waypoints. The route controls movement; the program handles the object's reaction. `creation.focus` and the object card focus the camera on the object itself.

## State and faults

The card shows fields, buttons and a program enable switch. `creation.program_status` returns actual state, completed-operation receipts and an exact error with its source path. Faults are also included in the creating chat's context through `workspace.program_feedback`.

`creation.actors` lets the assistant independently observe actual adapter ships: native ID, position relative to a discovered reference body, cargo and health. This is separate from the scheduled passenger transports returned by `ships.read`. Observation requires no program creation or world changes.

A fault stops that program. Completed world actions are not rolled back. Fixes require another reviewed proposal; successful mutations should not be replayed to repair an error.

Each program supports 8 events, 12 fields, 12 buttons, and up to 64 KiB each of source and state. A handler has a 4096-instruction budget; array loops allow 64 items. The shared event queue holds up to 256 entries and dispatches up to 16 handlers per frame. Programs cannot access files, networks or arbitrary engine methods.


Legacy `ui.workspace.columns` defines one or two columns of `choices`, `fields`, `list`, `progress` and `actions` sections. See `creation.program_schema.workspace` for exact bounds and fields. A choice has localized title/description and a plain `value` payload. An action with `inputs:["design"]` invokes its approved interaction with the selected payload at `event.input.design`. Queue contents, durations, stock checks and world effects belong to the program. `creation.open_controls` opens an approved workspace without executing an action.


## Composable UI

Use `ui.workspace.layout` for a nested widget tree described in `creation.program_schema.workspace.tree`. Legacy `columns` remain supported; choose one representation. Containers and inputs compose freely. Buttons send typed drafts to their program interaction under `event.input`; handlers implement the actual effects and validation. Live tables read arrays of maps from state. Visibility and enabled bindings read state only. Text is localized `{ru,en}` and widgets inherit the native theme. Bounds: 128 nodes, nesting depth 8, 24 children per container, 64 visible table rows. These are supported widgets, not unrestricted native-code execution.

Inputs support text, textarea, number, slider, toggle and select. Buttons may add a static `payload` for a shared handler; current draft inputs take precedence. All labels follow the game language, falling back to English, and a language change preserves drafts.

Program validation returns `program_ref`. Reuse it in a project definition instead of resending source. The exact source is copied into an ordinary player-reviewed proposal. Up to 16 validated programs are cached in memory; references expire on campaign reload.
