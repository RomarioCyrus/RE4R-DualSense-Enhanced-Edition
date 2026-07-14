# Weapon Audio Status

Single source of truth for per-weapon Wwise audio mapping progress. Scan
this table first before starting new weapon-audio work — don't re-derive
status from `MEMORY.md` prose or git history.

Legend: ✅ confirmed + deployed · ⏳ candidate found, not yet confirmed/deployed
· ➖ confirmed not to exist (don't re-search) · ❌ not yet investigated

| Weapon (`id`) | Start | Insert | Finish | Dry fire | Last shot | Draw | Aim-in | Aim-out |
|---|---|---|---|---|---|---|---|---|
| SG-09 R (`4000`) | ✅ hook | ✅ | ✅ | ✅ | ✅ | ✅ special only (normal draw has none) | ✅ | ➖ |
| Punisher (`4001`) | ✅ hook | ✅ | ✅ | ✅ 2-stage handler | ✅ | ✅ `3698896644` normal draw (3v); special draw: `753704067` draw_b (3v) + `1397185082` draw_c (4v) + `3208891162` draw_d (3v); live-confirmed 2026-07-06 | ✅ | ✅ handler (was broken: `712539726` duplicate key fixed 2026-07-02) |
| Red9 (`4002`) | ✅ hook | ✅ `2412561847` (3 variants, WEMs 489815732/774321839/812627257); insert fix 2026-07-06 (prior WAV was draw WEM by mistake) | ✅ `2993296297` event_0252 bolt-close confirmed 2026-07-05 | ✅ 2-stage handler | ✅ | ✅ `276251930` normal draw (3v); special draw: `2530110965` draw_b (3v) + `3383247231` draw_c (3v); live-confirmed 2026-07-06 | ✅ | ✅ handler (was broken: `3924820871` duplicate key fixed 2026-07-02) |
| Blacktail (`4003`) | ✅ hook | ✅ | ✅ | ✅ | ✅ | ✅ `2132585249` event_0258 (3 variants) normal draw; `3949149412` event_0280 + `3988807512` event_0282 special draw layers confirmed 2026-07-05 | ✅ | ✅ (reused generic `event_0274`) |
| Matilda (`4004`) | ✅ hook | ✅ | ✅ handler | ✅ | ➖ no ch_wp4004 candidate in last_shot window (2026-07-06); prior bank candidates `1518221001`/`2651947668` appeared in reload_insert window, not last_shot | ✅ `164257408` draw (3v) + `4245683862` draw_b (3v) + `4245683861` draw_c (3v); live-confirmed 2026-07-06 | ✅ | ✅ (shared ID/handler with Finish) |
| Sentinel Nine (`6000`) | ✅ hook | ✅ | ➖ (5 attempts, no live ID) | ✅ | ✅ | ✅ `3740539746` draw_a (3v) + `2169289773` draw_b (2v) + `1049114615` draw_c (2v) confirmed special draw 2026-07-05; bank: ch_wp6000.sbnk in re_dlc_stm_2109308.pak | ✅ (bank-unconfirmed) | ✅ (bank-unconfirmed) |
| W-870 (`4100`) | ➖ (per-shell only) | ✅ | ➖ (2-phase post-shot instead) | ✅ | n/a (shotgun) | ✅ 3-stage | ✅ | ➖ |
| Riot Gun (`4101`) | ➖ (per-shell only) | ✅ | ✅ | ✅ | n/a | ✅ 3-stage (same for normal/special) | ✅ | ➖ |
| Striker (`4102`) | ➖ (per-shell only) | ✅ | ➖ no ch_wp4102 event in reload_finish window; only generic `3468325258` (no weapon bank) (confirmed 2026-07-06) | ➖ (no live ID after 4 attempts; needs input-hook to do properly, declined) | n/a | ✅ single-stage | ✅ `2850476286` (2v ~0.27-0.38s) shared aim_in/aim_out; live-confirmed 2026-07-06 | ✅ shared with aim_in |
| SR M1903 (`4400`) | ➖ (per-shell only) | ✅ | ➖ (confirmed no finish stage) | ✅ | ➖ `2252083765` fires on every shot incl. last; no dedicated last_shot event (confirmed 2026-07-06) | ✅ 5-stage special (normal draw has no unique stage) | ✅ | ✅ (reused from former draw stage) |
| Stingray (`4401`) | ➖ (removed, no live ID) | ✅ `3683820930` (already routed; STATUS was stale) | ✅ | ✅ | ✅ `1122442048` (3v ~0.31-0.46s), ammo=0 gate; live-confirmed 2026-07-06 | ✅ 2-stage special + ✅ normal draw `1764992833` confirmed 2026-07-04 | ✅ | ✅ (`wp4401_draw_c.wav` copied as `wp4401_aim_out.wav`, confirmed 2026-07-04) |
| CQBR (`4402`) | ➖ no ch_wp4402 event in reload_start window (confirmed 2026-07-07) | ✅ `1920728793` insert_b (3v ~0.22s) secondary magazine click; live-confirmed 2026-07-07 (primary `event_0216` rejected earlier) | ✅ | ✅ | ➖ no dedicated last_shot sound (confirmed 2026-07-07) | ✅ single-stage | ✅ | ✅ |
| Broken Butterfly (`4500`) | ✅ hook (~0.9s late) | ✅ | ✅ | ✅ `1967149724` event_0195 cylinder click confirmed 2026-07-05 | ✅ `4248629768` post-shot cylinder cycle (4v WEMs 562261101/502390063/182769156/54444553 ~0.37-0.52s); fires on every shot; live-confirmed 2026-07-06 | ✅ `302927071` draw (3v) + `2926359449` draw_b (3v) + `3816064135` draw_c (1v); 3-stage cylinder sequence; live-confirmed 2026-07-06 | ✅ `4007639528` (1v ~0.27s, variants 1+2 silent); live-confirmed 2026-07-06 | ➖ no aim_out sound in game |
| Handcannon (`4502`) | ✅ hook (~0.9s late) | ✅ | ✅ | ✅ `1399173146` (1v ~0.07s); live-confirmed 2026-07-06 | ➖ revolver, no last_shot mechanic | ✅ `2702689930` post-shot cylinder rotation (9v ~0.28-0.79s); fires on every shot; live-confirmed 2026-07-06 | ✅ `3324641821` draw (3v) + `3094105099` draw_b (3v, normal only) + `3094105096` draw_c (3v, special only); live-confirmed 2026-07-06 | ✅ `3054041130` (3v ~0.35-0.66s); live-confirmed 2026-07-06 | ➖ no aim_out sound |
| Killer7 (`4501`) | ✅ `1484058684` reload_start (1v ~0.49s); live-confirmed 2026-07-06 | ✅ `1039594587` + `3151071005` insert_b (3v) | ➖ no dedicated finish event; `1484058684` re-triggers at finish via 1.0s cooldown | ✅ `1194393411` (1v ~0.07s); live-confirmed 2026-07-06 | ✅ `1388742891` (3v ~0.56-0.60s); empty-gun shot; live-confirmed 2026-07-06 | ✅ `3966122408` draw (3v) + `3151071006` draw_b (3v, also fires on reload) + `1766302611` draw_c (3v, special only) + `2557856193` draw_d (3v, special only); live-confirmed 2026-07-06 | ✅ `3317704895` (3v ~0.21-0.34s); live-confirmed 2026-07-06 | ➖ no aim_out sound in game |
| Skull Shaker (`6001`) | ✅ `1840028007` (1v ~0.30s) + `2246536536` (3v ~0.61s) + `814106828` (3v ~0.45-0.55s); 3-layer tray open; live-confirmed 2026-07-06 | ✅ | ✅ event_0219 `1840028004` WEM 215698335 confirmed 2026-07-04 | ✅ | n/a | ✅ `960381449` (6v ~0.30-0.43s), switch container normal sub-group; no special draw; live-confirmed 2026-07-06 | ✅ | ➖ |
| TMP (`4200`) | ✅ hook | ✅ | ✅ | ✅ `2462166917` (4v ~0.51-0.59s); live-confirmed 2026-07-06 | ➖ no mechanic | ✅ `2093308842` draw (3v) + `3595403541` draw_b + `466731380` draw_c (same WEMs as b) + `3574738629` draw_d + `3413842159` draw_e + `466731383` draw_f; draw_b–f special only; live-confirmed 2026-07-06 | ➖ no ch_wp4200 candidate found | ➖ no ch_wp4200 candidate found |
| Chicago Sweeper (`4201`) | ✅ hook | ✅ | ✅ | ✅ `3428451702` (3v ~0.19-0.30s); live-confirmed 2026-07-06 | ➖ only gunshot+echo candidates, rejected | ✅ `2610600561` draw (3v) + `232029062` draw_b (3v, normal+special) + `3049987048` draw_c (3v, special only) + `665041300` draw_d (3v, special only); live-confirmed 2026-07-06 | ✅ draw_b fires in aim context, acceptable | ➖ no aim_out sound in game |
| LE 5 (`4202`) | ✅ `345236802` start click (3v ~0.17s) + `1937401584` mag eject (3v ~0.70-0.78s); live-confirmed 2026-07-06 | ✅ | ✅ | ✅ `641294031` (3v ~0.14-0.20s); live-confirmed 2026-07-06 | ➖ no last_shot in game | ✅ `795674380` draw (3v) + `3335860215` draw_b (3v) + `3784264661` draw_c (3v) + `2471587121` draw_d (3v); draw_b/c/d special only; live-confirmed 2026-07-06 | ✅ `746214667` (3v); shared aim_in+aim_out; live-confirmed 2026-07-06 | ✅ shared with aim_in |
| Bolt Thrower (`4600`) | ✅ hook | ✅ | ➖ (no live ID found) | ✅ `1756416417` (1v ~0.07s); live-confirmed 2026-07-06 | ✅ `2370660519` shot first-stage (4v ~0.28-0.45s), fires per-shot; live-confirmed 2026-07-06 | ✅ `300966990` (6v ~0.29-0.64s), ch_wp4600.bnk; switch container; live-confirmed 2026-07-06 | ✅ `922138092` (2v ~0.57s) + `2857008769` (1v ~0.18s); live-confirmed 2026-07-06 | ✅ `3051463304` (2v ~0.43-0.47s); live-confirmed 2026-07-06 |

## Character action sounds (non-weapon)

Routed via `wwise_audio_router.lua` with no `weapon_id` gate. Game hooks
(`play_parry`, `play_fatal_kick`) are **bypassed** for audio — Wwise events
handle playback directly. The earlier `Melee.onHitAttack` Lua hook for
`knife_hit` was removed 2026-07-08 (caused double-fire alongside the Wwise
route for `2846967310`).

| Action | Wwise ID | Bank / event | WAV files | Status |
|---|---|---|---|---|
| Fatal kick hit | `1793304701` | `ch_cha0.bnk` event 18166 `play_cha0_se_chc_cm_fatal_kick_hit` | `fatal_kick_wwise.wav` | ✅ confirmed 11/11 Mercenaries windows (2026-07-01) |
| Parry / knife clash A | `3415105559` | `ch_wp_knife_cm.bnk` event 0135 | `knife_e1351.wav`, `knife_e1352.wav` | ✅ confirmed 4/7 parry windows (Mercenaries 2026-07-01) |
| Parry / knife clash B | `2078013350` | `ch_wp_knife_cm.bnk` event 0129 | `knife_e1291.wav`–`knife_e1293.wav` | ✅ confirmed 3/7 parry windows (Mercenaries 2026-07-01) |
| Parry / knife clash C | `1651038214` | `ch_wp_knife_cm.bnk` event 0125 | `knife_e1251.wav` (3.7s), `knife_e1252.wav` (3.3s) | ✅ confirmed 2026-07-11 Mercenaries parry window; previously misclassified as dead campaign hit |
| Knife hit (enemy) | `2846967310` | `ch_wp_knife_cm.bnk` | `knife_hit1.wav`–`knife_hit3.wav` | ✅ live-confirmed 2026-07-07 campaign (4×); +2 streamed WEMs not extractable |
| Knife surface hit | `1953686865` | `ch_wp_knife_cm.bnk` | `knife_surface1.wav`–`knife_surface7.wav` | ✅ live-confirmed 2026-07-07 (stone 15×, wood 32×, water 24×); wood WAV 1-3, metal 4-7; water group intentionally excluded (router can't see material) |
| Knife finisher stab | `1074911781` | `ch_wp5805.bnk` (shared finisher bank) | `knife_finish1.wav`–`knife_finish5.wav` | ✅ live-confirmed 2026-07-07 (stagger finisher + stealth layer) |
| Knife finisher impact A | `2456497329` | `ch_cha0.bnk` | `knife_finish_hit1.wav` (1.30s) | ✅ confirmed 2026-07-12; flesh-impact layer, plays alongside finisher stab |
| Knife finisher impact B | `1360748365` | `ch_cha0.bnk` | `knife_finish_hit2.wav` (1.09s) | ✅ confirmed 2026-07-12 |
| Knife finisher impact C | `1344092666` | `ch_cha0.bnk` | `knife_finish_hit3.wav` (0.94s), `knife_finish_hit4.wav` (0.60s) | ✅ confirmed 2026-07-12 |
| Stealth kill (kitchen session) | `2764633896` | `ch_wp5805.bnk` | `knife_stealth1.wav`–`knife_stealth3.wav` | ✅ live-confirmed 2026-07-07 |
| Stealth kill (combat session) | `4245295432` | `ch_wp5805.bnk` | `knife_stealth_cb1.wav`–`knife_stealth_cb3.wav` | ✅ live-confirmed 2026-07-07 |
| Combat Knife swing | `1597087934` | `ch_wp5000.bnk` | `knife_swing1.wav`–`knife_swing3.wav` | ✅ live-confirmed 2026-07-07 (10×) |
| Combat Knife swing-on-hit | `1597087905` | `ch_wp5000.bnk` | `knife_swing_hit1.wav`–`knife_swing_hit3.wav` | ✅ live-confirmed 2026-07-07 (pairs with knife_hit) |
| Combat Knife draw | `152060478` | `ch_wp5000.bnk` | `knife_draw1.wav`–`knife_draw3.wav` | ➖ removed 2026-07-08: shares button with parry; WAVs deleted. Revisit with longer defer once parry coverage is complete |
| Kitchen Knife swing | `1772329428` | `ch_wp5002.bnk` | `knife_swing_kitchen1.wav`–`knife_swing_kitchen3.wav` | ✅ live-confirmed 2026-07-07 (8×) |
| Kitchen Knife draw | `3684106924` | `ch_wp5002.bnk` | `knife_draw_kitchen1.wav`–`knife_draw_kitchen3.wav` | ➖ removed 2026-07-08: same reason as Combat Knife draw |
| Footstep (haptics future) | `1528453721` | `ch_cha0.bnk` event 18156, gated by `ch_ground_attribute` | — | ⏳ reserved for haptics, not routed |

Knife priority mechanics (2026-07-07): the minor knife routes (hit,
surface, swings) carry `suppressed_by = "knife_minor"` and `defer = 0.075` —
their emits are queued for 75 ms and dropped if a parry fires meanwhile.
Draw routes removed 2026-07-08 (see table).

**Parry coverage (updated 2026-07-11).** Three events now routed: e129 + e135
(Mercenaries 2026-07-01) + e125 (Mercenaries 2026-07-11, previously
misclassified). User confirmed parry sounds working. Monitoring for remaining
gaps — if silent parry types are found, they likely fire events in a different
bank (`ch_cha0.bnk` candidates `2871271748` / `3468325268` / `2008584986` not
yet auditoned).

Knife session notes (2026-07-07, campaign):
- The 2026-07-01 Mercenaries hit set (`e115`/`e117`/`e123`/`e133`/
  `e137`/`e139`) never fired in campaign captures — removed from the router,
  superseded by `knife_hit` (2846967310, same WEM pool as old e137).
  Exception: `e125` (1651038214) — re-confirmed 2026-07-11 as parry clash
  variant, re-added.
- Bank layout: `ch_wp_knife_cm.bnk` shared hit/parry/surface;
  `ch_wp5805.bnk` shared stealth/finisher (24 events, mostly unexplored);
  per-model swing/draw banks `ch_wp5000` (Combat), `ch_wp5002` (Kitchen).
  Fighting Knife (`wp5001`) and Primal Knife (`wp5006`) banks not captured —
  their swings/draws are silent on the speaker until a future session.
- Grab/QTE finisher: tried `1828770915` (`ch_wp5801.bnk`) — its 4 WEMs are
  swing whooshes, not the stab; removed. The actual grab-finisher stab source
  is unidentified (possibly streamed).
- No charged-attack mechanic exists in RE4R; knife-throw not captured.
- Rejected 1196205411 (no WEMs in chain, set-switch style event).

Removed after audition (2026-07-01): `knife_e119` (1058140391), `knife_e141` (3964128804) — confirmed non-hit sounds. Partial removals: `knife_e115` variants 2,4; `knife_e117` variants 3-5; `knife_e123` variants 1-3.

## Remaining scope (updated 2026-07-07)

All base-game weapons are fully investigated — no open ❌ entries remain.
Every role is either ✅ (confirmed + deployed) or ➖ (confirmed absent).

- **Separate Ways DLC weapons** — explicitly out of scope until decided otherwise.

## Known noise-floor IDs

See `AGENTS.md` → "Wwise Event Capture & Deployment Workflow" for the
full list and capture methodology. Do not re-discover this from scratch.
