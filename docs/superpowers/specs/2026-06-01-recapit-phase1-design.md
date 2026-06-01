# Recapit — Phase 1 Design Spec

Date: 2026-06-01
Domain: recapitai.com
Repo: github.com/joyson-fernandes/recapit (to be created)

## Overview

**Recapit** is a local-first AI meeting note-taker for macOS — Granola-class polish with full local processing as the default and BYOK cloud as opt-in. Phase 1 is the single-user macOS app with native menu bar + main window UI, calendar-driven auto-recording, on-device transcription, diarization, and LLM-powered summaries.

Phase 1 ships **before** any backend / web app / multi-user / bots. Those are Phase 2+.

### Why this exists

- Fireflies, Otter, Read AI ship cloud bots — those are being blocked by enterprise and hit by BIPA lawsuits.
- Granola popularised local-first but doesn't ship a fully-offline mode (still depends on Deepgram + GPT-4o for the heavy lifting).
- Anarlog and Meetily prove the open-source local-first market (8.5K + 12.5K stars respectively).
- Gap: a polished, Mac-native, fully-local-by-default product with the option to upgrade to cloud quality when you want. That's Recapit.

### What Phase 1 does

1. Watches your calendar (any Mac calendar — Google/iCloud/Outlook via EventKit).
2. Auto-records the right meetings with a cancel countdown.
3. Captures mic + system audio as two separate streams (never mixed at capture time).
4. Transcribes locally (WhisperKit) or via cloud (Deepgram/Whisper API).
5. Runs speaker diarization (Pyannote ONNX) on the system audio channel.
6. Generates a structured summary using a hybrid Fireflies-default + Granola-when-pre-notes-exist pattern.
7. Stores everything as SQLite + portable markdown files on disk. Zero cloud dependency unless the user opts in.

---

## Locked decisions

| Decision | Choice |
|---|---|
| **Project name** | Recapit (recapitai.com — recapit.ai was taken Feb 2026) |
| **Phase 1 scope** | macOS-native, single-user MVP. No web app, no multi-user, no bot. |
| **Stack** | Swift 5.9, SwiftUI + AppKit, Swift Package Manager, xcodegen |
| **Min macOS** | 14.0 (CoreAudio process tap, ScreenCaptureKit audio improvements) |
| **Trigger** | Calendar-driven auto-start with 30s cancel countdown + macOS notification |
| **Calendar source** | EventKit (works for Google/iCloud/Outlook via system) |
| **ASR (local)** | WhisperKit `large-v3-turbo` |
| **ASR (cloud)** | Deepgram Nova-3 / OpenAI Whisper API |
| **Diarization (local)** | Pyannote ONNX via ONNX Runtime Swift |
| **Diarization (cloud)** | Pyannote cloud / AssemblyAI |
| **AEC / noise suppression** | AVAudioEngine `voiceProcessingEnabled` (Apple hardware-accelerated) |
| **System audio** | ScreenCaptureKit `capturesAudio = true` |
| **LLM (local)** | Ollama (recommended: `llama3.1:8b`) |
| **LLM (cloud)** | Anthropic Claude, OpenAI, OpenRouter, generic OpenAI-compatible |
| **Embeddings** | Ollama `nomic-embed-text` (local) / OpenAI `text-embedding-3-small` (cloud) |
| **Summary style** | Hybrid — Fireflies-style sections by default, Granola-style (fill in user's pre-notes) when pre-notes exist |
| **Storage** | SQLite + sqlite-vec + markdown files on disk |
| **UI surface** | Menu bar popover + main window (library/reader) + separate notes window during recording |
| **Auto-join** | Headful (opens calendar URL in user's session, no bot) — only works when Mac is on |
| **Telemetry** | None in v1. Opt-in only in later versions. |

---

## Architecture

Four layers, 14 components, no Rust toolchain.

```
┌─ UI Layer ─────────────────────────────────────────────────────────┐
│  MenuBarController · CountdownNotification · MainWindow ·          │
│  NotesWindow · NotesEditor · FirstRunWizard                        │
└────────────────────────────────────────────────────────────────────┘
                              │
┌─ Orchestration ────────────────────────────────────────────────────┐
│  CalendarMonitor (EventKit) · RecordingCoordinator (state machine) │
└────────────────────────────────────────────────────────────────────┘
                              │
┌─ Audio + AI Pipeline ──────────────────────────────────────────────┐
│  AudioCaptureEngine ─→ ASR (WhisperKit/cloud) ─→ TranscriptStore   │
│                   └─→ Diarization (Pyannote ONNX/cloud)            │
│                                                                     │
│  SummaryEngine (3 passes: summary, action items, embeddings)        │
│       ↓                                                              │
│  LLMProvider (abstraction: Ollama/Claude/OpenAI/OpenAICompatible)   │
└────────────────────────────────────────────────────────────────────┘
                              │
┌─ Persistence ──────────────────────────────────────────────────────┐
│  MeetingDB (SQLite + sqlite-vec) · MarkdownStore · SettingsStore   │
│  Keychain (API keys)                                                │
└────────────────────────────────────────────────────────────────────┘
```

---

## Component responsibilities

### UI layer

**`MenuBarController`** — `NSStatusItem` with template SF Symbol icon (`waveform.circle` or similar). Click opens popover. Right-click opens menu (Settings, Quit, Launch at login).

**`PopoverView`** (SwiftUI, width 320pt) — states:

| State | Content |
|---|---|
| Idle | "Capture Now" button pinned at top → upcoming meetings (next 3 days, grouped by day, each row has join + record pill on hover) → divider → 3 most-recent recordings → gear icon top-right |
| Recording | Compact red-dot + timer + Pause + Stop card on top → "Open notes window" link → queued next meeting if any → rest of upcoming list |
| Processing | "Summarising…" spinner row at top → rest as Idle |
| Multiple back-to-back | "Now recording" + "Next at 3:00 PM" rows stacked — queue-aware |

**Live transcript does NOT live in the popover.** Lesson from researching Granola, Fireflies, Read AI, Fathom: NSPopover auto-dismisses on outside clicks, users panic-think recording stopped. Live transcript lives in a separate `NotesWindow` opened on record-start.

**`CountdownNotification`** — `UNNotificationCenter` notification fired at T-60s ("Product sync starts in 1 min · [Join + Record] [Skip]"). User taps Join+Record → opens meeting URL + starts recording. No custom floating window — uses native macOS notifications for consistency.

**`MainWindow`** (SwiftUI, ~960×620 default, resizable):
- Toolbar with search bar (FTS + semantic, dropdown chooses mode)
- Sidebar: meeting library grouped by date (Today / Yesterday / This week / Last week / Month / Older)
- Reader pane: pre-notes (editable), summary (editable), action items as checkboxes, expandable transcript with speaker labels (Speaker_1 etc renameable inline)
- Right-side "Open .md" + "Export" buttons (export = copy markdown to clipboard or save anywhere)

**`NotesWindow`** (SwiftUI, ~720×560, opens on record-start, Granola-style split):
- Left half: live editable notes panel — user types observations as the meeting progresses; saved as `pre_notes`
- Right half: live transcript stream (auto-scrolls, speaker-labelled, time-coded)
- Top bar: meeting title, elapsed timer, Pause/Stop
- Closes on meeting end (or user can keep open to keep editing the notes)

**`FirstRunWizard`** — three sheets:
1. Permissions (Calendar, Mic, Screen Recording — requested one at a time with explanations)
2. Processing mode (Local / Cloud / Hybrid) + model download if Local
3. Calendar selection (which EventKit calendars to watch)

### Orchestration

**`CalendarMonitor`**:
- Polls `EKEventStore` every 30 s for events in `[now, now+24h]`
- Classifies each event: meeting if it has a Zoom/Meet/Teams/Whereby/Cisco/GoTo URL regex match OR 2+ attendees besides user OR previously flagged
- Per-user toggle per-event ("Skip this") and per-recurring-event ("Always record this series") stored in SQLite
- Emits `MeetingUpcoming(eventId, startsAt)` to `RecordingCoordinator` at T-60s
- Emits `MeetingNow(eventId)` at T-0 (after countdown)

**`RecordingCoordinator`** — state machine: `idle → countdown → recording → processing → done`. Transitions:
- `idle → countdown`: triggered by `MeetingNow` or "Start ad-hoc" or "Capture Now"
- `countdown → recording`: 30 s elapsed without cancel, OR user clicks "Start now"
- `countdown → idle`: user cancels via notification action or popover
- `recording → processing`: user clicks Stop, OR meeting end + 60s grace with no audio
- `processing → done`: all 3 summary passes complete (or 1 fails — partial done with retry button)

State persists to SQLite on every transition so a crash doesn't lose context.

### Audio + AI pipeline

**`AudioCaptureEngine`**:
- **Mic channel**: `AVAudioEngine` with `voiceProcessingEnabled = true` on input node. Native input format is whatever the device gives (often 48 kHz stereo on AirPods). We attach an `AVAudioMixerNode` that downmixes to mono and resamples to 16 kHz Float32 — WhisperKit's expected format. Hardware AEC + noise suppression "for free."
- **System channel**: `SCStream` with `SCStreamConfiguration.capturesAudio = true`, `excludesCurrentProcessAudio = true` (don't capture our own UI sounds). Native output is 48 kHz stereo. We apply the same downmix/resample step via `AVAudioConverter` to produce 16 kHz mono Float32.
- Both channels emit `AudioChunk(channel, timestamp, samples)` events into a `ChunkBuffer` actor.
- Files-on-disk policy: per `SettingsStore.keepAudio` ("never" / "7d" / "forever"). When "never", chunks are streamed directly to ASR and discarded; nothing written. When "7d" or "forever", buffered to `~/Recapit/audio/{meetingId}.wav` and a daily cleanup task purges old files.

**`TranscriptionPipeline`**:
- Sliding 30 s windows with 5 s overlap (WhisperKit's sweet spot)
- Two parallel ASR streams (one per channel)
- Each emits `TranscriptSegment(meetingId, channel, startMs, endMs, text)` written immediately to SQLite
- Cross-window dedup via longest-common-subsequence merge on overlap zone

**`DiarizationPipeline`**:
- Runs only on the system channel (mic channel is trivially "You")
- Pyannote `segmentation-3.0` + `embedding` ONNX models, via ONNX Runtime Swift on Apple Neural Engine where available
- Each 30 s chunk → speaker ID labels per time range → merged into transcript segments
- Anonymous IDs (`Speaker_1`, `Speaker_2`...). User renames in the reader pane post-meeting; rename persists in `speakers` table.

**`SummaryEngine`** — runs after `RecordingCoordinator.finalize()`:
1. **Summary pass** — Fireflies-style template if `pre_notes` empty, Granola-style fill-in if not. Prompts in §"Summary prompts" below.
2. **Action items pass** — separate call with `json_schema` / `"type": "json"` mode. Schema: `[{task, owner?, due?}]`. Renders as native checkboxes.
3. **Embeddings pass** — batch-embeds all transcript segments (50 at a time) into the `embeddings` vec0 table.

Failures are non-fatal. UI shows "Retry summary" / "Retry action items" / "Retry embeddings" per-pass.

**`LLMProvider`** (protocol):

```swift
protocol LLMProvider {
    func complete(_ prompt: String, json: Bool, model: String) async throws -> String
    func embed(_ texts: [String], model: String) async throws -> [[Float]]
}
```

Implementations: `OllamaProvider`, `OpenAIProvider`, `AnthropicProvider`, `OpenAICompatibleProvider`. Switched at runtime via `SettingsStore`.

### Persistence

**File layout:**

```
~/Recapit/
├── recapit.sqlite                                # SQLite DB
├── notes/
│   ├── 2026-06-01T1500-team-standup.md
│   └── …
└── audio/
    ├── 2026-06-01T1500-team-standup.wav          # only if keepAudio != "never"
    └── …
```

**SQLite schema** (full DDL in §Appendix A).

**Markdown format** — every meeting writes a self-contained `.md` file with YAML frontmatter so even if SQLite is gone, all transcripts are still on disk + Spotlight-indexed.

```markdown
---
title: Team standup
date: 2026-06-01T15:00:00Z
attendees: [Alice, Bob, You]
duration: 28m
processing_mode: local
---

# Team standup

## Pre-meeting notes
- Discuss Q4 hiring
- Decide on vendor X

## Summary
…

## Action items
- [ ] Alice: send vendor comparison by Friday
- [ ] Bob: schedule architecture review

## Transcript
**15:00:02 — You**
…
```

---

## Summary prompts

### Fireflies-style (default — no pre-notes)

```
You are summarising a meeting transcript. Output Markdown with these exact sections:

## Overview
One paragraph, max 3 sentences. The "what happened in this meeting" elevator pitch.

## Key points
Bullet list of the most important things discussed, in chronological order.

## Decisions
Things the participants agreed on or decided. If none, write "No explicit decisions made."

## Outline
Sectioned by topic shift. Each section: bold title + 2-4 bullets.

Transcript:
{transcript}
```

### Granola-style (when pre-notes exist)

```
You are filling in the user's pre-meeting notes with what was actually
discussed in the meeting. Output Markdown that mirrors the user's bullet
structure exactly, with their original text preserved verbatim and the
actual discussion folded under each bullet as nested points (2 spaces
of indent for the nested points).

Be concise. If a bullet was not discussed, write "(not discussed)"
under it. Do NOT invent content.

Pre-meeting notes:
{pre_notes}

Transcript:
{transcript}
```

### Action items pass

```
Extract action items from this meeting transcript. Return strict JSON
matching this schema:

{
  "action_items": [{
    "task": "string (the thing to do)",
    "owner": "string (the person responsible) | null",
    "due": "string (ISO date) | null"
  }]
}

If no action items, return {"action_items": []}.

Transcript:
{transcript}
```

---

## Settings

Stored in `UserDefaults`, except API keys in Keychain.

```
General
  Launch at login          [✓]
  Show in menu bar         [✓]
  Hotkeys                  Start: ⌘⇧R · Stop: ⌘⇧S · Ad-hoc: ⌘⇧A (all user-configurable like klip — click recorder field, press combo to rebind; nil to clear)

Capture
  Microphone device        System default ▾
  Auto-join calendar URLs  [✓]
  Pre-meeting countdown    30s ▾  (15s / 30s / 60s)
  Keep audio recordings    Never ▾  (Never / 7d / Forever)
  Skip system audio        [ ]

Processing
  Mode                     ◉ Local  ○ Cloud  ○ Hybrid
  ASR provider             [ WhisperKit ▾ ]
    Model                  [ large-v3-turbo ▾ ]
  Diarization              [ Pyannote ONNX ▾ ]
  LLM provider             [ Ollama ▾ ]
    Model                  [ llama3.1:8b ▾ ]
    API key                ─                          [Test]
  Embeddings               [ nomic-embed-text ▾ ]

Calendars
  Work (Google)            [✓]
  Personal (iCloud)        [✓]
  Holidays (Subscribed)    [ ]

Storage
  Notes folder             ~/Recapit/notes
  Database                 ~/Recapit/recapit.sqlite
  Disk usage               312 MB · [Clean up old audio…]

About
  Version 1.0.0
  Open data folder in Finder
  Quit
```

---

## Error handling

- **Permission denied** (Calendar, Mic, Screen Recording): popover shows a one-line banner "Grant {permission} access" with a button that deep-links to System Settings.
- **WhisperKit model missing**: First-run wizard guards this. Settings shows download button if user later switches models.
- **Ollama not running**: API call fails → SummaryEngine retries with exponential backoff (3 attempts: 1s, 5s, 30s) → on persistent failure, marks the pass as "Retry pending" and surfaces "Start Ollama and click Retry" in the meeting row.
- **LLM API quota exhausted**: surfaced as "Retry summary" with the actual error message ("OpenAI returned 429 — quota exceeded").
- **Disk full** during recording: AudioCaptureEngine pauses recording, posts a notification, resumes when space frees up.
- **App quits mid-recording**: state machine persists every transition. On relaunch, RecordingCoordinator reads `state = 'recording'` and offers "Resume / Discard incomplete recording from {time}".

---

## Testing strategy

Tests live in `recapitTests/`. XCTest, no third-party test framework.

**Unit tests:**
- `KeyComboTests`, `SettingsStoreTests`, `MeetingDBTests`, `MarkdownStoreTests`, `TranscriptDeduperTests`, `LLMProviderTests` (with mock URLProtocol), `CalendarClassifierTests`.

**Integration tests:**
- `RecordingCoordinatorTests` — full state machine with mock audio + mock ASR.
- `SummaryEngineTests` — feed canned transcript + pre-notes, verify the 3 passes produce expected output structure (against fake LLM).

**Smoke tests** (manual, documented in `docs/SMOKE_TESTS.md`):
- First-run wizard end to end
- Calendar event → countdown notification → record → stop → summary
- Permission denials and recovery
- Switch Local → Cloud mid-flight

---

## Distribution

- Direct download as `.dmg` from `recapitai.com` and GitHub releases.
- Signed with Apple Developer ID, notarised.
- Auto-update via `Sparkle` framework — checks once per day, downloads in background.
- **Not** on Mac App Store in v1 (sandboxing makes mic + system audio + Ollama-on-localhost painful).

---

## Out of scope (Phase 2+)

- Cloud sync, backend, web app, multi-user
- Auto-join meeting bots (cloud, joins as separate participant)
- Slack / Notion / CRM integrations
- Meeting templates / library
- Mobile companion
- Team workspaces, sharing
- Magic-link auth

---

## Appendix A — Full SQLite schema

```sql
CREATE TABLE meetings (
  id              TEXT PRIMARY KEY,
  title           TEXT NOT NULL,
  started_at      INTEGER NOT NULL,
  ended_at        INTEGER,
  calendar_event  TEXT,
  pre_notes       TEXT,
  markdown_path   TEXT NOT NULL,
  audio_path      TEXT,
  summary         TEXT,
  attendees       TEXT,                 -- JSON array
  meeting_url     TEXT,                 -- detected Zoom/Meet/etc URL
  state           TEXT NOT NULL,        -- 'recording' | 'processing' | 'done' | 'failed'
  processing_mode TEXT NOT NULL,        -- 'local' | 'cloud' | 'hybrid'
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
);
CREATE INDEX idx_meetings_started_at ON meetings(started_at DESC);
CREATE INDEX idx_meetings_state ON meetings(state);

CREATE TABLE transcript_segments (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  channel         TEXT NOT NULL,        -- 'mic' | 'system'
  start_ms        INTEGER NOT NULL,
  end_ms          INTEGER NOT NULL,
  speaker         TEXT NOT NULL,        -- 'You' | 'Speaker_1' | ...
  text            TEXT NOT NULL
);
CREATE INDEX idx_segments_meeting ON transcript_segments(meeting_id, start_ms);

CREATE VIRTUAL TABLE transcript_fts USING fts5(
  text, meeting_id UNINDEXED, segment_id UNINDEXED,
  content='transcript_segments', content_rowid='id'
);

CREATE TABLE speakers (
  meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  speaker_id      TEXT NOT NULL,        -- 'Speaker_1'
  display_name    TEXT NOT NULL,
  PRIMARY KEY (meeting_id, speaker_id)
);

CREATE TABLE action_items (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  task            TEXT NOT NULL,
  owner           TEXT,
  due             TEXT,                 -- ISO date string
  done            INTEGER NOT NULL DEFAULT 0,
  position        INTEGER NOT NULL
);

CREATE TABLE meeting_overrides (
  calendar_event  TEXT PRIMARY KEY,     -- EventKit identifier
  recurring_id    TEXT,
  rule            TEXT NOT NULL         -- 'always' | 'skip'
);

-- One vec0 table per embedding dim. Phase 1 ships both common dims:
--   768  → Ollama nomic-embed-text (local default)
--   1536 → OpenAI text-embedding-3-small (cloud default)
-- Switching providers triggers a re-embed pass on the next startup if the
-- currently-populated table doesn't match the configured provider's dim.
CREATE VIRTUAL TABLE embeddings_768 USING vec0(
  meeting_id      TEXT,
  segment_id      INTEGER,
  embedding       FLOAT[768]
);

CREATE VIRTUAL TABLE embeddings_1536 USING vec0(
  meeting_id      TEXT,
  segment_id      INTEGER,
  embedding       FLOAT[1536]
);
```

---

## Appendix B — Naming references

- `recapit.ai` — taken (registered Feb 2026, GoDaddy). Worth Googling before public launch in case a competitor is in stealth.
- `recapit.com` — taken (corporate, 1999, MarkMonitor).
- `recapitai.com` — **available** as of 2026-06-01.
- Brand: **Recapit AI**. App name: **Recapit**.
