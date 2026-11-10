# Performance

## Removed work

- Removed the permanent `C_Timer.NewTicker(0.5, GcdIcons)` child-tree scan.
- Removed the bounded two-second extras polling loop. Optional modules now initialize from factory
  activity and the login flush.
- Removed generic recursive child-level scans on every styled frame show.
- Prevented completed window watches from scheduling zero-delay callbacks on later shows.
- Cached the resolved action-bar border style instead of repeatedly walking EllesmereUI databases
  and allocating style tables.
- Reused tint state and skipped unchanged tint and visibility updates.
- Reused deferred callback closures in the cast-bar, GCD, and EUI-window paths.
- Generic elements install show/size fallback hooks only if their first deferred construction-time
  styling attempt finds them unsized; normally constructed frames retain no such callbacks.
- Window candidates receive one coalesced construction-time callback, matching the stable window
  discovery path; hidden candidates exit without styling and are handled by their actual `OnShow`.
- Stable GCD pools perform only a child-count comparison on player casts and allocate no timer;
  child traversal occurs only when the pool grows and uses no temporary table.
- Turning the master border feature off skips the login deferral, action-bar database resolution,
  pending-edge drain, and supported-window discovery.

## Module and disabled-feature behavior

Configuration is validated once. Disabled modules are never initialized, and therefore install no
optional hooks, events, borders, textures, or discovery work. When Naowh Forever itself is disabled,
only independently enabled EllesmereUI window/bag integrations may install their narrow hooks and
one-time login flush. `PLAYER_LOGIN` unregisters itself; `ADDON_LOADED` remains as a dormant,
event-driven listener so supported load-on-demand integrations can initialize later in the session.

## Remaining runtime callbacks

- `UNIT_SPELLCAST_SUCCEEDED`: a player-only guard performs one child-count comparison. It schedules
  a coalesced GCD scan only when the upstream icon pool grew.
- Show/hide hooks: synchronize borders whose upstream visibility can change. Cached state makes
  duplicate notifications no-ops.
- Size/point hooks: limited to elements whose geometry can actually change (initially unsized
  pooled frames, the focus cast bar, GCD tracker, and EUI window hosts).
- `C_Timer.After(0, ...)`: one-shot, deduplicated deferrals used only to let an in-progress frame
  factory or layout operation finish. There are no repeating timers.

## Static comparison

| Metric | Original | 2.0.0 |
|---|---:|---:|
| Permanent `OnUpdate` scripts | 0 | 0 |
| `C_Timer.NewTicker` call sites | 2 | 0 |
| Idle GCD scans per minute | 120 | 0 |
| Generic border tree scan on every show | Yes | No |
| Border-style DB lookup/table creation on visibility or tint updates | Yes | No |
| Unchanged visibility/tint API writes | Possible | Guarded |

The scan-rate comparison follows directly from the removed 0.5-second ticker; it is not an in-game
CPU benchmark. WoW-client profiling and visual/taint validation remain necessary.

Restricted Blizzard aura-container buttons are styled only during their permitted
`initializeFrame` phase. A module-specific constructor post-hook creates one independent overlay;
afterward pooled reuse and visibility inheritance require no Lua work. The shared factory is never
replaced, and no script is attached to the aura button.

The settings panel is lazy and event-driven. While closed it has no `OnUpdate`, timer, registered
event, frame traversal, or synchronization callback. Changes are persisted immediately and applied
only after `/reload`, preserving the addon's immutable runtime styling state.

Granular toggles are initialization gates, not a generic runtime dispatcher. Disabled AuraIcon and
GCD features install neither their secure constructor hook nor spell event; disabled item, HUD,
window, font, color, and EllesmereUI-window features omit their corresponding wrappers/callbacks.
The disabled GCD feature is also excluded from generic and HUD fall-through styling, so its pooled
combat frame tree receives no skin work.
