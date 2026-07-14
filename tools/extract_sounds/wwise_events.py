"""Wwise capture-session helper: bank index, log analysis, WEM extraction.

Subcommands (run with `py wwise_events.py <cmd> ...`):

  index                     Rebuild event_bank_index.json from all cached
                            weapon .bnk files. Run once, and again only after
                            new banks are added to the cache.
  analyze <log>             Parse a sound_event_ids.log capture: drop
                            noise-floor IDs, annotate every remaining event
                            with its bank (from the index) and whether it is
                            already routed in wwise_audio_router.lua. Prints
                            only genuinely new candidates plus a summary.
  extract <event_id> [--stem NAME] [--out DIR]
                            Find the event's bank via the index, walk the
                            event->action->container->SFX chain, pull the WEMs
                            out of the matching _media.bnk and convert them to
                            numbered WAVs with vgmstream (NAME1.wav, ...).
  manifest [--out PATH]     Read all `event = ...` entries from
                            wwise_audio_router.lua, walk their HIRC chains,
                            and generate/update sounds_manifest.json with one
                            entry per WEM variant ({event_name}1, {name}2, ...).
                            Merges into any existing manifest without touching
                            hook-based reload entries. Run after routing new
                            events, then commit sounds_manifest.json so users
                            can extract everything via setup_sounds.bat.

Bank cache default: %LOCALAPPDATA%/Temp/re4r_txtp_regen/bnk (see AGENTS.md).
"""
import argparse
import json
import os
import re
import struct
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BANK_DIR = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Temp", "re4r_txtp_regen", "bnk")
INDEX_PATH = os.path.join(SCRIPT_DIR, "event_bank_index.json")
MANIFEST_PATH = os.path.join(SCRIPT_DIR, "sounds_manifest.json")
ROUTER_PATH = os.path.normpath(os.path.join(
    SCRIPT_DIR, "..", "..", "src", "reframework", "autorun",
    "DualSenseEnhanced", "wwise_audio_router.lua"))
VGMSTREAM = os.path.join(SCRIPT_DIR, "vgmstream", "vgmstream-cli.exe")
PAK_PREFIX = "natives/stm/_chainsaw/sound/wwise"

# Ambient/footstep/cloth noise floor -- IDs that recur in almost every
# capture regardless of weapon or action. Mirror of the list in
# AGENTS.md -> "Wwise Event Capture & Deployment Workflow". IDs differing
# by 1-3 from these are treated as the same noise family by fuzzy match.
NOISE_FLOOR = {
    807178836, 1332518089, 2250845221, 2250845243, 2453452847,
    2718174961, 3052338289, 3328592937, 3397245785, 3418362288,
    194540406, 1166837647, 1166837648, 1166837649, 2086827955,
    1857863324, 1401815104, 2095290572, 3545586723,
    2756336461, 2756336463,
}

# Known generic (non-weapon-bank) IDs already understood and deliberately
# not routed / disabled -- documented in wwise_audio_router.lua comments.
KNOWN_GENERIC = {
    3333492782: "generic weapon-grab cue (ch_cha0 event_18206, every switch)",
    3898613260: "generic weapon-grab cue (ch_cha0 event_18206, every switch)",
    272828262: "disabled: fires randomly during live fire / reload start",
    670443406: "disabled: ambient noise family, fires while AFK",
}


def is_noise(eid):
    if eid in NOISE_FLOOR:
        return True
    return any(abs(eid - n) <= 3 for n in NOISE_FLOOR)


# ---------------------------------------------------------------- bnk parsing

def parse_chunks(path):
    with open(path, "rb") as f:
        data = f.read()
    pos, chunks = 0, {}
    while pos + 8 <= len(data):
        tag = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        chunks[tag] = data[pos + 8:pos + 8 + size]
        pos += 8 + size
    return chunks


def parse_hirc(path):
    """Return {object_id: (type, data)} for every HIRC object in the bank."""
    body = parse_chunks(path).get(b"HIRC")
    if body is None:
        return {}
    count = struct.unpack_from("<I", body, 0)[0]
    p, objs = 4, {}
    for _ in range(count):
        otype = body[p]
        osize = struct.unpack_from("<I", body, p + 1)[0]
        odata = body[p + 5:p + 5 + osize]
        objs[struct.unpack_from("<I", odata, 0)[0]] = (otype, odata)
        p += 5 + osize
    return objs


def walk_event(objs, oid, seen=None, wems=None, log=None, depth=0):
    """Walk event->action->container->SFX; return WEM ids in tree order.

    Container children are found by scanning for 4-byte-aligned known object
    ids, but recursion is limited to sound/container types (2/5/6/9) so the
    DirectParentID field can't walk back up into the actor-mixer tree.
    Sound SFX stores AudioFileId at data[9..12] (not data[8]).
    """
    seen = set() if seen is None else seen
    wems = [] if wems is None else wems
    log = [] if log is None else log
    if oid in seen or oid not in objs:
        return wems, log
    seen.add(oid)
    otype, data = objs[oid]
    pad = "  " * depth
    if otype == 4:  # Event
        n = data[4]
        log.append(f"{pad}event {oid} ({n} actions)")
        for i in range(n):
            aid = struct.unpack_from("<I", data, 5 + i * 4)[0]
            walk_event(objs, aid, seen, wems, log, depth + 1)
    elif otype == 3:  # Action
        ref = struct.unpack_from("<I", data, 6)[0]
        log.append(f"{pad}action {oid} type={data[5]} -> {ref}")
        walk_event(objs, ref, seen, wems, log, depth + 1)
    elif otype == 2:  # Sound SFX
        wem = struct.unpack_from("<I", data, 9)[0]
        log.append(f"{pad}sfx {oid} WEM={wem}")
        wems.append(wem)
    elif otype in (5, 6, 9):  # Random / Switch / Layer container
        log.append(f"{pad}container {oid} type={otype}")
        for off in range(4, len(data) - 3):
            v = struct.unpack_from("<I", data, off)[0]
            if v != oid and v in objs and v not in seen \
                    and objs[v][0] in (2, 5, 6, 9):
                walk_event(objs, v, seen, wems, log, depth + 1)
    else:
        log.append(f"{pad}obj {oid} type={otype} (skip)")
    return wems, log


# ------------------------------------------------------------------- index

def cmd_index(args):
    bank_dir = args.bank_dir
    index = {}
    banks = sorted(f for f in os.listdir(bank_dir)
                   if f.endswith(".bnk") and not f.endswith("_media.bnk"))
    for bank in banks:
        objs = parse_hirc(os.path.join(bank_dir, bank))
        events = [i for i, (t, _) in objs.items() if t == 4]
        for eid in events:
            index[str(eid)] = bank
        print(f"{bank}: {len(events)} events")
    with open(INDEX_PATH, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=0, sort_keys=True)
    print(f"\n{len(index)} events from {len(banks)} banks -> {INDEX_PATH}")


def load_index():
    if not os.path.exists(INDEX_PATH):
        sys.exit(f"index not found: {INDEX_PATH} -- run `wwise_events.py index` first")
    with open(INDEX_PATH, encoding="utf-8") as f:
        return {int(k): v for k, v in json.load(f).items()}


def load_routed():
    """Return {event_id: first line of its router entry} from the Lua router."""
    routed = {}
    with open(ROUTER_PATH, encoding="utf-8") as f:
        text = f.read()
    for m in re.finditer(
            r"\[(\d+)\]\s*=\s*\{\s*\n\s*(?:event|handler)\s*=\s*\"([^\"]+)\"",
            text):
        routed[int(m.group(1))] = m.group(2)
    return routed


# ------------------------------------------------------------------ analyze

LOG_EVENT_RE = re.compile(r"event_id=(\d+)")
LOG_WEAPON_RE = re.compile(r"weapon=(\S+)")
LOG_WINDOW_RE = re.compile(r"window=(\S+)")


def cmd_analyze(args):
    index = load_index()
    routed = load_routed()
    # eid -> {kinds, weapons, windows, count}
    hits = {}
    with open(args.log, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            m = LOG_EVENT_RE.search(line)
            if not m:
                continue
            eid = int(m.group(1))
            # postEvent lines carry small per-session request ids, not Wwise
            # event hashes; onEndOfEvent is confirmation-only. Keep both out
            # of the candidate set but count onEndOfEvent separately.
            kind = parts[1] if parts[1] in ("preroll", "candidate") else None
            if "postEvent" in line and "postRequestInfo" not in line:
                continue
            if kind is None:
                continue
            h = hits.setdefault(eid, {"count": 0, "kinds": set(),
                                      "weapons": set(), "windows": set()})
            h["count"] += 1
            h["kinds"].add(kind)
            wm = LOG_WEAPON_RE.search(line)
            if wm:
                h["weapons"].add(wm.group(1).split(":")[0].split(" ")[0])
            wn = LOG_WINDOW_RE.search(line)
            if wn:
                h["windows"].add(wn.group(1))

    new, known = [], []
    for eid, h in sorted(hits.items(), key=lambda kv: -kv[1]["count"]):
        bank = index.get(eid)
        if is_noise(eid):
            status = "NOISE"
        elif eid in routed:
            status = f"ROUTED -> {routed[eid]}"
        elif eid in KNOWN_GENERIC:
            status = f"KNOWN-GENERIC: {KNOWN_GENERIC[eid]}"
        elif bank:
            status = f"NEW in {bank}"
        else:
            status = "NEW (no weapon bank -- generic/other)"
        row = (eid, h["count"], ",".join(sorted(h["kinds"])),
               ",".join(sorted(h["weapons"])), ",".join(sorted(h["windows"])),
               status)
        (new if status.startswith("NEW in") else known).append(row)

    def show(rows, title):
        if not rows:
            return
        print(f"\n== {title} ==")
        print(f"{'event_id':>11}  {'n':>3}  {'kind':<18} {'wpn tag':<10} {'window':<12} status")
        for eid, n, kinds, wpns, wins, status in rows:
            print(f"{eid:>11}  {n:>3}  {kinds:<18} {wpns:<10} {wins:<12} {status}")

    show(new, "NEW WEAPON-BANK CANDIDATES (act on these)")
    if args.all:
        show(known, "everything else (noise / routed / generic)")
    else:
        print(f"\n({len(known)} noise/routed/generic ids hidden -- use --all to show)")


# ------------------------------------------------------------------ extract

def cmd_extract(args):
    index = load_index()
    eid = args.event_id
    bank = index.get(eid)
    if not bank:
        sys.exit(f"{eid}: not found in index (generic/non-weapon event?)")
    bank_path = os.path.join(args.bank_dir, bank)
    media_path = os.path.join(args.bank_dir, bank.replace(".bnk", "_media.bnk"))
    objs = parse_hirc(bank_path)
    wems, log = walk_event(objs, eid)
    print("\n".join(log))
    if not wems:
        sys.exit("no WEMs found in chain")

    chunks = parse_chunks(media_path)
    didx, data = chunks[b"DIDX"], chunks[b"DATA"]
    table = {}
    for i in range(0, len(didx), 12):
        wid, off, ln = struct.unpack_from("<III", didx, i)
        table[wid] = (off, ln)

    stem = args.stem or str(eid)
    os.makedirs(args.out, exist_ok=True)
    for n, wid in enumerate(wems, 1):
        if wid not in table:
            print(f"WEM {wid}: NOT in {os.path.basename(media_path)} (streamed?)")
            continue
        off, ln = table[wid]
        wem_path = os.path.join(args.out, f"{stem}{n}.wem")
        wav_path = os.path.join(args.out, f"{stem}{n}.wav")
        with open(wem_path, "wb") as f:
            f.write(data[off:off + ln])
        r = subprocess.run([VGMSTREAM, "-o", wav_path, wem_path],
                           capture_output=True, text=True)
        info = next((l for l in r.stdout.splitlines() if "total samples" in l), "")
        os.remove(wem_path)
        print(f"WEM {wid} -> {wav_path}  {info.strip()}")


def load_wwise_events():
    """Return {event_id: event_name} for router entries with `event =` (not handler =)."""
    routed = {}
    with open(ROUTER_PATH, encoding="utf-8") as f:
        text = f.read()
    for m in re.finditer(
            r"\[(\d+)\]\s*=\s*\{\s*\n\s*event\s*=\s*\"([^\"]+)\"",
            text):
        routed[int(m.group(1))] = m.group(2)
    return routed


def cmd_manifest(args):
    """Update sounds_manifest.json from all Wwise-routed events in the router."""
    index = load_index()
    routed = load_wwise_events()

    new_entries = {}
    skipped = []

    for eid in sorted(routed.keys()):
        event_name = routed[eid]
        bank = index.get(eid)
        if not bank:
            skipped.append(f"{eid} ({event_name}): not in bank index (hook-based or generic)")
            continue

        bank_path = os.path.join(args.bank_dir, bank)
        bank_stem = bank[:-4]  # strip .bnk -> e.g. ch_wp4201
        media_bnk = f"{bank_stem}_media.bnk"
        media_path = os.path.join(args.bank_dir, media_bnk)

        if not os.path.exists(bank_path):
            skipped.append(f"{eid} ({event_name}): HIRC bank not found: {bank}")
            continue
        if not os.path.exists(media_path):
            skipped.append(f"{eid} ({event_name}): media bank not found: {media_bnk}")
            continue

        objs = parse_hirc(bank_path)
        wems, _ = walk_event(objs, eid)
        if not wems:
            skipped.append(f"{eid} ({event_name}): no WEMs found in HIRC chain")
            continue

        chunks = parse_chunks(media_path)
        didx = chunks.get(b"DIDX", b"")
        valid_wems = set()
        for i in range(0, len(didx), 12):
            valid_wems.add(struct.unpack_from("<I", didx, i)[0])

        bank_file = f"{bank_stem}_media.sbnk.1.x64"
        bank_pak = f"{PAK_PREFIX}/{bank_file}"

        for n, wem_id in enumerate(wems, 1):
            if wem_id not in valid_wems:
                skipped.append(
                    f"{eid} ({event_name}) WEM {wem_id}: not in {media_bnk} (streamed?)")
                continue
            new_entries[f"{event_name}{n}"] = {
                "bank_pak": bank_pak,
                "bank_file": bank_file,
                "wem_id": wem_id,
            }

    out_path = args.out or MANIFEST_PATH
    existing = {}
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8-sig") as f:
            existing = json.load(f)

    added = sum(1 for k in new_entries if k not in existing)
    combined = {**existing, **new_entries}

    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(combined, f, indent=4)

    print(f"wwise events in router : {len(routed)}")
    print(f"manifest entries built : {len(new_entries)}")
    print(f"new (added to existing): {added}")
    print(f"skipped                : {len(skipped)}")
    print(f"total in manifest      : {len(combined)}")
    print(f"output                 : {out_path}")
    if skipped:
        print("\nskipped:")
        for s in skipped:
            print(f"  {s}")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--bank-dir", default=DEFAULT_BANK_DIR,
                   help="bank cache dir (default: re4r_txtp_regen cache)")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("index")
    pa = sub.add_parser("analyze")
    pa.add_argument("log")
    pa.add_argument("--all", action="store_true",
                    help="also show noise/routed/generic ids")
    pe = sub.add_parser("extract")
    pe.add_argument("event_id", type=int)
    pe.add_argument("--stem", help="output wav stem (e.g. wp4001_draw)")
    pe.add_argument("--out", default=".", help="output dir (default: cwd)")
    pm = sub.add_parser("manifest")
    pm.add_argument("--out", default=None,
                    help=f"output path (default: {MANIFEST_PATH})")
    args = p.parse_args()
    {"index": cmd_index, "analyze": cmd_analyze,
     "extract": cmd_extract, "manifest": cmd_manifest}[args.cmd](args)


if __name__ == "__main__":
    main()
