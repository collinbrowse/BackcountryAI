# Library weak spots

What the offline library answers badly, from running 88 questions (`library/questions.tsv`) through the app's
retrieval with Apple's on-device model (`scripts/check-answers.sh`, 2026-11-10). A relevant article reached the
model for 82 of 88 questions with Essentials and 79 of 88 with Everything.

When the library has nothing on a question, Scout says so and answers from the model's general knowledge under
"Not from the library", which is less reliable and uncited.

## No useful article

| Question | Essentials | Everything | What the library has instead |
|---|---|---|---|
| Asthma attack, no inhaler | ✗ | ✗ | Inhaler side effects, intubation |
| Downed power line in the yard | ✗ | ✗ | Ready.gov power outage page (one line on it) |
| Replacing a chainsaw spark plug | ✗ | ✗ | A leaf blower troubleshooting thread |
| Charging a phone in a car in the garage (carbon monoxide) | ✗ | ✓ | Ready.gov power outage sheet |
| Making a phone battery last in an outage | ✗ | ✓ | An unrelated car thread |
| Falling through lake ice | ✓ | ✗ | A ship's medicine manual |
| Flash flood while in a canyon | ✓ | ✗ | Travel and hurricane articles |
| Mountain lion following you | ✓ | ✗ | A chemistry article |
| Signaling a rescue helicopter | ✓ | ✗ | RECCO, a satellite messenger thread |

Everything sometimes does worse than Essentials: its 930,000 Wikipedia articles crowd out the practical sources.

## Answered only by forum threads (no manual or official guide)

These find something, but it's Stack Exchange Q&A about a specific owner's problem, not a step-by-step guide.

- **Engines and vehicles:** snowmobile maintenance (only the Wikipedia "Snowmobile" and "Motor oil" articles), ATV,
  outboard motor, chainsaw, generator, diesel fuel gelling, getting a truck unstuck. No owner's or service manuals.
- **Camp gear:** camp stoves (finds kitchen oven threads), tent poles, sleeping pads, water filters.
- **Wildlife:** bears, mountain lions and moose come from Q&A and Wikipedia, not park service guidance.
- **Avalanche:** one Ready.gov page, the SERE manual, a Q&A thread, Wikivoyage. No avalanche course material.
- **Weather signs:** Wikipedia cloud articles and a Q&A thread.
- **Edible plants and mushrooms:** Q&A threads and the survival manuals. No regional field guide, so the model
  shouldn't be trusted to identify anything.
- **Emergency childbirth:** WikiMed's "Emergency childbirth" article plus noise ("Childbirth in Japan").

## Not in the library at all

- Specific product manuals (snowmobiles, stoves, radios, beacons).
- Maps, trails, land rules, fire restrictions, avalanche forecasts or current conditions.
- Drug doses beyond the UK Medicines A to Z and MedlinePlus.

## Library quality problems

- MedlinePlus utility pages slip in (a page titled "RSS Feeds" was picked for a shoulder dislocation).
- Many Ready.gov PDFs are titled with their file names ("fema full-suite-hazard-info-sheets"), so the model skips
  them even when they're the best source.

## Public-domain sources that would fill the gaps

All U.S. government works, so they can ship in a paid app:

| Gap | Source |
|---|---|
| Bears, mountain lions, moose, food storage | National Park Service safety pages (nps.gov/subjects/bears and park pages) |
| Lightning, flash floods, cold water, weather signs | National Weather Service safety pages (weather.gov/safety) |
| Falling through ice, cold-water immersion, boating | U.S. Coast Guard boating safety handbook |
| Avalanche basics | USDA Forest Service National Avalanche Center education pages |
| Chainsaws and small engines | USDA Forest Service chainsaw and crosscut saw training course; OSHA small-engine guidance |
| Downed power lines, generators, carbon monoxide | CDC and OSHA electrical-safety pages |
| Signaling and rescue | Already in ATP 3-50.21 and AFH 10-644; better titles and passages would surface them |
| Asthma without an inhaler | No good public-domain source; the answer should tell people to get help |
