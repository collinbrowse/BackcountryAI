# TestFlight "What to Test" notes, written for testers rather than developers.
#
# The commit messages since the last release are rewritten by Claude into plain-language bullets ("Added …, which
# lets you …", "Fixed a bug where …"), with build, CI and refactoring changes left out. Needs ANTHROPIC_API_KEY;
# without it, or if the request fails, a generic note is used so the upload never fails over release notes.

module TestflightNotes
  MODEL = "claude-opus-5-5"
  LIMIT = 4000   # App Store Connect's limit for "What to Test"

  FALLBACK = "Bug fixes and improvements.\n\n" \
             "Use the app the way you normally would, and send feedback from TestFlight if anything looks or works wrong."

  PROMPT = <<~PROMPT
    You write the "What to Test" notes that beta testers see in TestFlight for BackcountryAI, an offline
    iPhone app that answers backcountry, first-aid and survival questions from a downloaded library of field
    guides, using an on-device model. The assistant in the app is called Scout.

    You get the commit messages that went into this build. Rewrite them for testers, who are regular people,
    not developers.

    Rules:
    - Describe what changed from the tester's point of view: what they can now do, what looks or behaves
      differently, and what problem is gone. Use the app's own words for things (Scout, Chats, Saved, Offline
      library, field guides), never code names, file names, frameworks or internal terms.
    - Use these shapes:
        "Added <feature>, which lets you <benefit>."
        "Fixed a bug where <what the tester saw>."
        "<Thing> now <behaves differently>."
      Use "Fixed bugs and made small improvements." for small fixes that have no visible symptom worth naming.
    - Leave out changes testers can't see: CI, builds, signing, release tooling, tests, refactoring, developer
      builds, dependency updates, docs. If nothing in the build is visible to testers, say only
      "Behind-the-scenes improvements. Nothing new to test, but keep using the app as usual."
    - Order by what matters most to testers. Merge related commits into one bullet.
    - After the changes, add a short "Please try:" list of two to four concrete things to try in this build
      that exercise the new or fixed behaviour. Skip it if there is nothing new to test.
    - Plain text only: no Markdown, no headings with #, no bold. Start bullets with "• ". Keep the whole note
      under 3000 characters. Output only the note itself, with no introduction.
  PROMPT

  def self.generate(commit_log)
    return FALLBACK if commit_log.to_s.strip.empty?

    if ENV["ANTHROPIC_API_KEY"].to_s.strip.empty?
      UI.important("ANTHROPIC_API_KEY isn't set, so TestFlight gets generic notes. Add it as a GitHub secret (docs/release.md).")
      return FALLBACK
    end

    require "anthropic"
    message = Anthropic::Client.new(timeout: 120).beta.messages.create(
      model: MODEL,
      max_tokens: 4000,
      output_config: { effort: :medium },
      system_: PROMPT,
      messages: [{ role: "user", content: "Commits in this build, newest first:\n\n#{commit_log}" }],
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: :default
    )
    unless message.stop_reason == :end_turn
      UI.important("Claude stopped with #{message.stop_reason} while writing the TestFlight notes; using generic notes.")
      return FALLBACK
    end

    text = message.content.select { |b| b.type == :text }.map(&:text).join.strip
    return FALLBACK if text.empty?
    text.length > LIMIT ? text[0, LIMIT - 1].sub(/\n[^\n]*\z/, "") + "\n…" : text
  rescue StandardError => e
    UI.important("Couldn't write the TestFlight notes with Claude (#{e.class}: #{e.message}); using generic notes.")
    FALLBACK
  end
end
