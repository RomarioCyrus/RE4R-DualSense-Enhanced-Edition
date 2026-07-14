using System.Text.RegularExpressions;

namespace DualsenseAudioBridge;

/// <summary>
/// Maps game event names to sound file names.
/// Files are resolved from the configured sounds directory.
/// Supports .wav, .mp3, and .aiff.
/// Numbered files such as parry2.wav, parry_2.wav, and parry-v2.wav
/// are treated as random variants of the same event.
/// </summary>
public class SoundMap
{
    private readonly string _soundsDir;
    private readonly Dictionary<string, string> _lastResolved = new();

    // Event name -> file base names, in priority order, without extension.
    private readonly Dictionary<string, string[]> _map = new()
    {
        // Radio dialogue (Phase 1 MVP, see docs/RADIO_DIALOGUE_TASK.md).
        // "radio_test" is a placeholder using an existing confirmed sound
        // until real extracted dialogue WAVs are mapped per line.
        ["radio_test"]   = new[] { "heal_herb" },
        // "radio_ring" is also a placeholder: the real call-tone WAV lives
        // in a Wwise voice/radio bank not yet extracted via FusionTools.
        ["radio_ring"]   = new[] { "qte" },

        // Healing (heal_herb resolves via identity fallback to heal_herb1.wav)
        ["heal_spray"]   = new[] { "heal_spray" },
        ["heal_mixed"]   = new[] { "heal_mixed" },

        // Combat
        ["reload"]       = new[] { "reload" },
        ["wp4000_dry_fire"]     = new[] { "wp4000_dry_fire" },
        ["wp4000_last_shot"]    = new[] { "wp4000_last_shot" },
        ["wp4003_dry_fire"]     = new[] { "wp4003_dry_fire" },
        ["wp4003_last_shot"]    = new[] { "wp4003_last_shot" },
        ["wp4003_reload_finish"] = new[] { "wp4003_reload_finish" },
        ["wp4000_reload_start"]  = new[] { "wp4000_reload_start" },
        ["wp4000_reload_insert"] = new[] { "wp4000_reload_insert" },
        ["wp4000_reload_finish"] = new[] { "wp4000_reload_finish" },
        ["wp4001_reload_start"]  = new[] { "wp4001_reload_start" },
        ["wp4001_reload_insert"] = new[] { "wp4001_reload_insert" },
        ["wp4001_reload_finish"] = new[] { "wp4001_reload_finish" },
        ["wp4001_dry_fire_a"]    = new[] { "wp4001_dry_fire_a" },
        ["wp4001_dry_fire_b"]    = new[] { "wp4001_dry_fire_b" },
        ["wp4002_reload_start"]  = new[] { "wp4002_reload_start" },
        ["wp4002_reload_insert"] = new[] { "wp4002_reload_insert" },
        ["wp4002_reload_finish"] = new[] { "wp4002_reload_finish", "wp4002_reload_finish2" },
        ["wp4002_last_shot"]     = new[] { "wp4002_last_shot" },
        ["wp4002_dry_fire_a"]    = new[] { "wp4002_dry_fire_a" },
        ["wp4002_dry_fire_b"]    = new[] { "wp4002_dry_fire_b" },
        ["wp4003_reload_start"]  = new[] { "wp4003_reload_start" },
        ["wp4003_reload_insert"] = new[] { "wp4003_reload_insert" },
        ["wp4004_reload_start"]  = new[] { "wp4004_reload_start" },
        ["wp4004_reload_insert"] = new[] { "wp4004_reload_insert" },
        ["wp4004_reload_finish"] = new[] { "wp4004_reload_finish" },
        ["wp4004_dry_fire"]      = new[] { "wp4004_dry_fire" },
        ["wp4100_reload_start"]  = new[] { "wp4100_reload_start" },
        ["wp4100_reload_insert"] = new[] { "wp4100_reload_insert" },
        ["wp4100_reload_finish"] = new[] { "wp4100_reload_finish" },
        ["wp4100_dry_fire"] = new[] { "wp4100_dry_fire" },
        ["wp4101_dry_fire"] = new[] { "wp4101_dry_fire" },
        ["wp6001_dry_fire"] = new[] { "wp6001_dry_fire" },
        ["wp4101_reload_start"]  = new[] { "wp4101_reload_start" },
        ["wp4101_reload_insert"] = new[] { "wp4101_reload_insert" },
        ["wp4101_reload_finish"] = new[] { "wp4101_reload_finish" },
        ["wp4102_reload_start"]  = new[] { "wp4102_reload_start" },
        ["wp4102_reload_insert"] = new[] { "wp4102_reload_insert" },
        ["wp4102_reload_finish"] = new[] { "wp4102_reload_finish" },
        ["wp4400_reload_start"]  = new[] { "wp4400_reload_start" },
        ["wp4400_reload_insert"] = new[] { "wp4400_reload_insert" },
        ["wp4400_reload_finish"] = new[] { "wp4400_reload_finish" },
        ["wp4401_reload_start"]   = new[] { "wp4401_reload_start" },
        ["wp4401_reload_release"] = new[] { "wp4401_reload_release" },
        ["wp4401_reload_open"]    = new[] { "wp4401_reload_open" },
        ["wp4401_reload_insert"]  = new[] { "wp4401_reload_insert" },
        ["wp4401_reload_finish"]  = new[] { "wp4401_reload_finish" },
        ["wp4402_reload_release"] = new[] { "wp4402_reload_release" },
        ["wp4402_reload_safety"]  = new[] { "wp4402_reload_safety" },
        ["wp4402_reload_finish"]  = new[] { "wp4402_reload_finish" },
        ["wp4500_reload_start"]  = new[] { "wp4500_reload_start" },
        ["wp4500_reload_insert"] = new[] { "wp4500_reload_insert" },
        ["wp4500_reload_finish"] = new[] { "wp4500_reload_finish" },
        ["wp4500_postshot"]      = new[] { "wp4500_postshot" },
        ["wp4501_reload_start"]  = new[] { "wp4501_reload_start" },
        ["wp4501_reload_insert"] = new[] { "wp4501_reload_insert" },
        ["wp4501_reload_finish"] = new[] { "wp4501_reload_finish" },
        ["wp4502_reload_start"]  = new[] { "wp4502_reload_start" },
        ["wp4502_reload_insert"] = new[] { "wp4502_reload_insert" },
        ["wp4502_reload_finish"] = new[] { "wp4502_reload_finish" },
        ["wp4502_postshot"]      = new[] { "wp4502_postshot" },
        ["wp6001_reload_start"]  = new[] { "wp6001_reload_start" },
        ["wp6001_reload_insert"] = new[] { "wp6001_reload_insert" },
        ["wp6001_reload_finish"] = new[] { "wp6001_reload_finish" },
        ["wp6001_postshot"]      = new[] { "wp6001_postshot" },
        // Sentinel Nine: temporary placeholders reusing SG-09 R's WAVs
        // (mechanically near-identical pistol) until wp6000's own Wwise
        // bank is extracted.
        ["wp6000_dry_fire"]      = new[] { "wp6000_dry_fire" },
        ["wp6000_reload_start"]  = new[] { "wp6000_reload_start" },
        ["wp6000_reload_insert"] = new[] { "wp6000_reload_insert" },
        ["wp6000_last_shot"]     = new[] { "wp6000_last_shot" },
        ["wp6000_reload_finish"] = new[] { "wp6000_reload_finish" },
        // TMP: first-time mapping, WAVs extracted from wp4200's own bank.
        ["wp4200_reload_start"]  = new[] { "wp4200_reload_start" },
        ["wp4200_reload_insert"] = new[] { "wp4200_reload_insert" },
        ["wp4200_reload_finish"] = new[] { "wp4200_reload_finish" },
        // LE 5: first-time mapping, WAVs extracted from wp4202's own bank.
        ["wp4202_reload_start"]  = new[] { "wp4202_reload_start" },
        ["wp4202_reload_insert"] = new[] { "wp4202_reload_insert" },
        ["wp4202_reload_finish"] = new[] { "wp4202_reload_finish" },
        // Chicago Sweeper: first-time mapping, WAVs extracted from wp4201's own bank.
        ["wp4201_reload_start"]  = new[] { "wp4201_reload_start" },
        ["wp4201_reload_insert"] = new[] { "wp4201_reload_insert" },
        ["wp4201_reload_finish"] = new[] { "wp4201_reload_finish" },
        // Bolt Thrower: first-time mapping, WAVs extracted from wp4600's own bank.
        ["wp4600_reload_start"]  = new[] { "wp4600_reload_start" },
        ["wp4600_reload_insert"] = new[] { "wp4600_reload_insert" },
        // UI: attache case (inventory) open/close, quick-select weapon wheel.
        ["ui_inventory_open"]  = new[] { "ui_inventory_open" },
        ["ui_inventory_close"] = new[] { "ui_inventory_close" },
        ["ui_quick_select"]    = new[] { "ui_quick_select" },

        // Per-weapon draw/equip sound (quick-select weapon switch).
        ["wp4000_draw_a"] = new[] { "wp4000_draw_a" },
        ["wp4000_draw"]   = new[] { "wp4000_draw" },
        ["wp4000_draw_c"] = new[] { "wp4000_draw_c" },
        ["wp4100_draw"]   = new[] { "wp4100_draw" },
        ["wp4100_draw_b"] = new[] { "wp4100_draw_b" },
        ["wp4100_draw_c"] = new[] { "wp4100_draw_c" },
        ["wp4101_draw"]   = new[] { "wp4101_draw" },
        ["wp4101_draw_b"] = new[] { "wp4101_draw_b" },
        ["wp4101_draw_c"] = new[] { "wp4101_draw_c" },
        ["wp4102_draw"]   = new[] { "wp4102_draw" },
        ["wp4401_draw_a"] = new[] { "wp4401_draw_a" },
        ["wp4401_draw_b"] = new[] { "wp4401_draw_b" },
        ["wp4401_draw_c"] = new[] { "wp4401_draw_c" },
        ["wp4400_draw_a"] = new[] { "wp4400_draw_a" },
        ["wp4400_draw_b"] = new[] { "wp4400_draw_b" },
        ["wp4400_draw_c"] = new[] { "wp4400_draw_c" },
        ["wp4400_draw_d"] = new[] { "wp4400_draw_d" },
        ["wp4400_draw_e"] = new[] { "wp4400_draw_e" },
        ["wp4400_draw_f"] = new[] { "wp4400_draw_f" },
        ["wp4402_draw"]   = new[] { "wp4402_draw" },
        ["wp4400_dry_fire"] = new[] { "wp4400_dry_fire" },
        ["wp4401_dry_fire"] = new[] { "wp4401_dry_fire" },
        ["wp4402_dry_fire"] = new[] { "wp4402_dry_fire" },

        // Aim-in / aim-out (L2 press/release).
        ["wp4400_aim_in"]  = new[] { "wp4400_aim_in" },
        ["wp4400_aim_out"] = new[] { "wp4400_aim_out" },
        ["wp4401_aim_in"]  = new[] { "wp4401_aim_in" },
        ["wp4401_aim_out"] = new[] { "wp4401_aim_out" },
        ["wp4402_aim_in"]  = new[] { "wp4402_aim_in" },
        ["wp4402_aim_out"] = new[] { "wp4402_aim_out" },
        ["wp4101_aim_in"]  = new[] { "wp4101_aim_in" },
        ["wp4100_aim_in"]  = new[] { "wp4100_aim_in" },
        ["wp6001_aim_in"]  = new[] { "wp6001_aim_in" },
        ["wp4000_aim_in"]  = new[] { "wp4000_aim_in" },
        ["wp4001_aim_in"]  = new[] { "wp4001_aim_in" },
        ["wp4001_aim_out"] = new[] { "wp4001_aim_out" },
        ["wp4003_aim_in"]  = new[] { "wp4003_aim_in" },
        ["wp4003_aim_out"] = new[] { "wp4003_aim_out" },
        ["wp4002_aim_in"]  = new[] { "wp4002_aim_in" },
        ["wp4002_aim_out"] = new[] { "wp4002_aim_out" },
        ["wp4004_aim_in"]  = new[] { "wp4004_aim_in" },
        ["wp4004_aim_out"] = new[] { "wp4004_aim_out" },
        ["wp6000_aim_in"]  = new[] { "wp6000_aim_in" },
        ["wp6000_aim_out"] = new[] { "wp6000_aim_out" },

        ["empty_mag"]    = new[] { "empty_click" },
        ["parry"]        = new[] { "parry" },
        ["fatal_kick"]   = new[] { "fatal_kick" },
        ["knife_hit"]    = new[] { "knife_hit" },
        ["grab"]         = new[] { "grab" },
        ["qte"]          = new[] { "qte" },

        // Items
        ["item_pickup"]  = new[] { "item_pickup", "pickup_sound" },
        ["item_combine"] = new[] { "item_combine" },

        // UI / World
        ["save"]         = new[] { "typewriter" },
        ["merchant"]     = new[] { "merchant" },

        // HP warning
        ["low_hp"]       = new[] { "heartbeat" },
        // low_hp_end has no sound; it signals the bridge to stop looping later.
    };

    private static readonly string[] Extensions = { ".wav", ".mp3", ".aiff" };

    public SoundMap(string soundsDir)
    {
        _soundsDir = soundsDir;
    }

    /// <summary>
    /// Resolve event name to full file path.
    /// Returns null if event unknown or file not found.
    ///
    /// Falls back to treating the event name itself as the WAV stem when
    /// there's no explicit entry in <see cref="_map"/>. Most entries are a
    /// 1:1 identity mapping (event name == WAV stem) added purely so a new
    /// Wwise-confirmed sound could be wired up -- those no longer need a
    /// code change/rebuild at all, just drop the WAV next to the others.
    /// Only add an explicit `_map` entry when the event name differs from
    /// the WAV stem (aliases, multiple candidate WAVs, etc.).
    /// </summary>
    public string? Resolve(string eventName)
    {
        var baseNames = _map.TryGetValue(eventName, out var mapped)
            ? mapped
            : new[] { eventName };

        var candidates = new List<string>();
        foreach (var baseName in baseNames)
        {
            candidates.AddRange(FindVariants(baseName));
        }

        candidates = candidates
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (candidates.Count == 0)
            return null;

        if (candidates.Count == 1)
        {
            _lastResolved[eventName] = candidates[0];
            return candidates[0];
        }

        _lastResolved.TryGetValue(eventName, out var previous);
        var choices = candidates
            .Where(path => !string.Equals(path, previous, StringComparison.OrdinalIgnoreCase))
            .ToList();
        var selected = choices[Random.Shared.Next(choices.Count)];
        _lastResolved[eventName] = selected;
        return selected;
    }

    private IEnumerable<string> FindVariants(string baseName)
    {
        if (!Directory.Exists(_soundsDir))
            return Enumerable.Empty<string>();

        var stemPattern = new Regex(
            "^" + Regex.Escape(baseName) + @"(?:[_-]?(?:v|variant)?\d+)?$",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        return Directory.EnumerateFiles(_soundsDir)
            .Where(path => Extensions.Contains(
                Path.GetExtension(path),
                StringComparer.OrdinalIgnoreCase))
            .Where(path => stemPattern.IsMatch(
                Path.GetFileNameWithoutExtension(path)));
    }

    public IEnumerable<string> KnownEvents => _map.Keys;
}
