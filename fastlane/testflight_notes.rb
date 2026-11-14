# TestFlight "What to Test" notes, written for testers rather than developers.
#
# The commit messages since the last release are rewritten by Claude into plain-language bullets ("Added …, which
# lets you …", "Fixed a bug where …"), with build, CI and refactoring changes left out. It runs the Claude Code CLI
# signed in with your Claude subscription (CLAUDE_CODE_OAUTH_TOKEN, from `claude setup-token`), so it uses the
# subscription rather than API credits. Without the token, or if Claude fails, a generic note is used so the
# upload never fails over release notes.
require "open3"
require "timeout"
require "tmpdir"

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

    unless ENV["CLAUDE_CODE_OAUTH_TOKEN"].to_s.strip != "" || ENV["TESTFLIGHT_NOTES_LOCAL"] == "1"
      warn_ci("CLAUDE_CODE_OAUTH_TOKEN isn't set, so TestFlight gets generic notes. See docs/release.md.")
      return FALLBACK
    end

    # No tools, no settings, no MCP servers, and run outside the repo so no CLAUDE.md is picked up: Claude
    # only reads the commits it's given and writes text.
    command = ["claude", "-p", "--model", MODEL, "--effort", "medium", "--tools", "",
               "--system-prompt", PROMPT, "--setting-sources", "", "--strict-mcp-config",
               "--no-session-persistence", "--output-format", "text"]
    out, err, status = Dir.mktmpdir do |dir|
      Timeout.timeout(300) do
        Open3.capture3(*command, chdir: dir,
                       stdin_data: "Commits in this build, newest first:\n\n#{commit_log}")
      end
    end
    unless status.success?
      warn_ci("Claude Code exited with #{status.exitstatus} while writing the TestFlight notes " \
              "(#{(err.strip.empty? ? out : err).strip[0, 300]}); using generic notes.")
      return FALLBACK
    end

    text = out.force_encoding("UTF-8").scrub.strip
    return FALLBACK if text.empty?
    text.length > LIMIT ? text[0, LIMIT - 1].sub(/\n[^\n]*\z/, "") + "\n…" : text
  rescue StandardError, Timeout::Error => e
    warn_ci("Couldn't write the TestFlight notes with Claude (#{e.class}: #{e.message}); using generic notes.")
    FALLBACK
  end

  def self.warn_ci(message)
    FastlaneCore::UI.important(message)
  end
end
