# Changelog

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
