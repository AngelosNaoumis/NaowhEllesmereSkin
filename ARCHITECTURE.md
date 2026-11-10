# Architecture

## File structure

- `Core/Namespace.lua` owns addon identity, diagnostics, and the small module registry.
- `Core/Config.lua` owns defaults, SavedVariables migration, validation, and bulk operations.
- `Core/Utils.lua` owns allocation-free shared checks and color helpers.
- `NaowhEllesmereSkin.lua` is the runtime styling engine: theme integration, shared border engine,
  factory interception, concrete non-aura skin features, and native panel construction.
- `Skins/Auras.lua` owns the security-sensitive PvP/Raid aura lifecycle.
- `Options/Settings.lua` owns the `/nes` settings entry point.
- `Core/Init.lua` is the only event bootstrap and loads last.

Files receive the private table passed by WoW as the second chunk argument. Nothing is added to the
global namespace except SavedVariables and WoW's required slash-command identifiers.

## Initialization lifecycle

The TOC loads namespace, configuration, utilities, the runtime engine, feature modules, options,
and finally bootstrap. `ADDON_LOADED` validates SavedVariables and registers the native settings
category. Naowh skin activation occurs only after the real `NaowhForever` namespace exists. The
supported EllesmereUI-window border integration is independent and may initialize without Naowh;
all Naowh factory hooks and modules remain dormant when Naowh is disabled.

`ADDON_LOADED` remains registered after login solely for supported load-on-demand integrations.
It performs no polling and does no work between addon load events; every target path is idempotent.

At `PLAYER_LOGIN`, enabled border integrations resolve and cache the EllesmereUI action-bar border
style, then drain any one-time construction queue. Repeated addon events are harmless because every
factory hook and feature module has an idempotent guard.

## Configuration

`Core/Config.lua` is the single source of truth for defaults and independently gated feature keys.
Migration fills missing or wrongly typed values and clamps numeric values. Existing flat
SavedVariables keys remain unchanged for backwards compatibility. Settings mutate only the saved
table; every visual change requires `/reload`.

## Styling and borders

The runtime border engine centralizes edge creation, level selection, tinting, visibility following,
and weak-key frame caches. Factory wrappers pass concrete frames to this engine. A border is created
once, and later callbacks update only state that the upstream addon genuinely changes.

Window shells, item plates, generic elements, HUDs, focus cast bars, top bars, GCD icons, and
EllesmereUI windows remain explicit because their upstream lifecycles differ. This avoids a generic
dispatcher or repeated frame-tree scanning.

## Aura module

`Skins/Auras.lua` never replaces `Shared.AuraIcon`. After `NaowhForever_Combat` loads, it securely
post-hooks the finished `PvP.Icon.New` and `RaidDebuffs.Icon.New` methods. During Blizzard's allowed
initialization phase, the runtime creates one non-interactive child overlay. Weak-key caches prevent
duplicates without retaining retired pooled buttons. No script is attached to a restricted aura
button, and pooled reuse needs no scan or reapplication.

## Extending the addon

For an independent feature:

1. Add its default and bulk-toggle key in `Core/Config.lua`.
2. Add the matching native control and reload-only description.
3. Create `Skins/<Feature>.lua`, register it with `NS:RegisterModule`, and expose one idempotent
   `Initialize` method.
4. Add the file before `Core/Init.lua` in the TOC.
5. Gate every hook/event/allocation at initialization and reuse the runtime border helper when the
   standard edge is appropriate.

Keep specialized lifecycle logic explicit. A module should detect a frame, style it once, cache the
result with weak keys, and then stop unless a real show, geometry, tint, or pool-growth event occurs.
