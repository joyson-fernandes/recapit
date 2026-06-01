import Foundation

enum SummaryPrompts {
    static func summary(transcript: String, preNotes: String?) -> String {
        let trimmed = preNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = trimmed, !p.isEmpty {
            return granolaStyle(transcript: transcript, preNotes: p)
        }
        return firefliesStyle(transcript: transcript)
    }

    static func actionItems(transcript: String) -> String {
        """
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
        \(transcript)
        """
    }

    private static func firefliesStyle(transcript: String) -> String {
        """
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
        \(transcript)
        """
    }

    private static func granolaStyle(transcript: String, preNotes: String) -> String {
        """
        You are filling in the user's pre-meeting notes with what was actually
        discussed in the meeting. Output Markdown that mirrors the user's bullet
        structure exactly, with their original text preserved verbatim and the
        actual discussion folded under each bullet as nested points (2 spaces
        of indent for the nested points).

        Be concise. If a bullet was not discussed, write "(not discussed)"
        under it. Do NOT invent content.

        Pre-meeting notes:
        \(preNotes)

        Transcript:
        \(transcript)
        """
    }
}
