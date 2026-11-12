# Library weak spots

What the library answers badly. The last check (`scripts/check-answers.sh`, 2026-11-11) found a relevant
article for 88 of the 89 questions in `library/questions.tsv`.

When the library has nothing on a question, Scout answers from the model's own knowledge under "Not from the
library". To see those answers, run `scripts/check-answers.sh <library> --no-library`.

## Missed

- **Asthma attack with no inhaler:** the model's searches went off-topic, and there's no good public-domain
  source anyway. The answer should tell people to get help.

## Only forum threads, no manual or official guide

- **Engines:** snowmobiles, ATVs, outboard motors, chainsaws, generators, diesel gelling, getting a truck unstuck.
- **Camp gear:** stoves, tent poles, sleeping pads, water filters.
- **Avalanche:** only Forest Service and Ready.gov basics, with no course material.
- **Edible plants and mushrooms:** no regional field guide. Don't trust the model to identify anything.
- **Emergency childbirth:** one WikiMed article, plus noise.

## Not in the library

- Product manuals for snowmobiles, stoves, radios and beacons.
- Maps, trails, land rules, fire restrictions, and current conditions or avalanche forecasts.
- Drug doses beyond the UK Medicines A to Z and MedlinePlus.

## Text problems

- Some government web pages keep page clutter, such as menus, language lists and "T T T".
- The Forest Service chain saw guide has no bookmarks, so it's split only by its headings.
