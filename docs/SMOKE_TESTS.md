# Recapit smoke test checklist

Before each release, run through every item.

## 1. First-run wizard
- [ ] Delete `~/Library/Preferences/com.joyson.recapit.plist`
- [ ] Open Recapit
- [ ] All three permission prompts appear in order
- [ ] Processing mode defaults to Local
- [ ] Calendar list populates

## 2. Calendar trigger
- [ ] Add a calendar event with a Zoom URL starting in 90 seconds
- [ ] Wait → notification at T-60s
- [ ] Notification has "Join + Record" action
- [ ] Tap action → countdown starts → recording begins

## 3. Ad-hoc recording
- [ ] Click menu bar icon → "Capture Now"
- [ ] Countdown elapses → recording state
- [ ] Speak → check Console for ASR output
- [ ] Click Stop → processing state → done

## 4. Output
- [ ] `~/Recapit/notes/{id}.md` exists with frontmatter + transcript + summary
- [ ] Main window shows the meeting in sidebar
- [ ] Reader pane shows summary + action items

## 5. Settings + provider switching
- [ ] Settings UI deferred to v1.1 (Task 21)
- [ ] Verify Ollama summary works (with Ollama running locally)

## 6. Audio quality
- [ ] System audio output still works during recording (no muting)
- [ ] Mic capture produces non-zero RMS values in Console
