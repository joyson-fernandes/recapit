# Feature: AI Interview Copilot for Recapit

**Date:** 5 June 2026
**Context:** Joyson has a job interview with Denis Savostiyanov (Senior
Engineering Manager, Cloud Platform) at Mimecast on Friday 6 June at 4pm.
He wants an AI assistant that listens to the interviewer's spoken questions
and generates suggested answers in real time.

---

## What to build

A real-time interview copilot mode in Recapit:

1. **Listens** to the interviewer's spoken question via the existing ASR
   (WhisperKitProvider already does local speech-to-text).
2. **Generates a concise answer** using the existing LLM layer
   (OpenAICompatibleProvider with OpenRouter, model
   `anthropic/claude-sonnet-4.6`).
3. **Displays the suggested answer** on screen so Joyson can glance at it.
4. Optionally **speaks the answer** (TTS, lower priority).

---

## What already exists in the codebase

The app already has all the building blocks:

- `recapit/ASR/WhisperKitProvider.swift` — local speech-to-text, streams
  transcription segments in real time.
- `recapit/ASR/ASRProvider.swift` — the protocol; the copilot can reuse
  the same ASR pipeline.
- `recapit/LLM/OpenAICompatibleProvider.swift` — streams from any
  OpenAI-compatible endpoint (OpenRouter is one).
- `recapit/LLM/LLMProvider.swift` — the protocol.
- `recapit/Coordinator/RecordingCoordinator.swift` — orchestrates
  capture + ASR + LLM summarization.
- `recapit/Capture/` — system audio and mic capture.

---

## Design direction

Add a **Copilot mode** (or a toggle within the existing recording session)
that:

- Uses the mic (or system audio if on a call) to capture what the
  interviewer says.
- Accumulates the transcription until a pause is detected (similar to how
  the existing meeting flow chunks speech).
- When a question is detected (pause or manual trigger), sends it to the
  LLM with a system prompt:

```
You are helping a Cloud Operations / Platform engineer in a live job interview.
When given an interview question, provide a clear, concise, confident answer
they can deliver verbally.
Rules:
- Answer in 3-5 sentences maximum.
- Write in first person as the candidate.
- Be technical and specific.
- No preamble. Start the answer immediately.
```

- Streams the answer into a dedicated UI panel (or overlay).
- Stays ready for the next question.

---

## Key decisions already made

- **LLM provider:** OpenRouter with model `anthropic/claude-sonnet-4.6`.
  The OpenRouter key is already configured (or should be in Settings).
- **Context:** General knowledge only (not Joyson's prep notes). Keep it
  simple for v1.
- **Control:** Hands-free preferred. The ASR picks up the question; the
  user can also type/paste one manually as fallback.
- **No server needed:** Everything runs locally (ASR) or direct to
  OpenRouter (LLM). The app is already local-first.

---

## Interview topics to optimize for

The interviewer (Denis) will ask about:
- Linux (most important)
- Kubernetes
- AWS (especially EKS)
- Terraform
- Monitoring (Nagios, Grafana, Logscale)

The system prompt can mention these so the LLM knows the domain.

---

## What NOT to build

- No web UI (this is a native macOS app).
- No new API keys needed (OpenRouter key already in settings).
- No integration with the prep.joysontech.com site.
- No ElevenLabs TTS (lower priority; the text on screen is enough for v1).

---

## Suggested file placement

```
recapit/
  Copilot/
    CopilotCoordinator.swift    — orchestrates ASR → LLM → display
    CopilotView.swift           — SwiftUI panel showing Q + answer
    CopilotPrompt.swift         — system prompt + formatting
```

Or integrate into the existing `RecordingCoordinator` as a mode toggle.

---

## Done when

- [ ] Can capture audio (mic or system) and transcribe in real time
- [ ] Detected questions are sent to OpenRouter
- [ ] Streamed answers appear on screen
- [ ] Works during a live call (macOS system audio capture)
- [ ] Manual input fallback (type a question)
