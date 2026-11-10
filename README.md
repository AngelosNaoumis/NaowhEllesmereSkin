# NaowhEllesmereSkin

NaowhEllesmereSkin applies EllesmereUI's palette, fonts, window treatment, and border style to the
supported Naowh Forever interface. It changes no upstream addon files and remains dormant when
Naowh Forever is disabled.

## Installation

Copy the `NaowhEllesmereSkin` directory into `Interface/AddOns` and enable it with EllesmereUI.
Naowh Forever is optional. When it is disabled, Naowh-specific styling remains dormant while the
independent supported EllesmereUI-window border integration can continue to operate.

## Settings and commands

Use `/nes` to open the native AddOns settings page. Every change is saved immediately but applied
only after `/reload`; the page includes a Reload UI button. `/nfeui` provides the compact legacy
command interface and `/nfeui debug` reports installed hooks.

The page controls theme colors, font, window shells, item plates, the shared border engine, Naowh
window borders, generic element borders, item-button borders, HUD/tracker borders, PvP and Raid
aura borders, focus cast-bar borders, GCD tracker borders, top-bar borders, and supported
EllesmereUI-window borders. Enable All, Disable All, and Reset to Defaults are provided.

## Performance and safety

The addon has no permanent `OnUpdate`, repeating timer, or periodic frame scan. Enabled modules
install only their required lifecycle hooks. Borders are cached per frame. Dynamic aura icons use
secure post-hooks on Naowh's finished module-specific icon classes and never attach scripts to
restricted Blizzard aura buttons.
