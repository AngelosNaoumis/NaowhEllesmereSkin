# Changelog

## 2.1.13

- Reduced per-window memory allocation by sharing the unchanged Naowh window `OnShow` callback
  instead of creating an identical closure for every discovered window.
- Completed a conservative performance audit without changing the working window, aura, border,
  GCD, settings, or integration behavior.

## 2.1.12

- Restored the known-good 2.1.3 window discovery and border pipeline exactly: secure backdrop
  observation, Naowh window candidate scheduling, shell backdrop, and action-bar-style window edge.
- Kept later unrelated safety gates for restricted aura buttons, disabled GCD integration, and
  hidden-frame state preservation.
- Removed the experimental native shell-border path from 2.1.10.

## 2.1.11

- Simplified Naowh window discovery by removing the redundant `Parts.Window` factory replacement.
- Retained the shared backdrop paint interception and the reliable shell-owned window border.
- Reduced coupling to Naowh Forever internals without adding scans, polling, or recurring work.

## 2.1.10

- Fixed missing borders on Naowh feature windows. The EllesmereUI shell now owns its documented
  native window border instead of drawing a separate border on the underlying Naowh frame where
  the shell host could obscure it.
- Preserved the granular Naowh window-border toggle and removed the redundant per-window custom
  border application and child-level traversal.

## 2.1.9

- Fixed Naowh Forever feature windows not receiving the EllesmereUI shell by watching the shared
  window factory directly. This covers BiS, Dungeon Journal, Discovery, Gear Sets, Group Finder,
  Group Inspect, Instance Tracker, Trainer Planner, saved rewards, junk lists, blessings, and other
  windows built lazily by optional modules.
- The fix is creation/show driven and adds no polling or idle CPU work.

## 2.1.8

- Restored Naowh window discovery for metatable-backed `Parts.Backdrop:Paint()` instances. The
  secure table-method hook introduced in 2.1.5 did not reliably fire for these windows in-client,
  leaving Gear Sets, BiS, Training Planner, Discovery, utilities, and other Naowh windows unskinned.
- The restored class wrapper remains creation/paint-driven with no polling or idle processing.

## 2.1.7

- Fixed PvP Aura and Raid Debuff border creation attempting to branch on a secret `IsShown()`
  boolean inherited from Blizzard's restricted aura container.
- Aura overlays now bypass normal hidden-frame restoration, while other border targets safely
  ignore secret visibility values if Blizzard exposes one.

## 2.1.6

- Made the GCD tracker toggle a hard module-level gate. When disabled, generic and HUD border
  paths skip the tracker root and all descendants, and no GCD pool discovery, cast event, timer, or
  GCD-specific layout work is installed.

## 2.1.5

- Replaced the Naowh theme and backdrop method wrappers with secure post-hooks, preserving upstream
  return values and reducing compatibility risk.
- Skip deferred window evaluation for hidden candidates until their real `OnShow` lifecycle event.
- Skip GCD scan timers entirely when a successful cast did not grow the upstream icon pool.
- Removed temporary child/region tables from GCD, border-level, window, and aura traversals.
- Retain the event-driven `ADDON_LOADED` listener after login so late-loaded Naowh Combat and
  EllesmereUI integrations initialize correctly without polling.
- Fixed independent bag-window gating when general EllesmereUI-window borders are disabled.

## 2.1.4

- Added an independent setting for borders on EllesmereUI bag, reagent-bag, and bank windows.
- Discover these stable frames once when EllesmereUI Bags loads; no scanning, polling, or idle work.

## 2.1.3

- Preserve a frame's hidden state while applying an EllesmereUI border. EllesmereUI's solid-border
  API shows its target frame, which could expose inactive Flight/Craft timers, HUD movers, and other
  frames styled during construction.

## 2.1.2

- Decoupled supported EllesmereUI-window borders from Naowh Forever activation. EllesmereUI window
  skinning remains available when Naowh is disabled, while all Naowh-specific hooks stay dormant.

## 2.1.1

- Fixed the `SyncShown` forward declaration so `ApplyEdge` resolves the local function instead of
  attempting a nil global call. This affected all border types, including PvP/Raid aura overlays.

## 2.1.0

- Removed accidental global runtime functions and an unused shared helper.
- Coalesced duplicate deferred window evaluation callbacks.
- Generic frames now receive permanent show/size hooks only when their first post-construction
  styling attempt finds them genuinely unsized.
- Restricted focus cast-bar edge metadata collection to actual cast-bar parts when general borders
  are disabled.
- Specialized item and HUD factory callbacks with immutable initialization flags.
- Disabled border styling now skips the login timer, action-bar style resolution, edge queue work,
  and EllesmereUI/Friends window discovery entirely.
- Reused one aura constructor callback across staged Combat module initialization.

## 2.0.0

- Added a shared addon namespace, centralized configuration/migration service, reusable utilities,
  a dedicated bootstrap, and a separate slash-settings entry point.
- Moved the security-sensitive PvP/Raid aura integration into its own independently gated module.
- Configuration defaults, bulk feature operations, and numeric validation now have one owner.
- The addon remains dormant when Naowh Forever is disabled and retains reload-only configuration.
- Added README documentation and expanded architecture/performance guidance.

## 1.4.0

- Remains fully dormant when Naowh Forever is disabled: no skin hooks, delayed edge work, frame
  discovery, callbacks, or missing-addon login message are created.
- Added independent toggles for Naowh window, general element, item-button, HUD/tracker, PvP/Raid
  aura, focus cast-bar, GCD tracker, and top-bar borders.
- Added Enable All and Disable All actions while preserving the existing Reset to Defaults action.
- Disabled features now avoid their factory wrappers, discovery callbacks, secure hooks, events, and
  special-element construction wherever the upstream lifecycle permits.
- Color, font, third-party shell, and EllesmereUI-window callbacks are no longer registered when
  their associated feature is disabled at load time.

## 1.3.0

- Restored PvP Aura and Raid Debuff icon borders through secure post-hooks on their module-specific
  `Icon.New` constructors, without replacing or tainting `Shared.AuraIcon`.
- Aura buttons receive one independent border overlay during Blizzard's `initializeFrame` callback,
  before access restrictions apply; pooled buttons retain and reuse the same overlay.
- The native black edge is hidden only after the EllesmereUI border was created successfully.

## 1.2.1

- Fixed settings tooltips for clients using the modern `GameTooltip:SetText` ColorMixin signature.

## 1.2.0

- Added a lazy native settings page, available from the AddOns settings list or `/nes`.
- Added master color and border toggles plus custom solid-border thickness and color settings.
- Exposed existing font, shell, item-plate, divider, button-border, and EUI-window options.
- Added native reset and reload buttons with safe SavedVariables migration and range validation.
- Disabled border discovery hooks and special-element listeners completely when borders are off.

## 1.1.2

- Removed the `Shared.AuraIcon` factory wrapper completely. Restricted Blizzard aura containers
  inherit taint from any addon wrapper in their creation chain, even when the resulting buttons are
  not modified. PvP Aura and Raid Debuff buttons therefore retain their native edge.

## 1.1.1

- Skip Blizzard restricted/forbidden aura-container buttons before attaching frame scripts,
  preventing `HookScript` secret-aspect taint errors in PvP Auras and Raid Debuffs.

## 1.1.0

- Replaced permanent GCD polling with event-driven, child-count-guarded discovery.
- Replaced optional-element retry polling with coalesced factory-driven initialization.
- Cached the resolved action-bar border style for the session.
- Made visibility and tint synchronization state-aware and allocation-light.
- Removed repeated generic child-level traversal when styled frames are shown.
- Stopped completed window watches from scheduling redundant deferred work.
- Reused deferred callbacks in dynamic layout paths.
- Added architecture and performance documentation.
