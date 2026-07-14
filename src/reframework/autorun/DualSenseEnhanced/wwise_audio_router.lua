local sdk = sdk
local os = os
local pcall = pcall
local tostring = tostring
local tonumber = tonumber

_G.DualSenseEnhancedWwiseAudioRouterGeneration = (_G.DualSenseEnhancedWwiseAudioRouterGeneration or 0) + 1
local generation = _G.DualSenseEnhancedWwiseAudioRouterGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedWwiseAudioRouterGeneration == generation
end

local ROUTER = {}
ROUTER.enabled = true
ROUTER.last_status = "not installed"
ROUTER.last_error = nil
ROUTER.last_event = nil
ROUTER.installed_hooks = 0
ROUTER.hook_status = {}
ROUTER.last_emit_at = {}
-- suppress_group/suppressed_by: a route with `suppress_group` mutes, for
-- `suppress_duration` seconds, every route whose `suppressed_by` names the
-- same group. Used to give knife parry clash priority over the frequent
-- minor knife sounds (swing/hit/surface) that fire in the same instant and
-- drown the parry out on the controller speaker.
-- defer: minor routes additionally hold their emit in a queue for this many
-- seconds before sending it to the bridge. The Wwise clash/swing events can
-- arrive a few ms BEFORE the parry event, so forward-only suppression alone
-- still let them through; the short defer lets a parry that lands within the
-- window retroactively cancel them. 0.075 s keeps the swing/hit feedback tight (0.15 was audibly late).
ROUTER.suppress_until = {}
ROUTER.deferred = {}

local event_map = {
    -- Aim-in (L2 press) / aim-out (L2 release), confirmed via live capture
    -- per weapon (2025-06-28). Aim-in events follow a "play_wp<id>_SE_set"
    -- naming pattern in each weapon's own bank; aim-out (where present) is
    -- a separate generic weapon-lowering event, sometimes shared with
    -- other roles (noted per entry). Not every weapon has a distinct
    -- aim-out cue -- Riot Gun, W-870, Skull Shaker, and SG-09 R were
    -- confirmed to have none via clean captures.
    [892036529] = {
        event = "wp4402_aim_in",
        weapon_id = 4402,
        cooldown = 0.30,
        source = "wp4402 (CQBR) aim-in, ch_wp4402.bnk event_0201",
    },
    [666856267] = {
        event = "wp4402_aim_out",
        weapon_id = 4402,
        cooldown = 0.30,
        source = "wp4402 (CQBR) aim-out, ch_wp4402.bnk event_0199",
    },
    [3844674851] = {
        event = "wp4101_aim_in",
        weapon_id = 4101,
        cooldown = 0.30,
        source = "wp4101 (Riot Gun) aim-in, ch_wp4101.bnk event_0236; confirmed no aim-out cue exists",
    },
    [3027281516] = {
        event = "wp4100_aim_in",
        weapon_id = 4100,
        cooldown = 0.30,
        source = "wp4100 (W-870) aim-in, ch_wp4100.bnk event_0219; confirmed no aim-out cue exists",
    },
    [101476094] = {
        event = "wp6001_aim_in",
        weapon_id = 6001,
        cooldown = 0.30,
        source = "wp6001 (Skull Shaker) aim-in, ch_wp6001.bnk event_0207; confirmed no aim-out cue exists",
    },
    [1722211355] = {
        event = "wp4000_aim_in",
        weapon_id = 4000,
        cooldown = 0.30,
        source = "wp4000 (SG-09 R) aim-in, ch_wp4000.bnk event_0256; confirmed no aim-out cue exists",
    },
    [1428456100] = {
        event = "wp4001_aim_in",
        weapon_id = 4001,
        cooldown = 0.30,
        source = "wp4001 (Punisher) aim-in, ch_wp4001.bnk event_0250",
    },
    -- event_0240 (712539726) is shared by dry-fire stage 2 (ammo=0) and
    -- aim-out (ammo>0). Cannot have two Lua table keys, so routed through
    -- a handler that disambiguates by ammo. See play_wp4001_lower_event.
    [712539726] = {
        handler = "play_wp4001_lower_event",
        weapon_id = 4001,
        cooldown = 0.30,
        source = "wp4001 (Punisher) event_0240 shared aim-out/dry_fire_b",
    },
    [3698896644] = {
        event = "wp4001_draw",
        weapon_id = 4001,
        cooldown = 0.60,
        source = "wp4001 (Punisher) draw, ch_wp4001.bnk random container (3 variants, WEMs 878849558/1046254512/213050556); normal draw only; live-captured + bank-confirmed 2026-07-05",
    },
    [753704067] = {
        event = "wp4001_draw_b",
        weapon_id = 4001,
        cooldown = 0.60,
        source = "wp4001 (Punisher) special draw stage B, ch_wp4001.bnk (3 variants, WEMs 138436896/78249842/817704908 ~0.54-0.68s); fires instead of draw during special anim; live-captured 2026-07-06",
    },
    [1397185082] = {
        event = "wp4001_draw_c",
        weapon_id = 4001,
        cooldown = 0.60,
        source = "wp4001 (Punisher) special draw stage C, ch_wp4001.bnk (4 variants, WEMs 194405639/1034392878/823104848/659968438 ~0.50-0.68s); fires ~0.4s after draw_b; live-captured 2026-07-06",
    },
    [3208891162] = {
        event = "wp4001_draw_d",
        weapon_id = 4001,
        cooldown = 0.60,
        source = "wp4001 (Punisher) special draw stage D, ch_wp4001.bnk (3 variants, WEMs 827212066/43569277/142674449 ~0.64-0.81s); fires after draw_b ends; live-captured 2026-07-06",
    },
    [2132585249] = {
        event = "wp4003_draw",
        weapon_id = 4003,
        cooldown = 0.60,
        source = "wp4003 (Blacktail) draw, ch_wp4003.bnk event_0258; confirmed live in both holster-draw and quick-select 2026-07-05",
    },
    [3949149412] = {
        event = "wp4003_draw_b",
        weapon_id = 4003,
        cooldown = 0.60,
        source = "wp4003 (Blacktail) special draw layer B, ch_wp4003.bnk event_0280; fires only on special draw 2026-07-05",
    },
    [3988807512] = {
        event = "wp4003_draw_c",
        weapon_id = 4003,
        cooldown = 0.60,
        source = "wp4003 (Blacktail) special draw layer C, ch_wp4003.bnk event_0282; fires only on special draw 2026-07-05",
    },
    [1680709590] = {
        event = "wp4003_aim_in",
        weapon_id = 4003,
        cooldown = 0.30,
        source = "wp4003 (Blacktail) aim-in, ch_wp4003.bnk event_0252",
    },
    [3406633596] = {
        event = "wp4003_aim_out",
        weapon_id = 4003,
        cooldown = 0.30,
        source = "wp4003 (Blacktail) aim-out, ch_wp4003.bnk event_0274; previously identified (2025-06-27 Blacktail reload research) as a generic weapon-lowering cue, now finally given a real role",
    },
    [276251930] = {
        event = "wp4002_draw",
        weapon_id = 4002,
        cooldown = 0.60,
        source = "wp4002 (Red9) draw, ch_wp4002.bnk random container (3 variants, WEMs 907673377/760398384/62506831); live-captured + bank-confirmed 2026-07-05",
    },
    [2530110965] = {
        event = "wp4002_draw_b",
        weapon_id = 4002,
        cooldown = 0.60,
        source = "wp4002 (Red9) special draw layer B, ch_wp4002.bnk (3 variants, WEMs 542669695/911961700/565864635 ~0.24-0.31s); special-draw-only, live-captured 2026-07-06",
    },
    [3383247231] = {
        event = "wp4002_draw_c",
        weapon_id = 4002,
        cooldown = 0.60,
        source = "wp4002 (Red9) special draw layer C, ch_wp4002.bnk (3 variants, WEMs 371303259/621050623/574357643 ~0.26-0.30s); special-draw-only, live-captured 2026-07-06",
    },
    [3461965221] = {
        event = "wp4002_aim_in",
        weapon_id = 4002,
        cooldown = 0.30,
        source = "wp4002 (Red9) aim-in, ch_wp4002.bnk event_0266",
    },
    -- event_0272 (3924820871) is shared by dry-fire stage 2 (ammo=0) and
    -- aim-out (ammo>0). Routed through handler. See play_wp4002_lower_event.
    [3924820871] = {
        handler = "play_wp4002_lower_event",
        weapon_id = 4002,
        cooldown = 0.30,
        source = "wp4002 (Red9) event_0272 shared aim-out/dry_fire_b",
    },
    [164257408] = {
        event = "wp4004_draw",
        weapon_id = 4004,
        cooldown = 0.60,
        source = "wp4004 (Matilda) draw, ch_wp4004.bnk (3 variants WEMs 836898518/776019811/811074751 ~0.54-0.68s); live-captured 2026-07-06",
    },
    [4245683862] = {
        event = "wp4004_draw_b",
        weapon_id = 4004,
        cooldown = 0.60,
        source = "wp4004 (Matilda) draw layer B, ch_wp4004.bnk (3 variants WEMs 530717074/754705400/212106949 ~0.33-0.37s); fires +0.24s after draw; live-captured 2026-07-06",
    },
    [4245683861] = {
        event = "wp4004_draw_c",
        weapon_id = 4004,
        cooldown = 0.60,
        source = "wp4004 (Matilda) draw layer C, ch_wp4004.bnk (3 variants WEMs 299095967/148121183/176271415 ~0.23-0.28s); alternate layer B variant; live-captured 2026-07-06",
    },
    [1926286331] = {
        event = "wp4004_draw_d",
        weapon_id = 4004,
        cooldown = 0.60,
        source = "wp4004 (Matilda) special draw stage D, ch_wp4004.bnk (3 variants WEMs 29434068/128908844/58857295 ~0.26-0.51s); fires +0.37s after draw; special-draw-only; live-captured 2026-07-06",
    },
    [1518221001] = {
        event = "wp4004_draw_e",
        weapon_id = 4004,
        cooldown = 0.60,
        source = "wp4004 (Matilda) special draw stage E, ch_wp4004.bnk (2 variants WEMs 111535408/1023185056 ~0.45-0.48s); fires +0.94s after draw; special-draw-only; live-captured 2026-07-06",
    },
    [2927861719] = {
        event = "wp4004_aim_in",
        weapon_id = 4004,
        cooldown = 0.30,
        source = "wp4004 (Matilda) aim-in, ch_wp4004.bnk event_0258",
    },
    -- Matilda aim-out shares event_id=4245683861 with reload-finish
    -- (event_0268) -- see play_wp4004_weapon_lower_event in audio_feedback.lua,
    -- which picks finish vs aim-out based on AUDIO.reload_session_active.
    [4245683861] = {
        handler = "play_wp4004_weapon_lower_event",
        weapon_id = 4004,
        cooldown = 0.30,
        source = "wp4004 (Matilda) shared finish/aim-out event, ch_wp4004.bnk event_0268",
    },

    -- UI: attache case (inventory) open/close, quick-select weapon wheel.
    -- Not weapon-gated -- these fire from menu/UI code, independent of the
    -- currently equipped weapon. Confirmed via 2 independent live captures
    -- each, cross-checked against ch_ui_ingame.bnk (open/close) and
    -- ch_cha0.bnk (quick-select, event_18204).
    [465888893] = {
        event = "ui_inventory_open",
        cooldown = 0.50,
        source = "play_CH_GUI_ATTACHECASE_OPEN (ch_ui_ingame.bnk, event_0570)",
    },
    [1699876315] = {
        event = "ui_inventory_close",
        cooldown = 0.50,
        source = "play_CH_GUI_ATTACHECASE_CLOSE (ch_ui_ingame.bnk, event_0640)",
    },
    [3244343389] = {
        event = "ui_quick_select",
        cooldown = 0.20,
        source = "quick-select weapon wheel (ch_cha0.bnk, event_18204)",
    },
    -- Per-weapon draw/equip sound, fired when the new weapon appears in
    -- hand after a quick-select switch. Each weapon has its own dedicated
    -- Wwise event in its own bank (ch_wp<id>.bnk); confirmed via 2-3
    -- independent live captures each, cross-checked against the bank.
    -- event_id=3333492782/3898613260 (ch_cha0.bnk event_18206, generic
    -- character-level weapon-grab cue) are common to every weapon switch
    -- and intentionally not routed -- only the weapon-specific tail event
    -- carries useful per-weapon audio.
    -- SG-09 R's 3-stage special draw animation (does not fire on the
    -- ordinary draw, only a rarer special-animation variant). Confirmed
    -- reproducible across 3 independent captures in this order.
    [491310844] = {
        event = "wp4000_draw_a",
        weapon_id = 4000,
        cooldown = 1.0,
        source = "wp4000 (SG-09 R) special draw stage 1/3, ch_wp4000.bnk event_0244",
    },
    [1159279911] = {
        event = "wp4000_draw",
        weapon_id = 4000,
        cooldown = 1.0,
        source = "wp4000 (SG-09 R) special draw stage 2/3, ch_wp4000.bnk event_0252",
    },
    [3826103781] = {
        event = "wp4000_draw_c",
        weapon_id = 4000,
        cooldown = 1.0,
        source = "wp4000 (SG-09 R) special draw stage 3/3, ch_wp4000.bnk event_0271",
    },
    [2390921771] = {
        event = "wp4100_draw",
        weapon_id = 4100,
        cooldown = 1.0,
        source = "wp4100 (W-870) draw/equip stage 1/3, ch_wp4100.bnk event_0213",
    },
    [2047712154] = {
        event = "wp4100_draw_b",
        weapon_id = 4100,
        cooldown = 1.0,
        source = "wp4100 (W-870) draw/equip stage 2/3, ch_wp4100.bnk event_0207",
    },
    [1963824255] = {
        event = "wp4100_draw_c",
        weapon_id = 4100,
        cooldown = 1.0,
        source = "wp4100 (W-870) draw/equip stage 3/3, ch_wp4100.bnk event_0205",
    },
    [3445929668] = {
        event = "wp4101_draw",
        weapon_id = 4101,
        cooldown = 1.0,
        source = "wp4101 (Riot Gun) draw/equip stage 1/3, ch_wp4101.bnk event_0226",
    },
    [514608480] = {
        event = "wp4101_draw_b",
        weapon_id = 4101,
        cooldown = 1.0,
        source = "wp4101 (Riot Gun) draw/equip stage 2/3, ch_wp4101.bnk event_0214",
    },
    [514608483] = {
        event = "wp4101_draw_c",
        weapon_id = 4101,
        cooldown = 1.0,
        source = "wp4101 (Riot Gun) draw/equip stage 3/3, ch_wp4101.bnk event_0216",
    },
    [315968521] = {
        event = "wp4102_draw",
        weapon_id = 4102,
        cooldown = 1.0,
        source = "wp4102 (Striker) draw/equip, single stage, ch_wp4102.bnk event_0204",
    },
    [2850476286] = {
        event = "wp4102_aim_in",
        weapon_id = 4102,
        cooldown = 0.40,
        source = "wp4102 (Striker) aim_in/aim_out shared, ch_wp4102.bnk (2v ~0.27-0.38s); live-captured 2026-07-06",
    },
    [960381449] = {
        event = "wp6001_draw",
        weapon_id = 6001,
        cooldown = 0.60,
        source = "wp6001 (Skull Shaker) draw (6v ~0.30-0.43s), ch_wp6001.bnk; switch container normal-draw sub-group; no special draw; live-confirmed 2026-07-06",
    },
    -- Shotgun/per-shell weapon dry-fire, confirmed via live capture at
    -- ammo=0. Striker (wp4102) has no live Wwise ID for dry-fire after 4
    -- independent capture attempts; left without a dry-fire sound rather
    -- than guessing or faking an input-poll fallback.
    [4023261520] = {
        event = "wp4100_dry_fire",
        weapon_id = 4100,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4100 (W-870) dry fire, ch_wp4100.bnk event_0223",
    },
    [3648793271] = {
        event = "wp4101_dry_fire",
        weapon_id = 4101,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4101 (Riot Gun) dry fire, ch_wp4101.bnk event_0232",
    },
    [3347495870] = {
        event = "wp6001_dry_fire",
        weapon_id = 6001,
        ammo = 0,
        cooldown = 0.50,
        source = "wp6001 (Skull Shaker) dry fire, ch_wp6001.bnk event_0231",
    },
    -- Stingray normal draw (single-stage). Candidate 1764992833, not yet
    -- confirmed live -- added from bank analysis. Reuses wp4401_draw_c.wav
    -- (the former special-draw stage 3 WAV, orphaned when 4033741106 was
    -- reassigned to aim-out). No new WAV needed.
    [1764992833] = {
        event = "wp4401_draw_c",
        weapon_id = 4401,
        cooldown = 1.0,
        source = "wp4401 (Stingray) normal draw candidate, ch_wp4401.bnk; reuses draw_c WAV",
    },
    -- Stingray special draw animation, 3-stage, confirmed reproducible
    -- across 2 independent captures in this order.
    [1944767134] = {
        event = "wp4401_draw_a",
        weapon_id = 4401,
        cooldown = 1.0,
        source = "wp4401 (Stingray) special draw stage 1/3, ch_wp4401.bnk event_0231",
    },
    [3247665678] = {
        event = "wp4401_draw_b",
        weapon_id = 4401,
        cooldown = 1.0,
        source = "wp4401 (Stingray) special draw stage 2/3, ch_wp4401.bnk event_0250",
    },
    -- event_id=4033741106 (former stage 3/3) is actually the generic
    -- weapon-lowering/aim-exit cue (same pattern as M1903's
    -- event_id=3851521877) -- now routed as aim-out.
    [4033741106] = {
        event = "wp4401_aim_out",
        weapon_id = 4401,
        cooldown = 0.30,
        source = "wp4401 (Stingray) aim-out (L2 release); same ID was wrongly mapped as draw stage 3/3 before",
    },
    [611491844] = {
        event = "wp4401_dry_fire",
        weapon_id = 4401,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4401 (Stingray) dry fire, ch_wp4401.bnk event_0223",
    },
    [1122442048] = {
        event = "wp4401_last_shot",
        weapon_id = 4401,
        ammo = 0,
        cooldown = 0.30,
        source = "wp4401 (Stingray) last shot bolt-catch (3v ~0.31-0.46s), ch_wp4401.bnk; live-confirmed 2026-07-06",
    },
    -- SR M1903 special draw, originally mapped as 6 stages (bookended --
    -- first ID repeats at the end). event_id=3851521877 (stage 1/6) turned
    -- out to be the generic weapon-lowering/aim-exit cue (same pattern as
    -- Blacktail's event_0274 and Stingray's event_0262) -- now routed as
    -- aim-out instead of a draw stage.
    [3851521877] = {
        event = "wp4400_aim_out",
        weapon_id = 4400,
        cooldown = 0.30,
        source = "wp4400 (SR M1903) aim-out (L2 release); same ID was wrongly mapped as draw stage 1/6 before",
    },
    [1545855344] = {
        event = "wp4400_draw_b",
        weapon_id = 4400,
        cooldown = 1.0,
        source = "wp4400 (SR M1903) special draw stage 2/6, ch_wp4400.bnk event_0228",
    },
    [4065062720] = {
        event = "wp4400_draw_c",
        weapon_id = 4400,
        cooldown = 1.0,
        source = "wp4400 (SR M1903) special draw stage 3/6 (also fires on normal draw), ch_wp4400.bnk event_0256",
    },
    [1441789338] = {
        event = "wp4400_draw_d",
        weapon_id = 4400,
        cooldown = 1.0,
        source = "wp4400 (SR M1903) special draw stage 4/6, ch_wp4400.bnk event_0224",
    },
    [1357901439] = {
        event = "wp4400_draw_e",
        weapon_id = 4400,
        cooldown = 1.0,
        source = "wp4400 (SR M1903) special draw stage 5/6, ch_wp4400.bnk event_0222",
    },
    [1477056167] = {
        event = "wp4400_draw_f",
        weapon_id = 4400,
        cooldown = 1.0,
        source = "wp4400 (SR M1903) special draw stage 6/6, ch_wp4400.bnk event_0226",
    },
    -- SR M1903 normal draw is just 2 of the same-family events (3851521878,
    -- one digit off from the special draw's bookend 3851521877 -- not
    -- routed to avoid confusion with the special-draw mapping above) plus
    -- the shared 4065062720 already routed as draw_c.
    [118528811] = {
        event = "wp4400_dry_fire",
        weapon_id = 4400,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4400 (SR M1903) dry fire, ch_wp4400.bnk event_0216",
    },
    [2789614110] = {
        event = "wp4402_draw",
        weapon_id = 4402,
        cooldown = 1.0,
        source = "wp4402 (CQBR) draw/equip, single stage, ch_wp4402.bnk event_0226",
    },
    [2425776817] = {
        event = "wp4402_dry_fire",
        weapon_id = 4402,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4402 (CQBR) dry fire, ch_wp4402.bnk event_0222",
    },
    [2330373695] = {
        event = "wp4000_dry_fire",
        weapon_id = 4000,
        ammo = 0,
        cooldown = 0.20,
        source = "wp4000 event_0260 dry fire",
    },

    -- Blacktail dry fire. event_0256 was originally catalogued as
    -- reload-start by ear, but never fired in any reload capture; a clean
    -- ammo=0 trigger-pull capture confirmed it is exclusively the dry-fire
    -- sound (own dedicated WAV, not shared with reload like wp4000).
    [1962329062] = {
        event = "wp4003_dry_fire",
        weapon_id = 4003,
        ammo = 0,
        cooldown = 0.20,
        source = "wp4003 event_0256 dry fire",
    },

    -- Magazine insert/seat is driven directly by the confirmed Wwise event
    -- instead of an ammo-count increase. The ammo-delta heuristic in
    -- ammo_led.lua misses the case where the mag is already full and the
    -- player only re-chambers the extra round (total ammo never increases),
    -- so the insert cue must not depend on ammo math at all.
    [3172553005] = {
        event = "wp4003_reload_insert",
        weapon_id = 4003,
        cooldown = 1.0,
        source = "wp4003 event_0268 magazine insert/seat",
    },

    -- Same fix as wp4003: event_0271 (the previously catalogued "confirmed"
    -- insert ID) never fired in live capture, in either a normal reload or
    -- the already-full re-chamber edge case. event_0246 was the closest
    -- ammo-independent candidate, firing reliably ~0.3-0.4s before the ammo
    -- tick in every captured reload. Pending physical speaker confirmation.
    [635031351] = {
        event = "wp4000_reload_insert",
        weapon_id = 4000,
        cooldown = 1.0,
        source = "wp4000 event_0246 magazine insert candidate (replaces unconfirmed event_0271)",
    },

    -- Same fix as wp4000/wp4003. Confirmed reload-exclusive trio for
    -- Punisher (live capture, 2025-06-27): event_0244 -> event_0246 ->
    -- event_0260, fires every time regardless of ammo math (verified
    -- against the already-full re-chamber edge case at 12/12). event_0260
    -- fires last, right before the ammo tick in a normal reload, so it
    -- replaces the old ammo-delta insert trigger.
    [2748519654] = {
        event = "wp4001_reload_insert",
        weapon_id = 4001,
        cooldown = 1.0,
        source = "wp4001 event_0260 magazine insert candidate",
    },

    -- Same fix family for Red9. Live capture (2025-06-27), normal reload
    -- only (7->8): pre-tick sequence event_0228 -> event_0268 -> event_0262
    -- -> event_0240, with event_0240 firing last, immediately before the
    -- ammo tick. event_0252 fires after the tick as the bolt-close/slide-
    -- forward sound. Live log 2026-07-05 confirms: 0240 in reload_start
    -- window (ammo=0), 0252 first event in reload_insert window (ammo=8).
    [2412561847] = {
        event = "wp4002_reload_insert",
        weapon_id = 4002,
        cooldown = 1.0,
        source = "wp4002 event_0240 magazine latch click (fires ~0.6s before ammo tick); confirmed reload_start window 2026-07-05",
    },
    -- Red9 bolt-close / slide-forward: fires 0.17s after ammo tick (first
    -- event in reload_insert window). Previously disabled as "delayed tail"
    -- but it IS the bolt-close sound the user was missing. 2 random WEMs.
    [2993296297] = {
        event = "wp4002_reload_finish",
        weapon_id = 4002,
        cooldown = 0.80,
        source = "wp4002 event_0252 bolt-close/slide-forward; confirmed reload_insert window 2026-07-05; WEMs 482970420/445816727",
    },

    -- Same fix family for Matilda. Live capture (2025-06-27), normal reload
    -- only (17->18): pre-tick sequence event_0254 -> event_0262 ->
    -- event_0238, with event_0238 firing last, ~0.38s before the ammo tick.
    -- Not yet verified against the already-full re-chamber edge case --
    -- pending speaker confirmation.
    [929678675] = {
        event = "wp4004_reload_insert",
        weapon_id = 4004,
        cooldown = 1.0,
        source = "wp4004 event_0238 magazine insert candidate (unverified vs full-mag edge case)",
    },

    -- SG-09 R last-shot (slide locks back on the round that empties the
    -- magazine) and reload-finish, both newly identified (2025-06-27).
    [919884007] = {
        event = "wp4000_last_shot",
        weapon_id = 4000,
        ammo = 0,
        cooldown = 1.0,
        source = "wp4000 event_0248 last-shot slide lock",
    },
    [1972347088] = {
        event = "wp4000_reload_finish",
        weapon_id = 4000,
        cooldown = 0.50,
        source = "wp4000 event_0258 reload finish (previously rejected by ear, now confirmed live)",
    },

    -- Blacktail last-shot and reload-finish, newly identified (2025-06-27).
    [3376360896] = {
        event = "wp4003_last_shot",
        weapon_id = 4003,
        ammo = 0,
        cooldown = 1.0,
        source = "wp4003 event_0272 last-shot slide lock",
    },
    [1774673807] = {
        event = "wp4003_reload_finish",
        weapon_id = 4003,
        cooldown = 0.50,
        source = "wp4003 event_0254 reload finish",
    },

    -- Punisher: event_0234 is the same Wwise ID already used for the
    -- hook-triggered reload-start WAV, reused here (gated to ammo=0) as the
    -- last-shot cue, same pattern as wp4000's dry-fire/reload-start reuse.
    -- The dry-fire click itself is a two-stage sequence, event_0252 then
    -- event_0240, confirmed consistent across two separate captures.
    [122774918] = {
        event = "wp4001_reload_start",
        weapon_id = 4001,
        ammo = 0,
        cooldown = 1.0,
        source = "wp4001 event_0234 last-shot (reuses reload-start WAV)",
    },
    [1509391672] = {
        event = "wp4001_dry_fire_a",
        weapon_id = 4001,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4001 event_0252 dry-fire stage 1",
    },
    -- 712539726 (dry_fire_b / aim_out) is now handled by the unified
    -- play_wp4001_lower_event handler entry in the aim section above.
    [1524268397] = {
        event = "wp4001_reload_finish",
        weapon_id = 4001,
        cooldown = 0.50,
        source = "wp4001 event_0254 reload finish",
    },

    -- Red9: dry-fire is also a two-stage sequence, event_0248 then
    -- event_0272, confirmed consistent across two separate captures
    -- (user reported hearing it as a single click). event_0238 is the
    -- distinct last-shot cue; event_0252 is reload-finish.
    [2692002997] = {
        event = "wp4002_dry_fire_a",
        weapon_id = 4002,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4002 event_0248 dry-fire stage 1",
    },
    -- 3924820871 (dry_fire_b / aim_out) handled by play_wp4002_lower_event.
    [1452850441] = {
        event = "wp4002_last_shot",
        weapon_id = 4002,
        ammo = 0,
        cooldown = 1.0,
        source = "wp4002 event_0238 last-shot",
    },
    -- Red9: disabled 2026-07-04. Live test showed event_0252 plays as a
    -- delayed extra tail after the useful reload sequence. Keep start +
    -- event_0240 insert only until a better finish cue is identified.

    -- Matilda dry-fire (event_0234, newly identified). event_0268 was first
    -- identified as reload-finish but also fires during dry-fire at ammo=0,
    -- so it is routed through a handler that only emits when ammo > 0
    -- instead of the plain `event` field, to avoid playing the finish WAV
    -- on a dry trigger pull. No confirmed last-shot candidate yet (only
    -- generic/unresolved IDs were seen at the 1->0 transition).
    [554267755] = {
        event = "wp4004_dry_fire",
        weapon_id = 4004,
        ammo = 0,
        cooldown = 0.50,
        source = "wp4004 event_0234 dry fire",
    },
    -- event_id=4245683861 (event_0268) handling moved to the combined
    -- finish/aim-out entry further below (play_wp4004_weapon_lower_event).

    -- Riot Gun is per-shell, not single-insert like the handguns: live
    -- capture (2025-06-27) confirmed event_0220 fires once per shell loaded
    -- (observed at both 5->6 and 6->7), so the cooldown must be short
    -- enough not to suppress the next shell's repeat (~0.49s apart
    -- observed). event_0222 fired once, only when the tube reached max
    -- (7/7); kept unmapped for now (possible finish/full cue, unconfirmed).
    [1445424379] = {
        event = "wp4101_reload_insert",
        weapon_id = 4101,
        cooldown = 0.20,
        source = "wp4101 event_0220 per-shell insert (repeats per shell)",
    },

    -- Pump-rack/finish cue: event_0222 fired exactly once, only when the
    -- tube reached max capacity (7/7), distinct from the per-shell
    -- event_0220 repeats. wp4101_reload_finish.wav already exists and was
    -- mapped in SoundMap.cs but never triggered (no finish key was wired
    -- for wp4101 before this).
    [2100648851] = {
        event = "wp4101_reload_finish",
        weapon_id = 4101,
        cooldown = 1.0,
        source = "wp4101 event_0222 pump-rack/finish candidate",
    },

    -- W-870 is per-shell like Riot Gun. Live capture (2025-06-27) with the
    -- rapid-reload upgrade active confirmed event_0215 fires once per shell
    -- (3 times for 3 ammo increases, 2->3->4->5), ~0.45-0.52s apart.
    [2662879608] = {
        event = "wp4100_reload_insert",
        weapon_id = 4100,
        cooldown = 0.20,
        source = "wp4100 event_0215 per-shell insert (repeats per shell)",
    },

    -- W-870 post-shot pump cycle, previously driven by a fixed 60-frame
    -- delay after ammo decreases (W870_PUMP_OPEN_DELAY_FRAMES in
    -- ammo_led.lua), which would desync from the real animation under a
    -- pump-speed upgrade. Live capture (2025-06-27, normal fire, non-empty
    -- shot) confirmed event_0203 as the only weapon-specific candidate
    -- after the shot (~0.83s later), with no separate "close" ID observed
    -- in the same window -- the close layer is likely a cosmetic
    -- short-delay WAV rather than a second real game event. Routed through
    -- the `handler` field instead of `event` so it can call
    -- AUDIO.play_w870_pump_cycle(), which plays the open WAV immediately
    -- and schedules the close WAV after a short fixed cosmetic gap.
    [1130067124] = {
        handler = "play_w870_pump_cycle",
        weapon_id = 4100,
        cooldown = 0.50,
        source = "wp4100 event_0203 post-shot pump cycle (replaces fixed-frame delay)",
    },

    -- Skull Shaker is per-shell (2-round capacity). Live capture
    -- (2025-06-27) confirmed event_0229 fires once per shell (twice, for
    -- both 0->1 and 1->2 ammo ticks), contradicting the by-ear catalog
    -- label ("shell ejection/contact") -- event_0223, the catalogued
    -- "per-shell insertion" candidate, fired only once and did not repeat.
    -- `finish` is left on the existing ammo-based finish_on_full_insert
    -- path for now (two post-tick candidates, event_0209/event_0219, were
    -- seen but not yet disambiguated).
    [1840028007] = {
        event = "wp6001_reload_start",
        weapon_id = 6001,
        cooldown = 0.50,
        source = "wp6001 (Skull Shaker) tray open layer a (1v ~0.30s), ch_wp6001.bnk; live-confirmed 2026-07-06",
    },
    [2246536536] = {
        event = "wp6001_reload_start_b",
        weapon_id = 6001,
        cooldown = 0.50,
        source = "wp6001 (Skull Shaker) tray open layer b (3v ~0.61s), ch_wp6001.bnk; live-confirmed 2026-07-06",
    },
    [814106828] = {
        event = "wp6001_reload_start_c",
        weapon_id = 6001,
        cooldown = 0.50,
        source = "wp6001 (Skull Shaker) tray open layer c (3v ~0.45-0.55s), ch_wp6001.bnk; live-confirmed 2026-07-06",
    },
    [2970245350] = {
        event = "wp6001_reload_insert",
        weapon_id = 6001,
        cooldown = 0.20,
        source = "wp6001 event_0229 per-shell insert (repeats per shell)",
    },

    -- Skull Shaker pump-close / final reload finish; fires when ammo hits
    -- full after the last shell insert. Confirmed live 2026-07-04 via
    -- sound_event_ids.log (t=1426.815, ammo 2/2). ch_wp6001.bnk event_0219.
    [1840028004] = {
        event = "wp6001_reload_finish",
        weapon_id = 6001,
        cooldown = 0.30,
        source = "wp6001 (Skull Shaker) reload finish/pump-close, ch_wp6001.bnk event_0219; WEM 215698335; confirmed live 2026-07-04",
    },

    -- Skull Shaker post-shot action, previously a fixed ~1s delay timer
    -- (SKULL_SHAKER_POSTSHOT_DELAY_FRAMES in ammo_led.lua). Live capture
    -- (2025-06-27) confirmed event_0233 (the catalogued composite
    -- open+insert action) fires only ~0.1-0.3s after every shot, including
    -- the one that empties the weapon.
    [3617200030] = {
        event = "wp6001_postshot",
        weapon_id = 6001,
        cooldown = 0.50,
        source = "wp6001 event_0233 post-shot action (replaces fixed-frame delay)",
    },

    -- Striker is per-shell like Riot Gun/W-870. Live capture (2025-06-27)
    -- confirmed event_0208 fires once per shell loaded (3 times for 3 ammo
    -- increases, 7->9->11->12).
    [1637421798] = {
        event = "wp4102_reload_insert",
        weapon_id = 4102,
        cooldown = 0.20,
        source = "wp4102 event_0208 per-shell insert (repeats per shell)",
    },

    -- SR M1903 is per-shell too. Live capture (2025-06-27) confirmed
    -- event_0241 fires once per shell loaded (4 times for 4 ammo
    -- increases, 1->2->3->4->5).
    [2754292061] = {
        event = "wp4400_reload_insert",
        weapon_id = 4400,
        cooldown = 0.20,
        source = "wp4400 event_0241 per-shell insert (repeats per shell)",
    },

    -- SR M1903 post-shot bolt action, previously a fixed ~1s delay timer
    -- (SR1903_POSTSHOT_DELAY_FRAMES in ammo_led.lua). Live capture
    -- (2025-06-27) showed a sequence of 4 weapon-specific candidates after
    -- each shot (event_0226 -> event_0224 -> event_0222 -> event_0228).
    -- event_0228 was tried first but measured ~1.07s after the shot in a
    -- precise single-shot capture -- effectively the same lag as the old
    -- timer, so it is rejected. event_0226 fires earliest (~0.49s after the
    -- shot) and is the new candidate for the bolt-rack start. Best guess
    -- pending speaker confirmation -- the empty-shot deferred-until-reload
    -- path is untouched (not yet re-tested against this ID).
    -- event_0226 (like event_0228) also fires during the normal reload
    -- sequence, not just post-shot, so it is routed through a handler that
    -- skips while a reload session is active instead of the plain `event`
    -- field, to avoid spurious extra "finish" sounds layered during reload.
    [1477056167] = {
        handler = "play_sr1903_postshot_event",
        weapon_id = 4400,
        cooldown = 0.50,
        source = "wp4400 event_0226 post-shot bolt candidate (replaces fixed-frame delay, unverified)",
    },

    -- Stingray: confirmed live reload sequence (2025-06-27), identified by
    -- ear against the real extracted WAVs (not placeholders):
    -- event_0242 (magazine release/pull-out) -> event_0240 (sounds like a
    -- reload-start click) -> event_0252 (magazine insert, right before the
    -- ammo tick) -> [ammo tick] -> event_0248 (bolt rack / finish).
    -- event_0262 is excluded: it is a generic weapon-handling/aim-lower cue
    -- (same family as Blacktail's event_0274), confirmed by firing twice
    -- per reload AND on simple aim-exit; not reload-specific.
    -- The hook-triggered wp4401_reload_start sound is kept as-is alongside
    -- this sequence (unaffected, fires at the very start of the action).
    [2355383903] = {
        event = "wp4401_reload_release",
        weapon_id = 4401,
        cooldown = 0.50,
        source = "wp4401 event_0242 magazine release/pull-out",
    },
    [2263515509] = {
        event = "wp4401_reload_open",
        weapon_id = 4401,
        cooldown = 0.50,
        source = "wp4401 event_0240 reload-start-like click",
    },
    [3683820930] = {
        event = "wp4401_reload_insert",
        weapon_id = 4401,
        cooldown = 0.50,
        source = "wp4401 event_0252 magazine insert",
    },
    [2795902225] = {
        event = "wp4401_reload_finish",
        weapon_id = 4401,
        cooldown = 0.50,
        source = "wp4401 event_0248 bolt rack / finish",
    },

    -- CQBR: confirmed live reload capture (2025-06-27) plus user listening
    -- review. Final sequence: event_0210 (magazine release/extraction,
    -- despite the catalog calling it a rejected weapon-draw/equip cue) ->
    -- event_0231 (catalog: safety toggle, but kept in sequence per user
    -- review) -> event_0235 (post-shot bolt cycle, used as finish). The
    -- hook-triggered start sound and event_0216 ("magazine seated") were
    -- both rejected by the user and removed entirely; event_0235 replaces
    -- the previous cross-bank wp4401 placeholder WAV.
    [1314533246] = {
        event = "wp4402_reload_release",
        weapon_id = 4402,
        cooldown = 0.50,
        source = "wp4402 event_0210 magazine release/extraction",
    },
    [3189178245] = {
        event = "wp4402_reload_safety",
        weapon_id = 4402,
        cooldown = 0.50,
        source = "wp4402 event_0231 safety toggle",
    },
    [4242163571] = {
        event = "wp4402_reload_finish",
        weapon_id = 4402,
        cooldown = 0.50,
        source = "wp4402 event_0235 bolt rack / finish",
    },
    [1920728793] = {
        event = "wp4402_reload_insert_b",
        weapon_id = 4402,
        cooldown = 0.20,
        source = "wp4402 (CQBR) secondary magazine insert click, ch_wp4402.bnk (3v ~0.22s); live-captured 2026-07-07",
    },

    -- Killer7: same already-full re-chamber edge case as wp4000/wp4001/
    -- wp4003/wp4004 (ammo stayed at 7/7 the whole captured reload).
    -- Pre-tick-equivalent sequence event_0220 -> event_0212 -> event_0214;
    -- event_0214 fires last and replaces the old ammo-delta insert trigger.
    -- Reload: reload_start fires at start+insert+finish (1.0s cooldown gates insert
    -- overlap, naturally re-triggers at finish). insert_b is a second layer during loading.
    [1484058684] = {
        event = "wp4501_reload_start",
        weapon_id = 4501,
        cooldown = 1.00,
        source = "wp4501 (Killer7) reload mechanical layer, ch_wp4501.bnk (1 WEM 542468377 ~0.49s); fires reload_start+insert+finish; live-captured 2026-07-06",
    },
    [1039594587] = {
        event = "wp4501_reload_insert",
        weapon_id = 4501,
        cooldown = 0.50,
        source = "wp4501 event_0214 speedloader insert",
    },
    [3151071005] = {
        event = "wp4501_reload_insert_b",
        weapon_id = 4501,
        cooldown = 0.50,
        source = "wp4501 (Killer7) reload insert layer B, ch_wp4501.bnk (3 variants WEMs 878112439/841691150/329968913 ~0.25-0.56s); fires reload_insert; live-captured 2026-07-06",
    },
    [1194393411] = {
        event = "wp4501_dry_fire",
        weapon_id = 4501,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4501 (Killer7) dry fire / empty trigger click, ch_wp4501.bnk (1 WEM 151545836 ~0.07s); live-captured 2026-07-06",
    },
    [3317704895] = {
        event = "wp4501_aim_in",
        weapon_id = 4501,
        cooldown = 0.40,
        source = "wp4501 (Killer7) aim_in (3v ~0.21-0.34s), ch_wp4501.bnk; live-confirmed 2026-07-06",
    },
    -- Draw: base fires on both normal and special draw; draw_b fires on
    -- normal draw AND reload contexts (cylinder layer, same pattern as BB).
    -- draw_c and draw_d fire on special draw only.
    [3966122408] = {
        event = "wp4501_draw",
        weapon_id = 4501,
        cooldown = 0.60,
        source = "wp4501 (Killer7) draw, ch_wp4501.bnk (3 variants WEMs 635025450/402084624/646743203 ~0.29-0.60s); fires on normal+special draw; live-captured 2026-07-06",
    },
    [3151071006] = {
        event = "wp4501_draw_b",
        weapon_id = 4501,
        cooldown = 0.60,
        source = "wp4501 (Killer7) draw layer B, ch_wp4501.bnk (3 variants WEMs 201917923/1054751906/246547127 ~0.28-0.40s); fires on normal draw + reload contexts; live-captured 2026-07-06",
    },
    [1766302611] = {
        event = "wp4501_draw_c",
        weapon_id = 4501,
        cooldown = 0.60,
        source = "wp4501 (Killer7) draw layer C, ch_wp4501.bnk (3 variants WEMs 482234327/700045862/314123221 ~0.24-0.30s); special draw only; live-captured 2026-07-06",
    },
    [2557856193] = {
        event = "wp4501_draw_d",
        weapon_id = 4501,
        cooldown = 0.60,
        source = "wp4501 (Killer7) draw layer D, ch_wp4501.bnk (3 variants WEMs 200363649/581479529/32408838 ~0.27-0.35s); special draw only; live-captured 2026-07-06",
    },
    [1388742891] = {
        event = "wp4501_last_shot",
        weapon_id = 4501,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4501 (Killer7) last shot / empty gun click, ch_wp4501.bnk (3 variants WEMs 770545959/563878611/422967852 ~0.56-0.60s); live-confirmed 2026-07-06",
    },

    -- Sentinel Nine's start/insert/last-shot/finish are now handled via the
    -- Sentinel Nine (wp6000) has no extractable Wwise bank of its own, but
    -- the engine fires its own numeric Wwise event IDs (distinct from
    -- SG-09 R's) when it's equipped, even though it reuses SG-09 R's audio
    -- assets. WAV files are SG-09 R's, copied to wp6000_* names; the event
    -- IDs below are Sentinel-specific, captured live.
    [1498116241] = {
        event = "wp6000_reload_insert",
        weapon_id = 6000,
        cooldown = 1.0,
        source = "wp6000 magazine insert (live-captured, bank-unconfirmed)",
    },
    -- event_id=3601070767 (originally guessed as reload finish) is
    -- disabled (2025-06-28): live test showed it fires on plain aim-exit
    -- (the stray-sound bug). A second capture also showed it actually
    -- fires at the magazine-insert moment (ammo jump to full), not at the
    -- post-insert slide-rack -- it was never the right candidate for either
    -- role and must not be re-enabled without a dedicated control test.
    [2515821485] = {
        event = "wp6000_dry_fire",
        weapon_id = 6000,
        ammo = 0,
        cooldown = 0.20,
        source = "wp6000 dry fire (live-captured, bank-unconfirmed; confirmed reproducible across 3 independent captures)",
    },
    [4056224971] = {
        event = "wp6000_last_shot",
        weapon_id = 6000,
        ammo = 1,
        cooldown = 1.0,
        source = "wp6000 last-shot slide lock (live-captured, bank-unconfirmed; fires while ammo still reads 1/19, just before the 1->0 decrement registers -- confirmed across 2 captures)",
    },
    -- event_id=272828262 disabled (2025-06-28): live test showed it fires
    -- randomly during live fire and at reload start, not specifically after
    -- full magazine insert. Not weapon-specific/phase-specific; do not
    -- re-enable. A second capture also confirmed it coincides with the
    -- magazine-seating click (ammo reaching full), not the post-insert
    -- slide-rack.
    -- event_id=670443406 also disabled (2025-06-28): a third capture showed
    -- it firing during reload_start (before insert) and the user reported
    -- it firing even while AFK -- it is part of the same ambient/footstep
    -- noise floor as 807178836/2250845221/2250845243/etc, not weapon audio.
    -- No reliable post-insert slide-rack/finish candidate has been found
    -- for Sentinel Nine after 3 capture attempts; leave finish unmapped
    -- (same situation as SR M1903, which has no finish stage at all) rather
    -- than keep guessing from the noise floor. A future capture should be
    -- done standing still (no footsteps) to reduce ambient noise.
    -- Draw events confirmed from special draw capture 2026-07-05.
    -- Bank: ch_wp6000.sbnk in re_dlc_stm_2109308.pak (2 MB DLC stub).
    [3740539746] = {
        event = "wp6000_draw_a",
        weapon_id = 6000,
        cooldown = 0.60,
        source = "wp6000 (Sentinel Nine) draw stage A, ch_wp6000.bnk event 3740539746; confirmed special draw 2026-07-05",
    },
    [2169289773] = {
        event = "wp6000_draw_b",
        weapon_id = 6000,
        cooldown = 0.60,
        source = "wp6000 (Sentinel Nine) draw stage B, ch_wp6000.bnk event 2169289773; confirmed special draw 2026-07-05",
    },
    [1049114615] = {
        event = "wp6000_draw_c",
        weapon_id = 6000,
        cooldown = 0.60,
        source = "wp6000 (Sentinel Nine) draw stage C, ch_wp6000.bnk event 1049114615; confirmed special draw 2026-07-05",
    },

    -- Aim-in/aim-out, own IDs (not shared with SG-09 R, confirming
    -- wp6000 does not actually share wp4000's bank at the event level).
    [3761912333] = {
        event = "wp6000_aim_in",
        weapon_id = 6000,
        cooldown = 0.30,
        source = "wp6000 aim-in (L2 press), live-captured, bank-unconfirmed",
    },
    [3601070767] = {
        event = "wp6000_aim_out",
        weapon_id = 6000,
        cooldown = 0.30,
        source = "wp6000 aim-out (L2 release), live-captured, bank-unconfirmed; this is the same ID originally guessed (and rejected) as reload finish -- it's the generic aim-exit cue, not finish-related",
    },

    -- TMP: first-time mapping (2025-06-27), single-jump full reload
    -- (27->30). Pre-tick sequence event_0220 -> event_0230 -> event_0234,
    -- with event_0234 firing last, right before the tick. event_0242
    -- fires after the tick.
    -- Draw: base fires on both normal and special; draw_b on special only.
    [2093308842] = {
        event = "wp4200_draw",
        weapon_id = 4200,
        cooldown = 0.60,
        source = "wp4200 (TMP) draw, ch_wp4200.bnk (3v WEMs 116931065/979410682/366718883 ~0.40-0.60s); fires on normal+special draw; live-captured 2026-07-06",
    },
    [3595403541] = {
        event = "wp4200_draw_b",
        weapon_id = 4200,
        cooldown = 0.60,
        source = "wp4200 (TMP) draw layer B, ch_wp4200.bnk (3v WEMs 69158281/11015921/1067176941 ~0.27-0.50s); special draw only; live-captured 2026-07-06",
    },
    [466731380] = {
        event = "wp4200_draw_c",
        weapon_id = 4200,
        cooldown = 0.60,
        source = "wp4200 (TMP) draw layer C, ch_wp4200.bnk (3v WEMs 11015921/1067176941/69158281 ~0.27-0.50s); same WEM pool as draw_b, different event; special draw only; live-captured 2026-07-06",
    },
    [3574738629] = {
        event = "wp4200_draw_d",
        weapon_id = 4200,
        cooldown = 0.60,
        source = "wp4200 (TMP) draw layer D, ch_wp4200.bnk (3v WEMs 57265077/714158503/778127169 ~0.34-0.45s); special draw only; live-captured 2026-07-06",
    },
    [3413842159] = {
        event = "wp4200_draw_e",
        weapon_id = 4200,
        cooldown = 0.60,
        source = "wp4200 (TMP) draw layer E, ch_wp4200.bnk (3v WEMs 476963005/476373034/522219704 ~0.41-0.55s); special draw only; live-captured 2026-07-06",
    },
    [466731383] = {
        event = "wp4200_draw_f",
        weapon_id = 4200,
        cooldown = 0.60,
        source = "wp4200 (TMP) draw layer F, ch_wp4200.bnk (3v WEMs 257902496/143570252/1061577745 ~0.15-0.23s); special draw only; live-captured 2026-07-06",
    },
    [2462166917] = {
        event = "wp4200_dry_fire",
        weapon_id = 4200,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4200 (TMP) dry fire (4v ~0.51-0.59s), ch_wp4200.bnk; live-confirmed 2026-07-06",
    },
    [2760081145] = {
        event = "wp4200_reload_insert",
        weapon_id = 4200,
        cooldown = 0.50,
        source = "wp4200 event_0234 magazine insert candidate",
    },
    [3529770506] = {
        event = "wp4200_reload_finish",
        weapon_id = 4200,
        cooldown = 0.50,
        source = "wp4200 event_0242 finish candidate",
    },

    -- LE 5: first-time mapping (2025-06-27), single-jump full reload
    -- (17->20). event_0226 fires last before the ammo tick (also seen
    -- consistently across two incomplete earlier captures); event_0258
    -- fires after the tick.
    -- Draw: base fires on both normal and special; draw_b/c/d on special only.
    -- Note: 3335860215 and 2471587121 were previously listed as aim_in candidates
    -- but live capture confirmed they fire in the draw window, not aim_in.
    [746214667] = {
        event = "wp4202_aim_in",
        weapon_id = 4202,
        cooldown = 0.30,
        source = "wp4202 (LE 5) aim_in, ch_wp4202.bnk (3v WEMs 572949138/293076261/643720766 ~0.29-0.39s); live-captured 2026-07-06",
    },
    [795674380] = {
        event = "wp4202_draw",
        weapon_id = 4202,
        cooldown = 0.60,
        source = "wp4202 (LE 5) draw, ch_wp4202.bnk (3v WEMs 301457749/1065999590/461725618 ~0.40-0.60s); fires on normal+special draw; live-captured 2026-07-06",
    },
    [3335860215] = {
        event = "wp4202_draw_b",
        weapon_id = 4202,
        cooldown = 0.60,
        source = "wp4202 (LE 5) draw layer B, ch_wp4202.bnk (3v WEMs 746968447/307656730/343975167 ~0.24-0.35s); special draw only; live-captured 2026-07-06",
    },
    [3784264661] = {
        event = "wp4202_draw_c",
        weapon_id = 4202,
        cooldown = 0.60,
        source = "wp4202 (LE 5) draw layer C, ch_wp4202.bnk (3v WEMs 16202637/388443251/501900991 ~0.25-0.39s); special draw only; live-captured 2026-07-06",
    },
    [2471587121] = {
        event = "wp4202_draw_d",
        weapon_id = 4202,
        cooldown = 0.60,
        source = "wp4202 (LE 5) draw layer D, ch_wp4202.bnk (3v WEMs 892382414/113930824/88043296 ~0.31-0.38s); special draw only; live-captured 2026-07-06",
    },
    -- Reload start: magazine ejection click (0.17s). 345781889 was a false
    -- candidate -- those 2s WEMs are gunshot sounds firing at reload_start.
    [345236802] = {
        event = "wp4202_reload_start",
        weapon_id = 4202,
        cooldown = 0.50,
        source = "wp4202 (LE 5) reload_start click, ch_wp4202.bnk (3v WEMs 186107528/16630250/1068316980 ~0.17s); live-captured 2026-07-06",
    },
    -- Fires mid-reload, candidate for magazine ejection (~0.7s).
    -- Appeared in both reload_start and reload_finish windows across captures.
    [1937401584] = {
        event = "wp4202_reload_eject",
        weapon_id = 4202,
        cooldown = 0.50,
        source = "wp4202 (LE 5) reload mid-stage / mag eject candidate, ch_wp4202.bnk (3v WEMs 882965237/468264637/111988723 ~0.70-0.78s); live-captured 2026-07-06",
    },
    [560374151] = {
        event = "wp4202_reload_insert",
        weapon_id = 4202,
        cooldown = 0.50,
        source = "wp4202 event_0226 magazine insert candidate",
    },
    [4287874167] = {
        event = "wp4202_reload_finish",
        weapon_id = 4202,
        cooldown = 0.50,
        source = "wp4202 event_0258 finish candidate",
    },
    [641294031] = {
        event = "wp4202_dry_fire",
        weapon_id = 4202,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4202 (LE 5) dry fire (3v ~0.14-0.20s), ch_wp4202.bnk; live-confirmed 2026-07-06",
    },

    -- Chicago Sweeper: first-time mapping (2025-06-27), single-jump full
    -- reload (41->50). Pre-tick sequence event_0252 -> event_0242, with
    -- event_0242 firing last; event_0236 fires after the tick.
    [2785978584] = {
        event = "wp4201_reload_insert",
        weapon_id = 4201,
        cooldown = 0.50,
        source = "wp4201 event_0242 magazine insert candidate",
    },
    [1766324267] = {
        event = "wp4201_reload_finish",
        weapon_id = 4201,
        cooldown = 0.50,
        source = "wp4201 event_0236 finish candidate",
    },
    [2610600561] = {
        event = "wp4201_draw",
        weapon_id = 4201,
        cooldown = 0.60,
        source = "wp4201 (Chicago Sweeper) draw base layer (3v), ch_wp4201.bnk; normal+special; live-captured 2026-07-06",
    },
    [232029062] = {
        event = "wp4201_draw_b",
        weapon_id = 4201,
        cooldown = 0.60,
        source = "wp4201 (Chicago Sweeper) draw layer b (3v), ch_wp4201.bnk; normal+special; live-captured 2026-07-06",
    },
    [3049987048] = {
        event = "wp4201_draw_c",
        weapon_id = 4201,
        cooldown = 0.60,
        source = "wp4201 (Chicago Sweeper) draw layer c (3v), ch_wp4201.bnk; special only; live-captured 2026-07-06",
    },
    [665041300] = {
        event = "wp4201_draw_d",
        weapon_id = 4201,
        cooldown = 0.60,
        source = "wp4201 (Chicago Sweeper) draw layer d (3v), ch_wp4201.bnk; special only; live-captured 2026-07-06",
    },
    [3428451702] = {
        event = "wp4201_dry_fire",
        weapon_id = 4201,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4201 (Chicago Sweeper) dry fire (3v ~0.19-0.30s), ch_wp4201.bnk; live-captured 2026-07-06",
    },

    -- Bolt Thrower: first-time mapping (2025-06-27), single-bolt reload
    -- (2->3). event_0260 fires only ~0.03s before the ammo tick. No
    -- reliable finish candidate (the only post-tick wp4600 candidate,
    -- event_0283, also fires before the tick and on unrelated handling, so
    -- it is excluded as generic, not weapon-action-specific).
    [300966990] = {
        event = "wp4600_draw",
        weapon_id = 4600,
        cooldown = 0.60,
        source = "wp4600 (Bolt Thrower) draw (6v ~0.29-0.64s), ch_wp4600.bnk; draw-only window; live-confirmed 2026-07-06",
    },
    [922138092] = {
        event = "wp4600_aim_in",
        weapon_id = 4600,
        cooldown = 0.40,
        source = "wp4600 (Bolt Thrower) aim/bolt tension sound (2v ~0.57s), ch_wp4600.bnk; shared aim_in+aim_out; live-confirmed 2026-07-06",
    },
    [2857008769] = {
        event = "wp4600_aim_in_b",
        weapon_id = 4600,
        cooldown = 0.40,
        source = "wp4600 (Bolt Thrower) aim click (1v ~0.18s), ch_wp4600.bnk; shared aim_in+aim_out; live-confirmed 2026-07-06",
    },
    [3051463304] = {
        event = "wp4600_aim_out",
        weapon_id = 4600,
        cooldown = 0.40,
        source = "wp4600 (Bolt Thrower) aim out / bolt release (2v ~0.43-0.47s), ch_wp4600.bnk; live-confirmed 2026-07-06",
    },
    [2370660519] = {
        event = "wp4600_post_shot",
        weapon_id = 4600,
        cooldown = 0.35,
        source = "wp4600 (Bolt Thrower) shot impact / first stage without echo (4v ~0.28-0.45s), ch_wp4600.bnk; switch container sub-group; live-confirmed 2026-07-06",
    },
    [1756416417] = {
        event = "wp4600_dry_fire",
        weapon_id = 4600,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4600 (Bolt Thrower) dry fire (1v ~0.07s), ch_wp4600.bnk; live-confirmed 2026-07-06",
    },
    [1946457442] = {
        event = "wp4600_attach",
        weapon_id = 4600,
        cooldown = 0.40,
        source = "wp4600 (Bolt Thrower) mine attach/detach (3v ~0.33-0.43s), ch_wp4600.bnk; live-confirmed 2026-07-06",
    },
    [2455919916] = {
        event = "wp4600_reload_insert",
        weapon_id = 4600,
        cooldown = 0.50,
        source = "wp4600 event_0260 bolt insert candidate",
    },

    -- Broken Butterfly reload, converted from the old ammo-delta
    -- insert/finish_on_full_insert path to confirmed Wwise IDs (same
    -- candidates identified during the post-shot investigation above).
    -- event_0197 repeats once per shell (cooldown matches the other
    -- per-shell weapons); event_0193 fires once after the final tick.
    [4007639528] = {
        event = "wp4500_aim_in",
        weapon_id = 4500,
        cooldown = 0.40,
        source = "wp4500 (Broken Butterfly) aim_in (1v ~0.27s, variant 3 of 3; 1+2 silent), ch_wp4500.bnk; live-confirmed 2026-07-06",
    },
    [302927071] = {
        event = "wp4500_draw",
        weapon_id = 4500,
        cooldown = 0.60,
        source = "wp4500 (Broken Butterfly) draw, ch_wp4500.bnk (3 variants WEMs 35663448/12349786/292060911 ~0.29-0.60s); live-captured 2026-07-06",
    },
    [2926359449] = {
        event = "wp4500_draw_b",
        weapon_id = 4500,
        cooldown = 0.60,
        source = "wp4500 (Broken Butterfly) draw layer B / cylinder click, ch_wp4500.bnk (3 variants WEMs 409732540/30965633/665110711 ~0.28-0.40s); fires +0.44s; also fires on reload_finish/insert; live-captured 2026-07-06",
    },
    [3816064135] = {
        event = "wp4500_draw_c",
        weapon_id = 4500,
        cooldown = 0.60,
        source = "wp4500 (Broken Butterfly) draw layer C / cylinder settle, ch_wp4500.bnk (1 variant WEM 902972499 ~0.39s); fires +0.60s; also fires on reload_finish/insert; live-captured 2026-07-06",
    },
    -- Per-shot cylinder rotation: fires on every shot (like W-870 post-shot pump).
    -- Switch container with 13 WEMs; 4 deployed (0.37-0.52s), long reverb tails excluded.
    [4248629768] = {
        event = "wp4500_post_shot",
        weapon_id = 4500,
        cooldown = 0.30,
        source = "wp4500 (Broken Butterfly) post-shot cylinder cycle, ch_wp4500.bnk (4 variants WEMs 562261101/502390063/182769156/54444553 ~0.37-0.52s); fires on every shot; live-confirmed 2026-07-06",
    },
    [827544157] = {
        event = "wp4500_reload_start",
        weapon_id = 4500,
        cooldown = 0.50,
        source = "wp4500 event_0191 reload open / cartridge eject (matches catalog label)",
    },
    [2338516948] = {
        event = "wp4500_reload_insert",
        weapon_id = 4500,
        cooldown = 0.20,
        source = "wp4500 event_0197 per-shell insert (repeats per shell)",
    },
    [947094733] = {
        event = "wp4500_reload_finish",
        weapon_id = 4500,
        cooldown = 0.50,
        source = "wp4500 event_0193 finish candidate",
    },
    -- Broken Butterfly dry-fire: cylinder click when empty. Confirmed live
    -- 2026-07-05 (fires 4x on repeated trigger press, ammo=0/6, window=manual).
    -- Reuses reload_insert WAV (same cylinder-click WEM 13816708).
    [1967149724] = {
        event = "wp4500_dry_fire",
        weapon_id = 4500,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4500 (Broken Butterfly) dry-fire, ch_wp4500.bnk event_0195; WEM 13816708 (same as reload_insert); confirmed live 2026-07-05",
    },

    -- Handcannon reload, converted from the old ammo-delta
    -- insert/finish_on_full_insert WAV emission to confirmed Wwise IDs.
    -- event_0198 fires last before the single-round ammo tick; event_0224
    -- fires after the tick and matches the catalog's own "Reload Finish"
    -- label for this ID.
    -- Draw: base fires on both normal and special; draw_b on normal only;
    -- draw_c on special only.
    [3324641821] = {
        event = "wp4502_draw",
        weapon_id = 4502,
        cooldown = 0.60,
        source = "wp4502 (Handcannon) draw, ch_wp4502.bnk (3 variants WEMs 466736175/716338288/96139898 ~0.29-0.60s); fires on normal+special draw; live-captured 2026-07-06",
    },
    [3094105099] = {
        event = "wp4502_draw_b",
        weapon_id = 4502,
        cooldown = 0.60,
        source = "wp4502 (Handcannon) draw layer B, ch_wp4502.bnk (3 variants WEMs 776343600/347360899/772513110 ~0.35-0.66s); normal draw only; live-captured 2026-07-06",
    },
    [3094105096] = {
        event = "wp4502_draw_c",
        weapon_id = 4502,
        cooldown = 0.60,
        source = "wp4502 (Handcannon) draw layer C, ch_wp4502.bnk (3 variants WEMs 1009037431/615525484/34549052 ~0.21-0.23s); special draw only; live-captured 2026-07-06",
    },
    -- Per-shot cylinder rotation (fires on every shot, like W-870 post-shot pump).
    -- Switch container; 9 medium variants deployed (0.28-0.79s), reverb tails excluded.
    [2702689930] = {
        event = "wp4502_post_shot",
        weapon_id = 4502,
        cooldown = 0.30,
        source = "wp4502 (Handcannon) post-shot cylinder rotation, ch_wp4502.bnk (9v WEMs 381949168/526711272/178720006/240206926/17311511/801644704/88541712/747353870/1037712174 ~0.28-0.79s); fires on every shot; live-captured 2026-07-06",
    },
    [1399173146] = {
        event = "wp4502_dry_fire",
        weapon_id = 4502,
        ammo = 0,
        cooldown = 0.25,
        source = "wp4502 (Handcannon) dry fire / empty trigger click, ch_wp4502.bnk (1 WEM 735519259 ~0.07s); live-captured 2026-07-06",
    },
    [3054041130] = {
        event = "wp4502_aim_in",
        weapon_id = 4502,
        cooldown = 0.40,
        source = "wp4502 (Handcannon) aim_in (3v ~0.35-0.66s), ch_wp4502.bnk; live-confirmed 2026-07-06",
    },
    [3371019536] = {
        event = "wp4502_reload_start",
        weapon_id = 4502,
        cooldown = 0.50,
        source = "wp4502 event_0226 cylinder cartridge ejection (matches catalog label)",
    },
    [120859746] = {
        event = "wp4502_reload_insert",
        weapon_id = 4502,
        cooldown = 0.50,
        source = "wp4502 event_0198 magazine insert candidate",
    },
    [3367659771] = {
        event = "wp4502_reload_finish",
        weapon_id = 4502,
        cooldown = 0.50,
        source = "wp4502 event_0224 finish (matches catalog label)",
    },

    -- Skull Shaker finish: disabled 2026-07-04. event_0219 was originally
    -- picked only because it fired later than event_0209, but live speaker
    -- testing made that late tail feel wrong. The catalog labels event_0219
    -- as an unresolved/control-like double-click, not a confirmed reload
    -- close. Keep per-shell insert + direct post-shot only for now.

    -- Radio dialogue (see docs/RADIO_DIALOGUE_TASK.md). Live capture during
    -- a Hunnigan call (2025-06-27/28, weapon=none) identified event_0240's
    -- ID as a short tone that repeats periodically through the whole call
    -- (fired at both the start and partway through), distinct from the
    -- long ambient static-bed layers and the individual voice-line IDs.
    -- No weapon_id gate: radio calls can happen with any/no weapon
    -- equipped. Routed through RADIO.play_dialogue via the AUDIO.play_radio_ring
    -- handler so it respects the Radio Dialogue UI's enabled/mode/volume
    -- settings instead of the main audio volume.
    [3726123240] = {
        handler = "play_radio_ring",
        cooldown = 1.0,
        source = "radio call ring/connect tone (event ID from Hunnigan call capture)",
    },

    -- -----------------------------------------------------------------------
    -- Fatal kick hit (ch_cha0.bnk, Mercenaries session 2026-07-01).
    -- play_cha0_se_chc_cm_fatal_kick_hit — Leon's kick impact sound.
    -- Appeared in 11/11 fatal_kick windows. Two WAV variants:
    --   [NOMAL]    WEM 123340197 (impact) + random 937888918
    --   [critical] adds extra layers (10086209, 977346746, 239212694)
    -- Game hook play_fatal_kick() is now bypassed for audio (Wwise-only).
    -- -----------------------------------------------------------------------
    [1793304701] = {
        event = "fatal_kick_wwise",
        cooldown = 0.30,
        source = "play_cha0_se_chc_cm_fatal_kick_hit, ch_cha0.bnk event 18166, 11/11 fatal_kick windows",
    },

    -- -----------------------------------------------------------------------
    -- Knife sounds. No weapon_id gate — knife events fire regardless of the
    -- equipped firearm.
    -- Parry: ch_wp_knife_cm.bnk — e129 (3/7 windows), e135 (4/7), e125 (variant
    -- clash sound, confirmed 2026-07-11 Mercenaries parry window; previously
    -- removed as dead campaign hit but is a parry clash variant 3.7s/3.3s).
    -- Hits/actions: campaign sessions 2026-07-07. The 2026-07-01 Mercenaries
    -- audition hit set (e115/e117/e123/e133/e137/e139) never fired in any
    -- campaign capture and was removed 2026-07-07; enemy hits are event
    -- 2846967310 (knife_hit below, same WEM pool as the old e137).
    -- Bank layout: ch_wp_knife_cm.bnk = shared hit/parry/surface;
    -- ch_wp5805.bnk = shared stealth/finisher; per-model swing/draw banks:
    -- ch_wp5000.bnk = Combat Knife, ch_wp5002.bnk = Kitchen Knife (Fighting
    -- wp5001 / Primal wp5006 not captured yet).
    -- -----------------------------------------------------------------------
    [2078013350] = {
        event = "knife_e129",
        cooldown = 0.10,
        suppress_group = "knife_minor",
        suppress_duration = 0.7,
        source = "ch_wp_knife_cm.bnk event 0129, WEMs: 164104009/628438396/251783565 (3/7 parry windows)",
    },
    [3415105559] = {
        event = "knife_e135",
        cooldown = 0.10,
        suppress_group = "knife_minor",
        suppress_duration = 0.7,
        source = "ch_wp_knife_cm.bnk event 0135, WEMs: 845039442/623814290 (4/7 parry windows)",
    },
    [1651038214] = {
        event = "knife_e125",
        cooldown = 0.10,
        suppress_group = "knife_minor",
        suppress_duration = 0.7,
        source = "ch_wp_knife_cm.bnk event 0125, WEMs: 680574874/376198457; parry clash variant (3.7s/3.3s); confirmed 2026-07-11 Mercenaries parry window",
    },
    -- knife_e119 (1058140391), knife_e141 (3964128804): confirmed non-hit, removed 2026-07-01
    [2846967310] = {
        event = "knife_hit",
        cooldown = 0.20,
        suppressed_by = "knife_minor",
        defer = 0.075,
        source = "ch_wp_knife_cm.bnk event 2846967310, WEMs: 169978498/355607135/536982555 (+streamed 67427142/301405840, not in media bank); enemy hit, live-confirmed 2026-07-07 (4x campaign)",
    },
    [1953686865] = {
        event = "knife_surface",
        cooldown = 0.20,
        suppressed_by = "knife_minor",
        defer = 0.075,
        source = "ch_wp_knife_cm.bnk event 1953686865, 11 WEMs in 3 material groups: wood 973634024/404070738/235306242 (WAV 1-3), metal 578613857/747131844/260591387/730478419 (WAV 4-7), water 248642604/522632479/551564106/768805111 (removed from pool 2026-07-07 -- router can't see material, water on dry surfaces sounded wrong); wall/prop/water hit, live-confirmed 2026-07-07 (stone 15x, wood 32x, water 24x)",
    },
    -- knife_grab_finish (1828770915, ch_wp5801.bnk): tried 2026-07-07 for the
    -- grab/QTE finisher; its 4 WEMs turned out to be swing whooshes, not the
    -- stab, and played as random swings. Removed same day — the actual grab
    -- finisher stab audio source is still unidentified (possibly streamed).
    [1074911781] = {
        event = "knife_finish",
        cooldown = 0.50,
        source = "ch_wp5805.bnk event 1074911781, WEMs: 1041256639/118510284/679755354/443484019/854839088; finisher stab (stagger finisher + stealth-kill layer), live-confirmed 2026-07-07",
    },
    -- Finisher flesh-impact layer (ch_cha0.bnk): fires alongside knife_finish.
    -- Three event IDs — likely different enemy types. All share knife_finish_hit stem.
    -- WEMs: 837658032 (1.3s), 66761624 (1.09s), 94172777 (0.94s), 662880470 (0.60s).
    -- Confirmed 2026-07-12 via dry_fire window capture.
    [2456497329] = {
        event = "knife_finish_hit",
        cooldown = 0.80,
        suppress_group = "knife_finish_hit",
        suppress_duration = 1.5,
        source = "ch_cha0.bnk, WEM 837658032 (1.30s); finisher impact layer",
    },
    [1360748365] = {
        event = "knife_finish_hit",
        cooldown = 0.80,
        suppress_group = "knife_finish_hit",
        suppress_duration = 1.5,
        source = "ch_cha0.bnk, WEM 66761624 (1.09s); finisher impact layer",
    },
    [1344092666] = {
        event = "knife_finish_hit",
        cooldown = 0.80,
        suppress_group = "knife_finish_hit",
        suppress_duration = 1.5,
        source = "ch_cha0.bnk, WEMs 94172777/662880470 (0.94s/0.60s); finisher impact layer",
    },
    -- 2008584986 (ch_cha0.bnk): generic blood/hit container (1559 WEMs), fires
    -- during finisher but also randomly in other combat contexts — removed
    -- 2026-07-12 to avoid spurious playback outside finisher animation.
    -- 2764633896 (knife_stealth, ch_wp5805.bnk): REMOVED 2026-07-14 — fires in
    -- ambient context near torch-bearing enemies even without a stealth kill;
    -- confirmed via sound_event_ids.log capture at torch location (2026-07-13).
    -- Re-record stealth kill in an area without torch enemies to get a clean ID.
    [4245295432] = {
        event = "knife_stealth_cb",
        cooldown = 1.00,
        source = "ch_wp5805.bnk event 4245295432, WEMs: 199566050/834573903/606533743; stealth kill stab (combat knife session), live-confirmed 2026-07-07",
    },
    [1597087934] = {
        event = "knife_swing",
        cooldown = 0.20,
        suppressed_by = "knife_minor",
        defer = 0.075,
        source = "ch_wp5000.bnk event 1597087934, WEMs: 1004425820/174665342/316655876; Combat Knife air swing, live-confirmed 2026-07-07 (10x)",
    },
    [1597087905] = {
        event = "knife_swing_hit",
        cooldown = 0.20,
        suppressed_by = "knife_minor",
        defer = 0.075,
        source = "ch_wp5000.bnk event 1597087905, WEMs: 320941809/679873758/209193412; Combat Knife swing-on-hit layer (pairs with knife_hit), live-confirmed 2026-07-07 (3x)",
    },
    -- knife_draw (152060478, ch_wp5000.bnk) and knife_draw_kitchen (3684106924,
    -- ch_wp5002.bnk) removed 2026-07-08: draw and parry share the same button;
    -- the 75ms defer window is not always enough to suppress the draw sound
    -- before parry fires, causing the parry clash to drop. PS5 speaker also
    -- has no draw sound in the native game.
    [1772329428] = {
        event = "knife_swing_kitchen",
        cooldown = 0.20,
        suppressed_by = "knife_minor",
        defer = 0.075,
        source = "ch_wp5002.bnk event 1772329428, WEMs: 27049819/581944157/227214282; Kitchen Knife air swing, live-confirmed 2026-07-07 (8x)",
    },
    -- Experimental footstep-haptics route (docs/HAPTICS_FOOTSTEPS_TASK.md).
    -- Routed through a handler (not a plain `event`) so it can be gated on
    -- IPC.haptics_mode_enabled -- excluded from release v1.0, default off;
    -- no-op (returns false, no audio_events.json write) when disabled.
    --
    -- REVERTED 2026-07-11 to this narrow 3-ID set after two dead ends:
    -- (1) mapping the shared `a5` tag directly instead of enumerating IDs
    -- never matched live (see git history for that attempt); (2) enumerating
    -- ~30 IDs observed across concrete/wood/grass/house captures fixed wood
    -- coverage but broke correctness -- confirmed live in Mercenaries that
    -- those broader IDs are posted by ANY footstep-capable actor (NPCs
    -- included), not just Leon, so haptics fired from nearby enemies/allies
    -- while the player stood still. Tried gating on postEvent's `a1` arg as
    -- a per-actor object handle -- also confirmed wrong, `a1` is IDENTICAL
    -- across every call in a session regardless of event type or actor, not
    -- an object handle at all. No available Wwise postEvent arg reliably
    -- identifies the emitting actor. User's explicit call: prefer this
    -- narrow set (Leon-only, confirmed no NPC bleed) over broader surface
    -- coverage with the correctness bug. If revisiting per-actor filtering,
    -- it needs a different source of truth entirely -- e.g. gating on the
    -- player's own CharacterController velocity/movement state via
    -- REFramework reflection, not Wwise event args.
    [1528453721] = {
        handler = "play_footstep_haptic",
        cooldown = 0.20,
        cooldown_group = "footstep",
        source = "ch_cha0.bnk event 1528453721 (ch_cha0-18156-event); Leon footstep, surface-switched by ch_ground_attribute; previously treated as noise/excluded from parry routing, see docs/MEMORY.md",
    },
    [1332518089] = {
        handler = "play_footstep_haptic",
        cooldown = 0.20,
        cooldown_group = "footstep",
        source = "postEvent 1332518089; Leon footstep, confirmed no NPC bleed 2026-07-11",
    },
    [2453452847] = {
        handler = "play_footstep_haptic",
        cooldown = 0.20,
        cooldown_group = "footstep",
        source = "postEvent 2453452847; Leon footstep, confirmed no NPC bleed 2026-07-11",
    },
    -- Per-surface intensity (concrete/metal/soft volume buckets) was
    -- prototyped 2026-07-11 and removed before the v1.0 release decision --
    -- see git history (commit around "Stage 3 v2 per-surface intensity") and
    -- the project-haptics-experiment memory for the full per-surface ID
    -- lists, the rain-contamination caveat, and the GroundMaterialParams
    -- engine-field lead that wasn't finished. Re-derive from there, don't
    -- restart from scratch, if this gets picked up again.
}

local hook_methods = {
    postRequestInfo = true,
    postEvent = true,
}

local function current_weapon_id_and_ammo()
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or nil
    if not info then return nil, nil end
    return tonumber(info.id), tonumber(info.ammo)
end

local function current_weapon_text()
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or nil
    if not info then return "weapon=none ammo=?/?" end
    return string.format(
        "weapon=%s:%s ammo=%s/%s",
        tostring(info.id or "none"),
        tostring(info.name or "unknown"),
        tostring(info.ammo or "?"),
        tostring(info.ammoMax or "?")
    )
end

local function read_callback_field(obj, getter)
    local ok, value = pcall(function() return obj:call(getter) end)
    if ok and value ~= nil then return value end
    return nil
end

local function event_id_from_managed(managed)
    if not managed then return nil end
    return read_callback_field(managed, "get_EventId")
        or read_callback_field(managed, "get_EventID")
        or read_callback_field(managed, "get_EventHash")
        or read_callback_field(managed, "get_Id")
        or read_callback_field(managed, "get_ID")
end

local function event_id_from_raw(raw)
    if raw == nil then return nil end

    local managed = nil
    pcall(function() managed = sdk.to_managed_object(raw) end)
    local event_id = event_id_from_managed(managed)
    if event_id ~= nil then return event_id end

    local int_value = nil
    pcall(function() int_value = sdk.to_int64(raw) end)
    return int_value
end

local function scan_args_for_mapped_event(args)
    for index = 1, 7 do
        local value = event_id_from_raw(args[index])
        local mapped = event_map[tonumber(value)]
        if mapped then
            return tonumber(value), index, mapped
        end
    end
    return nil, nil, nil
end

local function mapped_event_allowed(mapped, weapon_id, ammo)
    if mapped.weapon_id and tonumber(mapped.weapon_id) ~= tonumber(weapon_id) then return false end
    if mapped.ammo ~= nil and tonumber(mapped.ammo) ~= tonumber(ammo) then return false end
    return true
end

local function emit_mapped(label, event_id, mapped, arg_index, args)
    if not ROUTER.enabled or not mapped then return end
    if not (mapped.event or mapped.handler or mapped.weapon_events) then return end

    local weapon_id, ammo = current_weapon_id_and_ammo()

    -- weapon_events supports one Wwise event ID shared across multiple
    -- weapons that reuse the same sound bank (e.g. Sentinel Nine reusing
    -- SG-09 R's bank): map weapon_id -> per-weapon event name instead of a
    -- single weapon_id + event pair.
    local effective_event = mapped.event
    if mapped.weapon_events then
        effective_event = mapped.weapon_events[tonumber(weapon_id)]
        if not effective_event then return end
        if mapped.ammo ~= nil and tonumber(mapped.ammo) ~= tonumber(ammo) then return end
    elseif not mapped_event_allowed(mapped, weapon_id, ammo) then
        return
    end

    local now = os.clock()

    -- Refresh suppression even when this route's own cooldown would skip the
    -- emit, so rapid parry re-fires keep the mute window alive.
    if mapped.suppress_group then
        local duration = tonumber(mapped.suppress_duration) or 0.7
        ROUTER.suppress_until[mapped.suppress_group] = now + duration
    end
    if mapped.suppressed_by then
        local muted_until = ROUTER.suppress_until[mapped.suppressed_by] or -9999
        if now < muted_until then return end
    end

    local cooldown = tonumber(mapped.cooldown) or 0.20
    -- cooldown_group lets multiple distinct Wwise event IDs that represent
    -- the same physical action (e.g. the footstep L/R pair plus the
    -- surface-switched variant) share one cooldown window, instead of each
    -- ID re-triggering independently and causing a double/triple-fire.
    local cooldown_key = mapped.cooldown_group or event_id
    local key = tostring(cooldown_key) .. ":" .. tostring(effective_event or mapped.handler) .. ":" .. tostring(weapon_id)
    local last = ROUTER.last_emit_at[key] or -9999
    if (now - last) < cooldown then return end

    -- Deferred emit: claim the cooldown now, queue the actual bridge emit for
    -- flush_deferred() on the UpdateBehavior tick. A suppress_group source
    -- (parry) firing inside the defer window cancels the queued entry.
    if mapped.defer then
        ROUTER.last_emit_at[key] = now
        ROUTER.deferred[#ROUTER.deferred + 1] = {
            due = now + (tonumber(mapped.defer) or 0.15),
            event = effective_event,
            handler = mapped.handler,
            suppressed_by = mapped.suppressed_by,
        }
        ROUTER.last_status = "deferred " .. tostring(effective_event or mapped.handler)
        return
    end

    local AUDIO = _G.DualSenseEnhancedAudio
    if not AUDIO then
        ROUTER.last_status = "audio module missing"
        return
    end

    local ok, err
    if mapped.handler then
        local fn = AUDIO[mapped.handler]
        if not fn then
            ROUTER.last_status = "handler missing: " .. tostring(mapped.handler)
            return
        end
        ok, err = pcall(fn)
    else
        if not AUDIO.emit then
            ROUTER.last_status = "audio module missing"
            return
        end
        ok, err = pcall(AUDIO.emit, effective_event)
    end
    if ok then
        ROUTER.last_emit_at[key] = now
        ROUTER.last_error = nil
        ROUTER.last_event = string.format(
            "%.6f %s event_id=%s audio_event=%s arg=%s %s",
            now,
            tostring(label),
            tostring(event_id),
            tostring(effective_event or mapped.handler),
            tostring(arg_index),
            current_weapon_text()
        )
        ROUTER.last_status = "emitted " .. tostring(effective_event or mapped.handler)
    else
        ROUTER.last_error = tostring(err)
        ROUTER.last_status = "emit failed"
    end
end

local function hook_method(type_name, method)
    local method_name = method:get_name()
    local label = type_name .. "." .. tostring(method_name)
    local ok, err = pcall(function()
        sdk.hook(method, function(args)
            if not is_current_generation() then return end
            local event_id, arg_index, mapped = scan_args_for_mapped_event(args)
            if event_id then
                emit_mapped(label, event_id, mapped, arg_index, args)
            end
        end, function(retval)
            return retval
        end)
    end)
    if ok then
        ROUTER.installed_hooks = ROUTER.installed_hooks + 1
        ROUTER.hook_status[label] = "OK"
    else
        ROUTER.hook_status[label] = "ERR " .. tostring(err)
    end
end

local hooks_installed = false

local function install_hooks()
    if hooks_installed then return end
    hooks_installed = true

    local type_name = "soundlib.SoundManager"
    local t = sdk.find_type_definition(type_name)
    if not t then
        ROUTER.hook_status[type_name] = "type not found"
        ROUTER.last_status = "type not found"
        return
    end

    local count = 0
    for _, method in ipairs(t:get_methods() or {}) do
        local ok_name, method_name = pcall(function() return method:get_name() end)
        if ok_name and hook_methods[method_name] == true then
            count = count + 1
            hook_method(type_name, method)
        end
    end

    ROUTER.last_status = "hooks installed: " .. tostring(ROUTER.installed_hooks)
    if count == 0 then
        ROUTER.hook_status[type_name] = "no matching methods"
        ROUTER.last_status = "no matching methods"
    end
    print("[DualSenseEnhancedWwiseAudioRouter] " .. ROUTER.last_status)
end

pcall(install_hooks)

local function flush_deferred()
    local queue = ROUTER.deferred
    if #queue == 0 then return end
    local now = os.clock()
    local i = 1
    while i <= #queue do
        local entry = queue[i]
        if now >= entry.due then
            table.remove(queue, i)
            local muted_until = entry.suppressed_by
                and (ROUTER.suppress_until[entry.suppressed_by] or -9999)
                or -9999
            if now >= muted_until then
                local AUDIO = _G.DualSenseEnhancedAudio
                if AUDIO then
                    if entry.handler and AUDIO[entry.handler] then
                        pcall(AUDIO[entry.handler])
                    elseif entry.event and AUDIO.emit then
                        pcall(AUDIO.emit, entry.event)
                    end
                end
            end
        else
            i = i + 1
        end
    end
end

pcall(function()
    re.on_application_entry("UpdateBehavior", function()
        if not is_current_generation() then return end
        if not hooks_installed then pcall(install_hooks) end
        pcall(flush_deferred)
        local PM = _G.PlayerMovement
        if PM then pcall(PM.update) end
    end)
end)

_G.DualSenseEnhancedWwiseAudioRouter = ROUTER
