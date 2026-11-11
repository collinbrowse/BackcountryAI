# Library weak spots

What the offline library answers badly, from running 88 questions (`library/questions.tsv`) through the app's
retrieval with Apple's on-device model (`scripts/check-answers.sh`, 2026-11-11). A relevant article reached the
model for 86 of 88 questions with both Essentials and Everything (before the 2026-11-11 additions: 85 and 81).

The 2026-11-11 round added 63 U.S. government safety pages (`library/guides.tsv`: NPS, NWS/NOAA, Coast Guard,
Forest Service, OSHA, CDC, CPSC, FDA, USDA, National Eye Institute), split the survival manuals into titled
sections ("Snow Walls, Trenches, and Caves (Chapter 7: Survival) — US Army TC 21-3"), gave Ready.gov PDFs
readable titles, and dropped MedlinePlus's pages about the site itself.

After the quality filter (`docs/library-quality.md`) removed about 30,000 junk articles, Essentials scored 85 of
88. The one new miss, GMRS versus FRS radios, is the relevance check rejecting radio threads that search still finds.

With the rewritten search and answer prompts (2026-11-11), retrieval found a relevant article for 88 of 89
questions (the pond-filter question was added).

When the library has nothing on a question, Scout says so and answers from the model's general knowledge under
"Not from the library". That answer is thin: run `scripts/check-answers.sh <library> --no-library` to see it.

## Still missed

| Question | Essentials | Everything | Notes |
|---|---|---|---|
| A power line is down in my front yard | ✗ | ✓ | The CDC page is in the library, but the model's searches ("electrical shock, circuit breaker") miss it |
| Charging a phone in a car running inside a garage | ✗ | ✓ | Finds car-battery threads, not carbon monoxide |
| Building a snow cave | ✓ | ✗ | Found the right TC 21-3 section, then the relevance check dropped it |
| Hypothermia (shivering, confused) | ✓ | ✓* | *Picked the TC 21-3 frostbite section, which the check's title pattern doesn't count |

Everything sometimes did worse than Essentials, since its 930,000 Wikipedia articles crowded out the practical
sources, so the app now offers only Essentials. Still thin: an asthma attack with no inhaler (no good public-domain source; the answer should tell people
to get help).

## Answered only by forum threads (no manual or official guide)

These find something, but it's Stack Exchange Q&A about a specific owner's problem, not a step-by-step guide.

- **Engines and vehicles:** snowmobile maintenance (only the Wikipedia "Snowmobile" and "Motor oil" articles), ATV,
  outboard motor, chainsaw, generator, diesel fuel gelling, getting a truck unstuck. No owner's or service manuals.
- **Camp gear:** camp stoves (finds kitchen oven threads), tent poles, sleeping pads, water filters.
- **Avalanche:** Forest Service and Ready.gov basics, but no avalanche course material.
- **Edible plants and mushrooms:** Q&A threads and the survival manuals. No regional field guide, so the model
  shouldn't be trusted to identify anything.
- **Emergency childbirth:** WikiMed's "Emergency childbirth" article plus noise ("Childbirth in Japan").

## Not in the library at all

- Specific product manuals (snowmobiles, stoves, radios, beacons).
- Maps, trails, land rules, fire restrictions, avalanche forecasts or current conditions.
- Drug doses beyond the UK Medicines A to Z and MedlinePlus.

## Library quality problems

- Some government web pages keep page clutter (menus, language lists, "T T T") in their text.
- The Forest Service chain saw guidebook has no bookmarks, so it's one long document split by its headings.
