# WEAPON_AUDIO_TASK.md — Стартовый промпт для аудио-сессии

> **Использование**: скопируй содержимое блока ниже как первое сообщение
> в новой сессии Claude Code. Всё необходимое включено — не нужно ничего
> дополнительно объяснять.

---

## СТАРТОВЫЙ ПРОМПТ (копировать целиком)

```
Ты продолжаешь работу над RE4R DualSense Enhanced Edition — добавляешь
звуки оружия через Wwise event routing.

Сначала прочти:
  docs/AGENTS.md — архитектура, машинные пути, все правила
  docs/WEAPON_AUDIO_STATUS.md — текущий статус каждого оружия (что готово, что нет)
  docs/WEAPON_AUDIO_TASK.md — этот файл, полный рабочий контекст ниже

После прочтения скажи "готов" и жди инструкций пользователя.
```

---

## ПОЛНЫЙ КОНТЕКСТ (для агента)

### Машинные пути

| Ресурс | Путь |
|---|---|
| Репо | `$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project\` |
| Игра | `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\` |
| Lua autorun (game) | `<игра>\reframework\autorun\DualSenseEnhanced\` |
| Sounds (game) | `<игра>\reframework\data\DualSenseEnhanced\sounds\` |
| Sounds (dev/repo) | `<репо>\src\reframework\data\DualSenseEnhanced\sounds\` |
| Router (dev) | `<репо>\src\reframework\autorun\DualSenseEnhanced\wwise_audio_router.lua` |
| Capture log | `<игра>\reframework\data\DualSenseEnhanced\sound_event_ids.log` |
| ree-pak-cli | `<репо>\tools\extract_sounds\ree-pak-cli.exe` |
| Hash list | `<репо>\tools\extract_sounds\DSE_Required_Banks.list` |
| vgmstream | `<репо>\tools\extract_sounds\vgmstream\vgmstream-cli.exe` |
| Bank cache | `$env:USERPROFILE\AppData\Local\Temp\re4r_txtp_regen\bnk\` |
| REtool pak list | `<REtool-root>\RE4_Release_Pak.list` |

Путь к игре содержит **двойной пробел** перед `BIOHAZARD` — всегда квотировать.

---

### Что уже готово / что осталось

Статус по каждому оружию — в `docs/WEAPON_AUDIO_STATUS.md`.
Приоритеты (по направлению пользователя):

**Draw звуки пистолетов — приоритет 1:**
- Punisher (4001): кандидаты `753704067`, `824052433`, `1397185082` — нужен захват
- Red9 (4002): кандидаты `83617206`, `3376285255`, `3520624873` — нужен захват
- Matilda (4004): кандидаты `1518221001`, `2651947668` — нужен захват

**Full pass (reload/dry-fire/draw/aim) — приоритет 2:**
- Magnums: Broken Butterfly (4500), Handcannon (4502), Killer7 (4501)
- SMG: TMP (4200), Chicago Sweeper (4201), LE 5 (4202)
- Crossbow: Bolt Thrower (4600)

**Частично:**
- Skull Shaker (6001): draw stage 2 банк не найден, stage 1 = placeholder

---

### Рабочий процесс: от захвата до коммита

#### Шаг 1 — читаем лог захвата

```powershell
Get-Content "<игра>\reframework\data\DualSenseEnhanced\sound_event_ids.log" -Tail 100
```

Ищем строки `candidate` + `postRequestInfo` с нужным `weapon=NNNN`.
Убираем шум (см. список ниже). Остаток = кандидаты.

**Noise-floor IDs (фильтровать всегда):**
`807178836`, `1332518089`, `2250845221`, `2250845243`, `2453452847`,
`2718174961`, `3052338289`, `3328592937`, `3397245785`, `3418362288`,
`194540406`, `1166837647`/`1166837648`/`1166837649`, `2086827955`,
`1857863324`, `1401815104`, `2095290572`, `3545586723`,
`2756336461`/`2756336463`.
Пары ±1-3 = одна noise family.

#### Шаг 2 — находим банк и WEM IDs

**Сначала проверь кэш:**
`$env:USERPROFILE\AppData\Local\Temp\re4r_txtp_regen\bnk\ch_wpNNNN.bnk`

**Если нет — targeted extraction (НИКОГДА не весь пак):**

1. Добавь в `DSE_Required_Banks.list` (если нет):
   ```
   natives/stm/_chainsaw/sound/wwise/ch_wpNNNN.sbnk.1.x64
   natives/stm/_chainsaw/sound/wwise/ch_wpNNNN_media.sbnk.1.x64
   ```

2. Извлеки — пробуй паки по порядку, останавливайся на первом успехе:
   ```powershell
   $reepak = "<репо>\tools\extract_sounds\ree-pak-cli.exe"
   $list   = "<репо>\tools\extract_sounds\DSE_Required_Banks.list"
   $out    = "$env:USERPROFILE\AppData\Local\Temp\claude\bnk_extract"
   New-Item -ItemType Directory -Force $out | Out-Null

   # 1. Основной пак (большинство оружий 4xxx, 6001)
   & $reepak unpack -p $list -i "<игра>\re_chunk_000.pak" -o $out -f "ch_wpNNNN" --skip-unknown

   # 2. DLC паки (Sentinel Nine wp6000 = re_dlc_stm_2109308.pak)
   foreach ($pak in Get-ChildItem "<игра>\dlc" -Filter "*.pak" | Sort-Object Length -Descending) {
       & $reepak unpack -p $list -i $pak.FullName -o $out -f "ch_wpNNNN" --skip-unknown
       if (Get-ChildItem $out -Recurse -Filter "ch_wpNNNN*") { break }
   }
   ```

   **Карта DLC паков:**
   - `re_dlc_stm_2109300.pak` — Separate Ways (10 GB, `ao_` банки)
   - `re_dlc_stm_2109308.pak` — Sentinel Nine wp6000 (2 MB)
   - `re_dlc_stm_2109307/09/10.pak` — другие DLC

3. Переименуй `.sbnk.1.x64` → `.bnk`, скопируй в кэш.

**HIRC парсинг — структура объектов:**
- type=4 (Event): data[4]=count, data[5..8]=action_id (и далее)
- type=3 (Action): data[4]=scope, data[5]=action_type, data[6..9]=refId
- type=5/9 (Container): сканируй data в поисках дочерних ID (4-byte aligned)
- type=2 (Sound SFX): AudioFileId в **data[9..12]** (НЕ data[8]!) — подтверждено 2026-07-05

**Важно в PowerShell:** event IDs > 2^31 — всегда кастовать `[uint32]` при
поиске в dictionary, иначе silent miss (Int64 vs UInt32 ключи).

#### Шаг 3 — извлекаем WEM и конвертируем

```powershell
# WEM из DIDX секции media.bnk
# DIDX записи по 12 байт: WemId(4) + Offset(4) + Len(4)
# DATA секция идёт после DIDX — offset считается от начала DATA body

& "<репо>\tools\extract_sounds\vgmstream\vgmstream-cli.exe" -o "wp4003_draw1.wav" "source.wem"
```

#### Шаг 4 — называем WAV файлы

Имя WAV = имя event в роутере:
- `wp4003_draw` → `wp4003_draw.wav` (или `wp4003_draw1.wav`, `wp4003_draw2.wav`, ...)
- Numbered variants: Router автоматически ищет `event1.wav`, `event2.wav`, ...
- Stage суффиксы: `wp6000_draw_a1.wav`, `wp6000_draw_b1.wav` (для multi-event draws)
- Cooldown: draw ~0.60s, aim ~0.30s, reload insert ~0.50s, finish ~0.40s

#### Шаг 5 — добавляем роут в wwise_audio_router.lua

```lua
[EVENT_ID] = {
    event = "wp4003_draw",
    weapon_id = 4003,
    cooldown = 0.60,
    source = "wp4003 (Blacktail) draw, ch_wp4003.bnk event_XXXX; confirmed YYYY-MM-DD",
},
```

Перед добавлением — проверить что ID не дублируется в файле.

#### Шаг 6 — деплой

```powershell
$repo  = "$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project"
$game  = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4"
$sounds_dev  = "$repo\src\reframework\data\DualSenseEnhanced\sounds"
$sounds_game = "$game\reframework\data\DualSenseEnhanced\sounds"
$router_src  = "$repo\src\reframework\autorun\DualSenseEnhanced\wwise_audio_router.lua"
$router_dst  = "$game\reframework\autorun\DualSenseEnhanced\wwise_audio_router.lua"

# WAV в оба места
Copy-Item "new.wav" $sounds_dev -Force
Copy-Item "new.wav" $sounds_game -Force

# Lua роутер
Copy-Item $router_src $router_dst -Force

# Верификация (обязательно)
$sh = (Get-FileHash $router_src -Algorithm SHA256).Hash
$dh = (Get-FileHash $router_dst -Algorithm SHA256).Hash
if ($sh -eq $dh) { Write-Host "OK: $sh" } else { Write-Host "HASH MISMATCH" }
```

Сказать пользователю: **Reset Scripts** в игре.

#### Шаг 7 — обновляем документы и коммитим

**Всегда обновлять после завершения модуля:**

1. `docs/WEAPON_AUDIO_STATUS.md` — строка оружия: статус + event IDs + дата
2. `src/.../wwise_audio_router.lua` — уже обновлён роутами

**WAV файлы** — в `.gitignore`, не коммитятся. Только Lua и MD.

```powershell
cd "<репо>"
git add docs/WEAPON_AUDIO_STATUS.md
git add "src/reframework/autorun/DualSenseEnhanced/wwise_audio_router.lua"
git add "tools/extract_sounds/DSE_Required_Banks.list"  # если добавляли банк
git commit -m @'
audio: add wp4003 (Blacktail) draw - 3 events, 9 WAVs from ch_wp4003.bnk

Короткое описание что подтверждено, откуда банк, дата захвата.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
'@
```

---

### DEV vs RELEASE

| | Dev (репо) | Release (папка игры) |
|---|---|---|
| Lua | `src/reframework/autorun/DualSenseEnhanced/` | `<игра>/reframework/autorun/DualSenseEnhanced/` |
| WAV | `src/reframework/data/DualSenseEnhanced/sounds/` (gitignored) | `<игра>/reframework/data/DualSenseEnhanced/sounds/` |
| C# bridge | `speaker/DualsenseAudioBridge/` (source) | `<игра>/reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe` |

**C# rebuild нужен** только при изменении `SoundMap.cs` или другого C# кода.
Для новых WAV/роутов — только Lua + WAV + Reset Scripts.

```powershell
# C# rebuild (только если нужно)
cd "<репо>\speaker\DualsenseAudioBridge"
dotnet publish ./DualsenseAudioBridge.csproj -c Release -r win-x64 --self-contained true `
    --no-restore -o ./bin/Release/net6.0-windows/win-x64/publish-fixed
# Остановить bridge → скопировать .exe → запустить
```

---

### Известные ловушки

| Ловушка | Что делать |
|---|---|
| AudioFileId в SFX = data[8] | **НЕТ.** Правильно: data[9..12] |
| wp6000 не в основном паке | Он в `re_dlc_stm_2109308.pak` |
| Большие ID в PS словаре | Кастовать `[uint32]` иначе silent miss |
| Deploy drift (src ≠ game) | Всегда верифицировать SHA256 |
| Дублирующийся ключ в роутере | Поиск ID в файле перед добавлением |
| `3601070764` для wp6000 | onEndOfEvent preroll, не реальный event |
| Весь пак (55 GB) | Только `-f "ch_wpNNNN" --skip-unknown` |
