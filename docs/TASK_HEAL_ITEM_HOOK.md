# Agent Task: Find Item-Use Hook for Healing Item Detection

> **Scope**: research only — find and confirm the RE4R method that fires when
> the player uses a healing item from inventory, and verify it exposes the
> item ID. No audio wiring, no deployment. Report the method name and how to
> read item_id from hook arguments.

## Context

The mod plays `heal_herb.wav` (~5 s custom sound) on the DualSense speaker
whenever Leon heals. The heal is detected in `hp_led.lua` via HP delta
(`cur > prev_hp_abs`). This works but has no context about *what* was used —
the same sound plays for a green herb, a first-aid spray, a chicken egg, or a
viper. The goal is to eventually play different sounds per item type.

The item database already exists: `src/reframework/autorun/DualSenseEnhanced/item_ids.lua`
has every healing item mapped to the `"healing"` category, and they are
individually identifiable by ID (Green Herb `114400000`, First Aid Spray
`114416000`, Chicken Egg `277080256`, etc.).

The missing piece: a hook that fires at the moment of item use (not pickup)
and exposes the item ID.

**Why `onAcceptPickup` doesn't help**: that hook fires when Leon picks up an
item from the ground. Using an herb or spray from the inventory menu is a
different code path entirely.

---

## Read first

```
docs/AGENTS.md          ← machine paths, REFramework workflow
src/reframework/autorun/DualSenseEnhanced/item_ids.lua      ← item ID table
src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua ← current heal
src/reframework/autorun/DualSenseEnhanced/hp_led.lua         ← HP delta hook
```

---

## What to find

A REFramework-hookable method on a type like:
- `chainsaw.PlayerInventoryManager` — inventory management
- `chainsaw.ItemUseController` or similar
- `chainsaw.HealManager` / `chainsaw.VitalController`
- Any method whose name contains `use`, `consume`, `heal`, `apply`

The method must:
1. Fire specifically when an item is **used** (not picked up, not dropped)
2. Expose enough context to identify the item (item ID, item type, or an
   object from which `getItemID()` can be called)

---

## Investigation approach

### Option A — REFramework object explorer (fastest)

In-game, open the REFramework menu → Object Explorer. While in the inventory
menu, inspect the player object or search for types containing "inventory",
"item", "use", "consume", "heal". Look for methods being called when you
select and use an herb.

### Option B — Lua method enumeration

Write a short probe script, deploy, and run while using a healing item.
Example pattern (adapt type names as needed):

```lua
-- Drop this in a temporary .lua file, deploy, Reset Scripts, use an herb
local t = sdk.find_type_definition("chainsaw.PlayerInventoryManager")
if t then
    for _, m in ipairs(t:get_methods()) do
        local name = m:get_name()
        if name:lower():find("use") or name:lower():find("consume") or
           name:lower():find("heal") or name:lower():find("apply") then
            print("[probe] method: " .. name)
        end
    end
end
```

Print all method names to the REFramework log; repeat for candidate types.

### Option C — Hook broad candidates and log args

Once a plausible method is found, hook it and log all arguments when a
healing item is used:

```lua
local t = sdk.find_type_definition("chainsaw.CANDIDATE_TYPE")
if t then
    local m = t:get_method("candidateMethod")
    if m then
        sdk.hook(m, function(args)
            print("[probe] hook fired, args:")
            for i = 1, 6 do
                local raw = args[i]
                pcall(function()
                    local obj = sdk.to_managed_object(raw)
                    if obj then
                        local td = obj:get_type_definition()
                        print("  a" .. i .. " = " .. (td and td:get_full_name() or "?"))
                        -- Try to read item ID
                        local id = nil
                        pcall(function() id = obj:call("getItemID") end)
                        if id then print("    item_id = " .. tostring(id)) end
                    end
                end)
            end
        end, function(r) return r end)
        print("[probe] hooked")
    end
end
```

Use an herb from inventory → check if the hook fires and if item_id is readable.

### Option D — Cross-reference with `onAcceptPickup` pattern

The pickup hook in `audio_feedback.lua` uses `chainsaw.DropItem.onAcceptPickup`
with a candidate cache built from `cantDoubleBilling`/`updateSleep`. The same
pattern (pre-hook to cache object, post-hook to act) may work for item use.
Look for methods that run on the inventory item object just before use.

---

## Deliverable

A short report with:

1. **Type name** — e.g. `chainsaw.PlayerInventoryManager`
2. **Method name** — e.g. `useItem`
3. **Hook position** — pre-hook (args) or post-hook (retval)?
4. **How to get item_id** — which argument, what call chain
   (e.g. `args[2] → sdk.to_managed_object → :call("getItemID")`)
5. **Fires for ALL inventory item uses or only healing items?**
   (If all uses: note that filtering by category via `item_ids.lua` will be
   needed downstream)
6. **Does it fire before or after the HP change?**
   (Ideally before or simultaneous, so we can store `last_used_item_id` and
   read it from the HP delta callback)
7. **Probe Lua snippet** that demonstrates the hook working (minimal, just
   the `print` for confirmation — no audio wiring)

---

## What this task does NOT do

- Does not modify `hp_led.lua` or `audio_feedback.lua`
- Does not add new sound stems or WAV files
- Does not wire any audio routing

The wiring task (storing `last_used_item_id`, routing to per-item stems,
creating WAV files) is separate and blocked on this research.

---

## WIRING (2026-07-13) — shipped

Hook stores `last_used_item_id = sdk.to_int64(args[3])` in `audio_feedback.lua`.
`AUDIO.play_heal()` calls `heal_stem_for_item(last_used_item_id)` which routes:

| Item | Stem | File | Notes |
|------|------|------|-------|
| All herb combos (10 IDs) | `heal_herb` | `heal_herb.wav` (3.80s) | lighter click ×2 + inhale + exhale |
| Herbs — rare (5% / 20% danger) | `heal_herb_rare` | `heal_herb_rare.wav` (6.10s) | herb + 0.3s pause + cough |
| Herbs — mock (inverse HP, max 10% at ≥90% HP) | `heal_herb_mock` | `heal_herb_mock.wav` (0.9s) | just cough — punish over-healing |
| Chicken Egg | `heal_egg` | `heal_egg.wav` (0.19s) | quick crunch |
| Brown Chicken Egg | `heal_egg_brown` | `heal_egg_brown.wav` (0.63s) | longer crunch ×1.7 |
| Gold Chicken Egg | `heal_egg_gold` | `heal_egg_gold.wav` (0.75s) | full crunch |
| Black Bass | `heal_fish` | `heal_fish.wav` (0.38s) | quick bite ×1.5 |
| Lunker Bass | `heal_fish_lunker` | `heal_fish_lunker.wav` (0.74s) | medium bite |
| Black Bass (L) | `heal_fish_large` | `heal_fish_large.wav` (2.55s) | full chew |
| Viper | `heal_viper` | `heal_viper.wav` (0.54s) | bite ×1.5 |
| Rhinoceros Beetle | `heal_beetle` | `heal_beetle.wav` (0.77s) | crunch ×1.7 |
| First Aid Spray | `heal_spray` | `heal_spray.wav` | original game WEM 363831734 — intentional |

**Danger state**: `hp_led.lua` exports `LED.is_danger` (bool, updated each tick from
`vital_key == "Danger"`) via `_G.HPLed.is_danger` — same signal that drives the
lightbar blink. Herb rare chance: 5% normal → 20% in danger.

**Egg ID base gotcha**: egg IDs are not multiples of 1600 (e.g. `277080256 % 1600 = 256`).
`EGG_STEMS` keys use the floor-computed base (`277080000` etc.), not raw `item_ids.lua`
values. Herb IDs are exact multiples of 1600 and are unaffected. See fix `e716219`.

---

## RESULT (2026-07-12) — research complete, hook confirmed

Full writeup also in `docs/game_events.md` under "Item Use Detection".
Probe script used for this research has been deleted per the instructions
above (hook confirmed).

1. **Type name**: `chainsaw.CsInventoryController`
2. **Method name**: `applyUseResult`
3. **Hook position**: pre-hook (args) — item ID is available before the
   method body runs, no need to wait for retval.
4. **How to get item_id**: `args[3] → sdk.to_int64(args[3])` directly.
   `chainsaw.ItemID` is a C#-enum-backed value (329 named constants), not a
   struct — reads correctly as a raw int64, unlike other value-type hook
   args elsewhere in this project that need `sdk.to_valuetype`. Do not use
   `to_valuetype`/`to_managed_object` here, both fail/return nil on this arg.
   `args[4] → sdk.to_managed_object → chainsaw.ItemUseResult` also exposes
   `_ResultType` (int, `1` observed on both confirmed successful uses) and
   `_ResultInfo` (nested `REManagedObject`, unexplored, probably unneeded).
5. **Fires for ALL inventory item uses or only healing items?**: Live-tested
   with two different healing items (Chicken Egg `277080256`, First Aid
   Spray `114416000`) — both gave an exact `sdk.to_int64` match against
   `item_ids.lua`. Does **not** fire on equipping/selecting a grenade
   (weapon/throwable actions are a separate path). Method name and scope
   strongly suggest it fires for the general inventory *consumable-use*
   action (not heal-specific), so **filtering by category via
   `item_ids.lua` downstream is still required**, per the original
   assumption in this doc — but weapon/throw actions should never leak
   through this hook, which is a useful property for the wiring pass.
6. **Does it fire before or after the HP change?**: Not directly measured.
   Reasoned to be same-tick or before, based on the method's role ("apply
   the use result"), but **verify empirically before relying on it** — e.g.
   compare an `os.clock()`/frame-counter timestamp from this hook against
   `hp_led.lua`'s `cur > prev_hp_abs` detection on the same real heal event,
   before assuming `last_used_item_id` set in this hook is safely readable
   in the same or next HP-delta poll.
7. **Probe snippet** (already removed from the repo, kept here for
   reference):
   ```lua
   local t = sdk.find_type_definition("chainsaw.CsInventoryController")
   local m = t:get_method("applyUseResult")
   sdk.hook(m, function(args)
       local item_id = sdk.to_int64(args[3])
       print("[probe] item used, id=" .. tostring(item_id))
   end, function(retval) return retval end)
   ```

**Rejected/ruled-out candidates** (do not re-investigate):
- `chainsaw.CsInventoryController.useItem` — does not exist on this type
  (confirmed via full 173-method enumeration). An earlier probe hooking it
  by this name is suspected to have resolved to an unrelated, near-per-frame
  method; unbounded per-call disk I/O in that hook hung the game. Any future
  hook-based probing on this controller should keep a hard write-count cap
  regardless of assumed call frequency.
- `chainsaw.CsInventoryController.onItemUsed` (+ `add_OnItemUsed`/
  `remove_OnItemUsed` event pair) — exists, hook installs cleanly, but never
  fired on a real item use in testing.
- `chainsaw.CsInventoryController.use(InventorySlotType, CsSlotIndex)` —
  fires once per use like `applyUseResult`, but only carries the UI slot
  being used, not the item ID.
- Not found in this build: `chainsaw.RecoveryController`,
  `chainsaw.PlayerItemController`, `app.UseItemAction`,
  `chainsaw.ItemUseController`, `chainsaw.HealManager`,
  `chainsaw.VitalController`, `chainsaw.PlayerInventoryManager`,
  `chainsaw.PlayerHealth`.
- `chainsaw.ItemManager` exists but only exposes sub-manager getters (no
  use-shaped methods). `chainsaw.PlayerCondition` exists (4 methods) but
  none are use-shaped.
