# Display Config Switcher

Saved display configurations shared by a user's widget instances.

## Language

**Display profile**:
A named snapshot of a display configuration that can be applied again.
_Avoid_: Preset

**Shared profiles**:
The authoritative collection of display profiles shared by widget instances. An empty collection means no profiles are saved.

**Instance cache**:
A widget instance's local copy of the shared profiles, which may be stale.
_Avoid_: Local source of truth

**Profile migration**:
The initial establishment of shared profiles from an instance cache when shared storage is absent.
