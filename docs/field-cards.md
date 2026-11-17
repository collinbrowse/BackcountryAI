# Field cards

Field cards are the app's own quick-reference cards (`Sources/FieldCardData.swift`): what to do in the situations
people most often ask about, in about 130 words each. There are 52. Field mode and the Guide show the 15 first-aid
cards as they are. In chat, when a question is about a card's situation, the card is the answer model's first source,
ahead of anything search found (`CardMatcher`, `Retrieval.find`), and it sits first among the answer's sources, where
it opens like an article.

## Why

On the test questions only about one prompt in eight held a library excerpt that answered the question, and both
models follow whatever excerpts they are given. Given the hypothermia, bleeding, burns, head-injury and altitude cards
as the only source, the same models with the same instructions answered correctly questions they had answered wrongly
from the library: Qwen all 6 tried, Apple's model all 6 once its step instruction was fixed.

## Review before release

**Every card must be reviewed by qualified people before it ships.** The 15 first-aid cards were written for this app
as general wilderness first-aid guidance and need a wilderness medicine instructor's review. The 37 situation cards
were drafted by Claude from the library's public-domain sources and checked by a second pass, and need the same. Five
rest mostly on general knowledge because no government source in the library covers them: **Vehicle won't start**,
**Vehicle stuck in snow or mud**, **Small engine won't start** and **Camp stove won't light** (a mechanic and the
makers' manuals), and **Dog hurt on the trail** (a veterinarian). **Emergency childbirth** needs a midwife or
obstetric reviewer: it departs from the library's 2000 Navy manual in three places (no routine suction, the cord left
attached, the head supported and not pushed back).

The last eight cards (seizure, stroke, low blood sugar, asthma attack, emergency childbirth, animal bite and rabies,
tornado, small engine) were added because test questions about them kept landing near a card that didn't answer
them. Parts of each rest on current public guidance that the library only links to (CDC's seizure first aid, the
"15-15 rule" for low blood sugar, the stroke check); their sections below say which.

Where the library's sources disagree, the cards follow current public guidance:

- **Boiling at altitude:** 3 minutes above 6,500 ft (CDC's public guidance). The Army manual in the library says
  3 minutes above 8,000 ft; CDC's Yellow Book says 1 minute is enough at any common elevation.
- **Snakebite, limb position:** still, at about heart level (CDC NIOSH). The Army manuals say below the heart and
  the Yellow Book says elevated; the older Army advice to open blisters was not used.
- **Knocked-out tooth:** replant at once (current dental-trauma guidance, not in the library). The ship's-medicine
  manual in the library says to soak it for 20 minutes first.
- **Black bears:** fight back, don't play dead (National Park Service, "Staying Safe Around Bears"). Another NPS
  page contradicts itself on a surprised black bear.

## How a question finds its card

Each card has about 40 `asks`: ways people describe its situation, written the way they type or dictate ("my buddy
won't stop shaking and he's talking funny"), and 16 to 27 `notAsks`: messages that share its words and need a
different answer. The library's embedder turns the message into a vector, and a card's score is the mean of its two
nearest asks (`CardMatcher`).

1. **No card** when the best score is under 0.70, or when the message is nearer to one of that card's notAsks than
   to any of its asks ("someone is having a seizure" used to sit nearest the heat card, and nearer still to its "not
   this" phrases).
2. **No card** when the runner-up is within 0.02. The nearest card is then the wrong one about half the time, and the
   wrong ones are the dangerous kind (the heat card for someone soaked and stumbling in sleet). A missing card costs
   nothing that wasn't already so: search answers as it would have.
3. Otherwise the card is used at 0.78 or more, and between 0.70 and 0.78 Apple's model is asked one yes-or-no
   question: is this card about their message? Asked that way, with one clear candidate, it said yes to 107 of 119
   right cards and to 3 of 36 wrong ones.
4. A follow-up is scored twice, alone and together with what the person said before it, and takes the higher. Alone
   it can lift a card only 0.03 above what the whole situation gives it: cards have fragments among their asks
   ("should I close it or leave it open?"), and a fragment alone matches the same fragment on any card.

Without the embedder (the simulator, or a library built before meaning search) a card is matched by shared words,
which is rarely wrong and finds about a quarter of what meaning does.

### Measured

`scout-tools cards <library> <messages.tsv>` runs the app's matcher over a file of messages (expected card or
`none`, kind, message; a follow-up is written `earlier || new`). The files are in `library/card-tests/`. The blind
sets were written by separate Claude sessions that saw only the cards' titles: plain questions, messy dictated ones,
follow-ups, near misses and unrelated messages. **Don't write asks from their rows**: once a set has been used to
write phrases it no longer measures anything, and a new one has to be written.

| Messages | About a card | Right card | Wrong card | No card | About none | Given a card anyway |
|---|---|---|---|---|---|---|
| `questions.tsv`: the app's test questions (`library/questions.tsv`) with their cards | 62 | 54 | 0 | 8 | 27 | 0 |
| `blind-1.tsv`: the 44 older cards | 264 | 211 | 1 | 52 | 120 | 3 |
| `blind-2.tsv`: the 44 older cards | 264 | 201 | 6 | 57 | 120 | 0 |
| `new-cards.tsv`: the eight newest cards and their neighbours | 120 | 84 | 4 | 32 | 30 | 0 |
| `library/questions-longtail.tsv`: 130 questions written to be about no card | | | | | 130 | 4 |

`new-cards.tsv` was blind once: 77 right, 6 wrong, 37 none, and 1 card on a message about none. Rule 4 and sixteen notAsks
between the new cards and their neighbours (asthma and chest pain, stroke and head injury, a bitten dog and a dog
bite) came from reading its misses, so its second measurement is not blind. The new cards have had one round of
phrases where the older ones had three, which is most of the gap.

**Cards on questions that are near a card but not about it are the weak spot.** The long-tail questions were
written to be off every card, and 17 of the 130 got one anyway: the thunderstorm card for a hurricane, the
snakebite card for "is this snake venomous", the night-out card for how to layer clothes. Ten of those were grey-zone
cards the model said yes to. The judge scored 13 of the 17 cards as a near miss or worse, and with a card in front
only 3 of those 17 prompts held an excerpt that answered the question, against 61 of the other 113. A stricter
yes-or-no question halved them and lost 4 to 9% of the right cards, so it wasn't taken. What was: 30 notAsks for
those topics, which leaves 4 of 130 and changed nothing in the other sets. That 4 is not a blind number. Expect
something nearer the first figure, about one in eight, for near-card topics nobody has written notAsks for yet,
and add notAsks whenever one turns up (`scout-tools cards` on any list of questions shows them).

What moved the numbers, on blind set 1 with the 44 older cards:

| | Right card | Wrong card | No card | Given a card anyway |
|---|---|---|---|---|
| 11 asks a card, one line at 0.74 | 191 of 264 | 37 | 36 | 12 of 120 |
| 11 asks a card, the model asked about every candidate | 208 | 17 | 39 | 4 |
| about 41 asks and 20 notAsks a card, rules 1 to 3 | 213 | 1 | 50 | 4 |
| the same, but asking the model about both cards in a close call | 241 | 4 | 19 | 6 |
| by shared words only | 69 | 5 | 190 | 0 |

More asks did more than any change to the scoring: with 11 a card the nearest card was the right one for 88% of the
messages, with about 41 for 95%. Asking the model about both cards in a close call (`CardMatcher.WhenClose.askBoth`,
off) finds more right cards, but on blind set 2 it also raised wrong cards from 4 to 13 of 264, and those were
hot-for-cold mix-ups: it says yes too easily when two cards are near. Asking Apple's model to choose among the top
three cards did not work either: it answered "A" 343 times in 357.

What the cards do to answers is in `docs/answer-quality.md`.

### Situations with no card yet

Seen landing near a card in the tests, and worth a card: bites and stings without an allergy (spiders, scorpions,
bees), poison ivy and sunburn, splinters, fainting and panic attacks, hurricanes and earthquakes, a flat tire, and
water filter care.

## Adding or changing a card

1. Write the card in `Sources/FieldCardData.swift`: recognize, treat (3 to 6 steps), avoid, evacuateIf, and the
   library searches that find its sources. Keep the whole card under about 130 words.
2. Write its asks the way people talk, not as titles: indirect descriptions of what they see, follow-up fragments
   ("now it's spreading up his arm"), dictated run-ons, and a few plain questions. About 40. Add notAsks for the
   questions that share its words, and give its neighbours notAsks for its situation.
3. Have someone who hasn't seen the asks write test messages for it (and for its neighbours: a new card can take
   their questions), and run `scout-tools cards` on those and on the older sets.
4. Have it reviewed, and add it to the table below.

## The situation cards: sources and open questions

Sources are the titles of the library passages each card was drafted from. Open questions are what the drafter left
out, was unsure of, or took from general knowledge: start a review there.

### Lost or off the trail (`lost`)

**Sources:** Outdoor Emergency Plan: If You Get Lost (National Park Service); Outdoor Emergency Plan (National Park
Service); Backcountry Safety (U.S. Forest Service).

**Open questions:** Steps follow NPS: stop, locate, retrace if safe, call 911, stay put. USFS agrees (backtrack if
practical, otherwise stay). Satellite SOS is general knowledge, not in the library sources, and I didn't name any
product. Left out NPS's children's 'hug a tree' advice and the list of details to give a 911 dispatcher about a
missing group member. The NPS warning not to light a fire in high fire danger is in the signaling and wet-fire cards.

### Thunderstorm coming (`thunderstorm`)

**Sources:** Lightning Safety for the Outdoors (National Weather Service); Lightning Safety When Outdoors (National
Weather Service); Lightning Safety Above Treeline (Rocky Mountain National Park); Lightning in the Mountains (Shoshone
National Forest); Backcountry Safety (U.S. Forest Service).

**Open questions:** NWS stresses that no outdoor spot is safe and these steps only lower the risk. Forest Service
pages also say to drop metal objects (poles, framed packs). I left that out: current NWS/NOLS guidance says metal
doesn't attract lightning, and dropping gear can slow your descent. The crouch is offered by Shoshone NF and USFS. NWS
calls it a last resort, and some current guidance downplays it, so it's the last step. The 15 ft spacing is from
Shoshone NF and USFS. The prevention tip to be below treeline by noon is in the know line's spirit but left off to
save space; consider adding it.

### Flash flood in a canyon or wash (`flashflood`)

**Sources:** Flash Floods in Slot Canyons (Zion National Park); Hiking the Narrows Safely: Flash Floods and Cold Water
(Zion National Park); Weather Dangers: Flash Floods and Lightning (Grand Canyon National Park); What to Do During a
Flood (National Weather Service); Turn Around Don't Drown: Flood Water Safety (National Weather Service).

**Open questions:** The Zion pages say 'watch for these indications' but the bulleted list didn't survive in the
library text. The warning signs in the know line (rising or muddy water, debris, roaring sound) come from my general
knowledge of NPS/NWS guidance, so please verify them. The 6 in and 12 in figures are NWS figures for moving
floodwater; NWS also says 18 in to 2 ft carries away larger vehicles. The 'blue sky' phrasing paraphrases 'storms
miles away'.

### Making water safe to drink (`water`)

**Sources:** Water Disinfection | CDC Yellow Book 2024; Avoid Contaminated Water During Travel | Travelers; Chapter 3
- Water — US Army ATP 3-50.21; Water; Food and Water Safety During Power Outages and Floods (FDA).

**Open questions:** Boil time at altitude: the library's Army manual (ATP 3-50.21) says extend to 3 minutes above
8,000 ft. The CDC Yellow Book says 1 minute is enough at any common elevation because pathogens die well below
boiling. CDC's current public 'Making water safe' guidance (not in the library) says 3 minutes above 6,500 ft. I used
CDC's 6,500 ft. Filters: the CDC Yellow Book says microfilters remove bacteria and protozoa but not viruses, while
CDC's traveler page says 'most portable water filters do not remove bacteria or viruses'. I followed the Yellow Book.
I left out bleach doses on purpose: FDA/FEMA give 8 drops per gallon for 5.25% bleach, but most bleach sold now is
6-8.25%, so the dose varies. I also left out UV pens and specific tablet wait times (they vary by product). The line
about chemicals and fuel is from the CDC traveler page.

### Bear encounter (`bear`)

**Sources:** Staying Safe Around Bears (National Park Service); Bear Attacks: What to Do (National Park Service); Bear
Spray vs. Firearms: Using Bear Spray (National Park Service); Close Encounters With Bears: What to Do (Glacier Bay
National Park).

**Open questions:** Sources disagree in places. NPS 'Bear Attacks' says both 'if you surprise a bear, regardless of
species, don't fight it' and 'if you surprise a black bear and it charges or attacks, fight back.' I followed NPS
'Staying Safe Around Bears': black bear, don't play dead. Glacier Bay (Alaska, mostly brown bears) says to play dead
on any contact and puts spray range at 6-8 yards. NPS 'Using Bear Spray' says spray when a charging bear is within 60
ft. I used the NPS figure. NPS says spray a cloud 'between you and the bear'. I wrote 'at it', which is shorter but
slightly different, so check the wording. I left out telling the species apart (color is unreliable) because it
doesn't fit in the word budget. Check whether the card needs it.

### Storing food in bear country (`foodstorage`)

**Sources:** Backcountry Safety (U.S. Forest Service); Storing Food in a Bear Canister (Grand Teton National Park);
Staying Safe Around Bears (National Park Service).

**Open questions:** The government sources in the library cover canisters (USFS: 100 ft from camp; Grand Teton: what
counts as scented) but have no instructions for hanging a bag and nothing for the no-canister, no-tree case. I left
out hang heights and distances (the common 10-12 ft up and 4-6 ft out are not in the library). The no-tree line is my
own conservative general knowledge; a forum answer suggests hanging over a cliff or rock, which I didn't include.
Check whether to add 'downwind' and a specific distance. Burning trash is illegal in Grand Teton. 'Let it go' rests on
the NPS line about not letting bears get food plus general knowledge.

### Mountain lion encounter (`lion`)

**Sources:** Mountain Lion Safety (National Park Service); Wildlife Safety: Mountain Lions, Moose and Bears (Rocky
Mountain National Park); Mountain Lion Safety (Glacier National Park).

**Open questions:** All three NPS sources agree. I left out the RMNP distance advice (keep 120 ft away), which is
about wildlife viewing, not encounters.

### Snakebite (`snakebite`)

**Sources:** Venomous Snakes: Prevention and First Aid (CDC NIOSH); Poisonings, Envenomations, and Toxic Exposures |
CDC Yellow Book 2024; US Army ATP 4-02.11: Casualty Response, Tactical Combat Casualty Care and First Aid (2026).

**Open questions:** Limb position varies by source. CDC NIOSH says 'neutral position of comfort'. Army ATP 4-02.11
says 'slightly below the level of the heart'. The CDC Yellow Book says 'elevated and extended position with a splint'.
The older Army ATP 3-50.21 says keep it lower than the heart and also says to 'break open the large blisters', which
is outdated and I didn't use. I went with NIOSH (about heart level, position of comfort), which matches my
understanding of current Wilderness Medical Society advice for North American pit vipers. Please check this. Left out
pressure-immobilization bandages: the Yellow Book mentions them only for neurotoxic (e.g. coral snake) venom, and
they're not advised for pit vipers. 'Mark again as it spreads' adds a little to NIOSH's single mark. The
no-aspirin/ibuprofen line is NIOSH's.

### Tick removal (`tick`)

**Sources:** What to Do After a Tick Bite (CDC); Tick Bites | Tickborne Disease.

**Open questions:** Straight from CDC and MedlinePlus, which agree. CDC lists sealing, taping, flushing or alcohol for
disposal; keeping it for identification is a common add-on. The body locations in the know line are general knowledge.
Left out how long a tick must be attached to spread disease (it varies by disease) and preventive antibiotics.

### Blister or hot spot (`blister`)

**Sources:** Chapter 2 - Survival Medicine — US Army ATP 3-50.21; Unit Field Sanitation Team (FM 4-25.12); Blisters.

**Open questions:** The nickel-size rule and the moleskin doughnut are from Army ATP 3-50.21. Draining large blisters
is the Army's advice; some WMS guidance prefers leaving intact blisters alone unless they're likely to tear, so check
whether 'drain' should be 'drain if it's tense or likely to burst'. Left out blister-specific products such as
hydrocolloid dressings, since I didn't want to make product claims.

### Crossing a river on foot (`rivercrossing`)

**Sources:** Backcountry Safety (U.S. Forest Service); 20.6. Fording Streams (20. River Travel) — USAF AFH 10-644;
Chapter 7 - Movement and Navigation — US Army ATP 3-50.21.

**Open questions:** Pole technique and the downstream 45-degree angle are from Army ATP 3-50.21. The early-morning
timing for glacial streams and the braided-channel advice are from USAF AFH 10-644. The hip belt, never crossing above
rapids or falls, and the swept-away position are from USFS. 'Face upstream' and 'keep your shoes on' are general
knowledge (the manual implies facing upstream with the pole; Zion's Narrows page says sturdy footwear is essential).
The Army manual also says to put the heaviest person downstream on a shared pole, which I didn't state because it's
easy to garble. Logjams (strainers) are general knowledge. No depth threshold is given because the library doesn't
give a reliable one.

### Fell through ice / cold water (`coldwater`)

**Sources:** The Ship's Medicine Chest and Medical Aid at Sea; Symptoms (Chapter 8: Cold Injury) — US Army ATP
4-25.12; Cold Water Survival and Hypothermia (U.S. Coast Guard); Hospital Corpsman (NAVEDTRA 14295), part 1.

**Open questions:** The kick-and-pull method, getting your trunk onto the ice, and frozen clothing holding you are
from The Ship's Medicine Chest. The roughly 5-minute self-rescue window is from Army ATP 4-25.12 (I wrote 'a few
minutes' rather than give a number). Post-rescue collapse is a USCG stage. Reach or throw, don't go, is from NAVEDTRA
(it's about drowning in general). 'Turn back toward the way you came' and 'roll away from the hole' are standard
ice-safety general knowledge and not in the library. I avoided the popular '1-10-1' rule because it isn't in the
sources. Evacuating anyone who went under is general knowledge.

### Wildfire nearby (`wildfire`)

**Sources:** How to prepare for a wildfire; Wildfire Safety Social Media Toolkit; Know Before You Go: Fire (U.S.
Forest Service); Wildfires.

**Open questions:** The library is thin here. Ready.gov's last-resort advice for being trapped outdoors is quoted
almost exactly, and Ready.gov itself says 'researchers are examining guidance' for that case. 'Fire runs fastest
uphill' and 'go downhill or across the slope, not uphill ahead of it' are general fire-behavior knowledge, not in the
library sources. I also left out the advice to head for already-burned ground ('the black') and to avoid narrow
canyons and saddles, because I couldn't ground them. A wildland fire expert should review this card.

### Signaling for rescue (`signaling`)

**Sources:** Outdoor Emergency Plan: If You Get Lost (National Park Service); Backcountry Safety (U.S. Forest
Service); 21.5.9.1. Aiming Improvised Mirrors (21. Signaling and Communication) — USAF AFH 10-644; 21.5.10.1. Raised
Platform Smoke Generator (21. Signaling and Communication) — USAF AFH 10-644; Get Tech Ready.

**Open questions:** Ready.gov says texts need less bandwidth and get through more reliably on busy networks. Applying
that to weak backcountry signal is my inference. Satellite SOS is general knowledge, and I named no product. The NPS
SOS light pattern is 'three times quickly, three times slowly, three times quickly'. I left out the USAF signal-fire
spacing (three fires 100 ft apart in a triangle) to stay short, and USAF smoke-colour detail beyond green for white
smoke.

### Unplanned night out (`nightout`)

**Sources:** Chapter 6 - Shelter and Clothing — US Army ATP 3-50.21; 13.2. Principles of Shelter Locations and Types
(13. Shelter) — USAF AFH 10-644; Snow Walls, Trenches, and Caves (Chapter 7: Survival) — US Army TC 21-3; Staying Safe
During a Winter Storm (National Weather Service); Outdoor Emergency Plan: If You Get Lost (National Park Service).

**Open questions:** Site selection is from Army ATP 3-50.21 and USAF AFH 10-644. The insulation and debris-roof steps
are a compressed version of the Army debris hut, which calls for at least 3 ft of debris on top and 2 ft underneath
(left out for brevity). The snow trench and wall are from TC 21-3. Moving limbs without overexerting or sweating is
from NWS. 'Don't hike in the dark' is general knowledge. I left out fire on purpose (it has its own card) and because
NPS warns against fires in high fire danger.

### Starting a fire when it's wet (`wetfire`)

**Sources:** Chapter 5 - Fire — US Army ATP 3-50.21; 14.3.3. Getting the Most of Warmth from a Fire (14. Firecraft) —
USAF AFH 10-644; Outdoor Emergency Plan: If You Get Lost (National Park Service).

**Open questions:** From Army ATP 3-50.21 (tinder list, drying tinder in clothing, split inner wood, lower dead
conifer branches) and USAF AFH 10-644 (platform on wet ground or snow, exploding porous rocks). The Army manual says
to gather 'enough to fill their hand with fingers cupped'. I wrote 'two cupped handfuls', a little more. The Army
lists wood soaked in petroleum fuels as kindling. I deliberately left out pouring stove fuel on a fire because of burn
risk, and added no line about it either way.

### Carbon monoxide (`carbonmonoxide`)

**Sources:** Carbon Monoxide From Camping Stoves, Lanterns and Heaters in Tents (CPSC); Camping Equipment and Portable
Heater Carbon Monoxide Safety Alert (CPSC); Carbon Monoxide Poisoning (Chapter 4: Optimizing Physical Care) — US Army
TC 21-3; Carbon Monoxide Poisoning Basics (CDC); Power Outages; Staying Safe During a Winter Storm (National Weather
Service); Carbon Monoxide Poisoning.

**Open questions:** CPSC says the risk is higher at altitude and that CO is easily mistaken for flu. The 20 ft
generator distance is from CDC and Ready.gov. The tailpipe, window and 10-minutes-an-hour advice is from NWS.
Treatment (fresh air, warm, CPR, oxygen, evacuate) is from Army TC 21-3. I left out the Army's 'bright red lips and
skin' sign because it's unreliable and usually seen only after death. 'Never while sleeping' follows CPSC. I didn't
add a flat rule against cooking in a vestibule, which many experienced campers do with ventilation; a reviewer may
want to add one.

### Vehicle won't start (`vehiclestart`)

**Sources:** Staying Safe During a Winter Storm (National Weather Service).

**Open questions:** No government source in the library covers vehicle troubleshooting. A forum check (se-mechanics)
turned up only model-specific threads. Apart from the NWS 'stay with the vehicle' advice, the whole card rests on my
general knowledge and needs a mechanic's review. I deliberately left out the 'hold the pedal to the floor to clear a
flooded engine' tip (true for many fuel-injected cars but not all), cranking-time limits (manuals vary, often 10-15
seconds), anti-theft/immobilizer lights, and diesel glow plugs. The jump-start order is the standard one but should be
checked against the owner's manual (some cars have remote jump posts).

### Vehicle stuck in snow or mud (`vehiclestuck`)

**Sources:** Staying Safe During a Winter Storm (National Weather Service); Gov winter storm partners toolkit.

**Open questions:** The NWS stuck-in-a-storm advice (stay in, 10 minutes an hour, window cracked, clear tailpipe,
bright cloth, raise the hood after the snow stops) and the warning about overexertion are grounded. Sand or kitty
litter for traction is from a Ready.gov kit list (for walkways, but it applies). The digging, wheel-straightening,
low-gear and rocking steps are general knowledge and not in the library sources; forums had nothing useful. I left out
airing down tires, recovery straps and winching, which carry injury risks a short card can't cover. Some automatic
transmissions shouldn't be shifted while the wheels are turning; a reviewer may want a line on that.

### Camp stove won't light or burns weak (`stove`)

**Sources:** Carbon Monoxide From Camping Stoves, Lanterns and Heaters in Tents (CPSC); Know Before You Go: Fire (U.S.
Forest Service).

**Open questions:** No government source covers stove troubleshooting. The canister-cold behaviour (butane boils at
0°C, isobutane at -11.7°C) and jet clogging come from forum answers (se-outdoors). Everything else is my general
knowledge of common canister and white-gas stoves and needs review against manufacturer manuals. Designs vary: some
liquid-fuel stoves prime differently, some canister stoves have inverted-canister modes, and some manufacturers forbid
any windscreen. I left out pump counts, which vary by model. The government sources only ground the CO and fire-safety
lines.

### Dehydration (`dehydration`)

**Sources:** Dehydration; Chapter 2 - Survival Medicine — US Army ATP 3-50.21; Symptoms (Chapter 8: Cold Injury) — US
Army ATP 4-25.12; Travelers’ Diarrhea | CDC Yellow Book 2024.

**Open questions:** Symptoms and red flags are from MedlinePlus. 'Thirst is not an adequate indicator' and the no
alcohol, urine or seawater rule are from Army ATP 3-50.21. ORS is from the CDC Yellow Book. 'Pale urine' is general
knowledge; CDC uses regular urination as the sign that rehydration is working. I gave no daily volume because needs
vary so much. The low-sodium warning points to the existing Heat card.

### Avalanche warning signs (`avalanche`)

**Sources:** Avalanche Safety (Ready.gov, FEMA); When Snow Becomes Deadly: How to Survive an Avalanche (U.S. Forest
Service); 19.3.3.1.3. Weather Factors (19. Land Travel) — USAF AFH 10-644; Forecasting Avalanches (U.S. Forest
Service).

**Open questions:** Recent avalanches, shooting cracks and the 30-degree rule are from Ready.gov. Beacon, probe,
shovel and the 20-30 minute burial window are from USFS. Wind loading, storms and rapid warming are from USAF AFH
10-644 and USFS. The 'whumpf' sound, crossing one at a time, cornices, and not regrouping in runout zones are general
avalanche-course knowledge, not in the library. I left out danger-scale thresholds and what to do while caught
(swimming, airbags) to keep this a warning-signs card. An avalanche educator should review it.

### Saving your phone battery (`phonebattery`)

**Sources:** Get Tech Ready; Chapter 8 - Survival Equipment — US Army ATP 3-50.21.

**Open questions:** Low Power Mode, Airplane Mode and texting are from Ready.gov 'Get Tech Ready' (written for home
emergencies, applied here). Cold and heat degrading batteries is from Army ATP 3-50.21. 'Searching for signal drains
the battery', offline maps, and sending your location early are general knowledge. I didn't describe satellite SOS
(whether it works in Airplane Mode, which phones have it) because I can't ground those product details.

### Dog hurt on the trail (`dog`)

**Sources:** none in the library.

**Open questions:** No government source covers pet first aid. The library search turned up only forum posts
(se-outdoors: dogs often need sedation for quill removal, cost anecdote). The whole card rests on my general knowledge
of common veterinary first-aid advice and needs a veterinarian's review. I left out pain medicines for dogs entirely
(many human drugs, including ibuprofen, are toxic to dogs), sedation, and how long to leave a paw bandage on.

### Sprained ankle far from the trailhead (`sprain`)

**Sources:** Chapter 2 - Survival Medicine — US Army ATP 3-50.21; Strains | Sprains; Ankle Injuries | Ankle Disorders.

**Open questions:** RICE and 'leave the boot on unless circulation is compromised' are from Army ATP 3-50.21.
MedlinePlus confirms the symptoms and early treatment. The four-step weight-bearing test and bone tenderness as
fracture signs come from the Ottawa ankle rules (general medical knowledge, not in the library). I left out icing
durations (the Army gives 24-48 hours intermittently, but no minutes) and taping technique. This overlaps with the
existing Fractures card, which has one sprain line. Decide which card should own sprain questions; I've written asks
for this card and nots on the other side.

### Something in the eye (`eye`)

**Sources:** Hospital Corpsman (NAVEDTRA 14295), part 2; US Army ATP 4-02.11: Casualty Response, Tactical Combat
Casualty Care and First Aid (2026).

**Open questions:** Flushing direction, lower-lid technique and the dry cotton warning are from NAVEDTRA 14295. The
rigid shield, not pressing, covering only the injured eye and not removing protruding objects are from Army ATP
4-02.11. Flush time: NAVEDTRA gives 5-10 minutes for acids and at least 20 minutes for alkalis. Since a hiker can't
tell which, I used 'at least 20 minutes'. I left out flipping the upper lid over a swab (standard, but not in the
sources) and contact lens advice.

### Diarrhea after untreated water (`diarrhea`)

**Sources:** Giardiasis | CDC Yellow Book 2024; Travelers’ Diarrhea | CDC Yellow Book 2024; Giardia Infections;
Giardiasis (Chapter 3: Unit Water Supply) — US Army ATP 4-25.12.

**Open questions:** Giardia timing and symptoms are from the CDC Yellow Book; the Army manual gives a 7-21 day
incubation. Loperamide and bismuth for mild cases, and loperamide not alone with fever or blood, are from the CDC
Yellow Book. I named no dose; the CDC/Medscape passage gives 4 mg then 2 mg per loose stool, up to 16 mg a day, but I
left doses to the package. Bismuth subsalicylate (contains salicylate) cautions for children, pregnancy and aspirin
allergy are left out. The 'within a few days' for bacteria and viruses is general knowledge. The antibiotic options in
the Yellow Book are left to doctors.

### Knocked-out tooth (`tooth`)

**Sources:** The Ship's Medicine Chest and Medical Aid at Sea.

**Open questions:** The library's only real source (The Ship's Medicine Chest) says to soak the tooth in Hanks
solution for 20 minutes and then replant. It ranks storage as milk, then saline, then saliva, then sterile water.
Current International Association of Dental Traumatology guidance (not in the library) is to replant immediately when
possible, and I followed that. Holding by the crown, the brief rinse and not replanting baby teeth are from IADT, as
general knowledge. I left out dentist time windows (often quoted as within 30-60 minutes) because I'm not sure of an
exact number. I also left out the source's antibiotic and analgesic doses.

### Choking (`choking`)

**Sources:** US Army ATP 4-02.11: Casualty Response, Tactical Combat Casualty Care and First Aid (2026); Choking |
Heimlich Maneuver | CPR.

**Open questions:** Army ATP 4-02.11 (2026) gives back blows before abdominal thrusts, the hand position, chest
thrusts for pregnancy or obesity, and what to do if they become unresponsive. Alternating 5 back blows with 5 thrusts
matches my understanding of current Red Cross/AHA guidance, which I'm not sure the library fully states. No blind
finger sweep and seeing a doctor afterward are general knowledge. Infants (under 1) need a different technique; this
card is for adults and older children only. Consider adding an infant line or a separate card. Self-rescue when alone
is also left out.

### Seizure (`seizure`)

**Sources:** Seizures (MedlinePlus); US Army ATP 4-02.11: Casualty Response, Tactical Combat Casualty Care and First
Aid (2026); First Aid (FM 4-25.11); Opening the Airway (CERT Unit 3: Disaster Medical Operations – Part 1 Participant
Manual) — FEMA CERT Basic Training; Hospital Corpsman (NAVEDTRA 14295), part 2.

**Open questions:** Library: MedlinePlus gives 30 s-2 min typical and 5 minutes / repeated seizures without waking as
the emergency line; the Army manuals give ease to ground, support head, don't hold limbs, nothing between the teeth;
CERT gives the recovery position. The rest of the 'evacuate urgently' list (first seizure, injury, in water, pregnant,
diabetic, trouble breathing) and the 'known epilepsy may not need emergency care' line come from CDC's 'First Aid for
Seizures', which the library only links to; they rest on my knowledge of that page and need checking. The Hospital
Corpsman manual says to transport every patient after a seizure ends, which is stricter than CDC; I followed CDC but
made the known-epilepsy line a judgement call, not permission. Left out: rescue medicines (nasal or buccal midazolam,
rectal diazepam) that some people with epilepsy carry, since dosing is theirs; febrile seizures in young children;
focal or absence seizures beyond the 'staring' line. Seizures caused by heat stroke, head injury or low blood sugar
are pointed at only through the evacuate line, so the cause still needs the other cards.

### Stroke (`stroke`)

**Sources:** Stroke | CVA | Cerebrovascular Accident (MedlinePlus); Ischemic Stroke (MedlinePlus); Hemorrhagic Stroke
(MedlinePlus); Transient Ischemic Attack | TIA | Mini-stroke (MedlinePlus); Hospital Corpsman (NAVEDTRA 14295), part
2.

**Open questions:** Signs and 'call right away' are from MedlinePlus; the position (semi-reclining, or on the
paralyzed side) and attention to the airway are from the Hospital Corpsman manual. The smile / arms / sentence test is
the American Stroke Association's BE FAST / FAST check, from general knowledge, not the library. 'Nothing by mouth'
and 'no aspirin' rest on standard AHA/Red Cross first-aid teaching (a stroke can be a bleed, and swallowing may be
impaired); the library has no passage saying it. 'Treatment works only within hours' is deliberately vague: I left out
the 3-4.5 hour clot-buster window and the 24-hour thrombectomy window because they change and won't apply far from a
hospital. 'Even if it goes away' rests on MedlinePlus's TIA page calling a TIA a warning of a stroke. The low-blood-
sugar line is general knowledge; it is a pointer, and conflicts slightly with 'nothing by mouth', which the reviewer
should look at. Changed after drafting: the draft had the person lie 'weak side down' (from the 2000 Hospital Corpsman
manual); current first-aid guidance names no side, so the card says only 'on their side'. The pointer to the low blood
sugar card now says to check their sugar with their meter, so it no longer reads as 'give sugar' next to 'nothing by
mouth'.

### Low blood sugar (diabetes) (`lowbloodsugar`)

**Sources:** Hypoglycemia (MedlinePlus); Insulin in Blood (MedlinePlus); Hospital Corpsman (NAVEDTRA 14295), part 2;
Hospital Corpsman (NAVEDTRA 14295), part 3.

**Open questions:** Signs, causes (too much exercise or too little food after insulin), 'if in doubt give sugar' and
glucagon by injection or nasal spray are in the library (MedlinePlus Hypoglycemia; Hospital Corpsman 'Insulin Shock').
The 15 g / 15 minute rule and the examples (4 tablets, half cup juice or regular soda, a tablespoon of sugar or honey)
are not in the library; they are the CDC/American Diabetes Association '15-15 rule' from my general knowledge, so
check them against the current ADA page. 'Don't use chocolate' is also ADA guidance from general knowledge.
Disagreement: the Hospital Corpsman manual (2000) says to place sugar cubes under the tongue; current Red Cross/AHA
first aid says never put anything in the mouth of someone who cannot swallow, so I followed that. Glucagon is
mentioned without a dose or technique on purpose; the kit's own instructions apply. 'Still confused after two doses'
as the evacuation trigger is my judgement, not a sourced number. High blood sugar and DKA are not covered. Changed
after drafting: 'unsure if high or low: give sugar' now comes before the can't-swallow step and says 'awake', so it
can't be read as sugar for someone who can't swallow.

### Asthma attack (`asthma`)

**Sources:** Asthma | Asthma Symptoms | Asthma Attack (MedlinePlus); Asthma in Children | Asthma Symptoms
(MedlinePlus); Inhalation Injuries | Smoke Inhalation (MedlinePlus); Wildfire Safety Social Media Toolkit (Ready.gov).

**Open questions:** Symptoms, triggers (cold air, smoke, infections, exercise in dry air), the quick-relief inhaler,
'emergency care if it does not work' and the severe signs for children (blue lips, serious breathing problems) are
from MedlinePlus. No library source gives a puff count, so I left it out and pointed to the person's own asthma action
plan; Red Cross and national asthma guidance give different repeat-dosing schemes, which a reviewer could add. The
position (upright, leaning forward), pursed-lip breathing and the buff over the mouth in cold air rest on general
first-aid knowledge (MedlinePlus only lists the 'How to breathe when you are short of breath' handout by title). Left
out: using someone else's inhaler (common advice says it is better than nothing in an emergency but I found no
source), caffeine, and steroid controller inhalers (not for an attack). The anaphylaxis line keeps the boundary with
the Allergic reaction card; the altitude boundary (HAPE) is not stated on the card. Changed after drafting: '(often
blue)' was removed; quick-relief inhalers sold in the U.S. are not reliably blue.

### Emergency childbirth (`childbirth`)

**Sources:** Hospital Corpsman (NAVEDTRA 14295), part 2; Childbirth | Stages of Labor | Effacement (MedlinePlus);
Childbirth Problems (MedlinePlus).

**Open questions:** Signs that birth is near (contractions under 3 minutes, urge to move bowels, crowning),
controlling the head, the cord around the neck, the slippery baby, 'do not pull on the placenta', massaging the lower
abdomen, and urgent transport for a limb or prolapsed cord are from the Hospital Corpsman manual (2000). Where it
differs from current guidance I followed current: it suctions every baby's mouth and nose with a bulb syringe, but
current AAP/AHA newborn guidance suctions only if the airway is blocked, so I left suction out; it clamps and cuts the
cord, but standard wilderness and WHO practice is to delay clamping and there is no need to cut it at all in the
field, so the card says leave it attached; it gently pushes on the head to slow it, which I softened to 'support it'.
Skin to skin and nursing to help the uterus contract are general knowledge (WHO), not in the library. The Corpsman
says the afterbirth comes in 10-20 minutes; 'no afterbirth after an hour' as an urgent trigger is the usual obstetric
threshold from general knowledge and needs review. Left out on purpose: how to tie and cut the cord, breech and
shoulder-stuck manoeuvres, and newborn CPR; a quantified 'too much bleeding' (about 500 ml) because a lay person can't
measure it. This card needs a midwife or obstetric reviewer.

### Animal bite and rabies (`animalbite`)

**Sources:** Medical Treatment for Rabies (Chapter 6: Pest Management) — US Army ATP 4-25.12; Arthropods of Military
Significance (Chapter 6: Pest Management) — US Army ATP 4-25.12; Rabies | CDC Yellow Book 2024; Zoonotic Exposures:
Bites, Stings, Scratches; Rabies (MedlinePlus); US Army ATP 4-02.11: Casualty Response, Tactical Combat Casualty Care
and First Aid (2026); The Ship's Medicine Chest and Medical Aid at Sea.

**Open questions:** Washing: the Army (ATP 4-25.12) says soap and water for at least 15 minutes; the CDC Yellow Book
zoonotic chapter says at least 20 minutes of running water; the Yellow Book rabies chapter adds povidone-iodine. I
used 15 as the floor; the reviewer may prefer 20. Delay closing the wound (Yellow Book: delay suturing for
unvaccinated patients). Bat teeth leaving no visible mark and 'any suspected bat bite is grounds for PEP' are in the
Yellow Book; 'a bat in a tent with someone asleep counts' is CDC's domestic guidance from my general knowledge, not
found in the library. High-risk = unprovoked or ill animal is from the Yellow Book; head bites having shorter
incubation is from the Ship's Medicine Chest; the hand line rests on general infection-risk knowledge. I left out any
deadline for starting shots: the Army says PEP still works weeks or months later, while CDC says begin as soon as
possible, so the card says 'as soon as you can' without a number. Also left out: the 10-day observation of a healthy
pet dog or cat (Ship's Medicine Chest, CDC), keeping a bat for testing, tetanus, and B virus after monkey bites.

### Tornado with no building nearby (`tornado`)

**Sources:** Tornadoes (Ready.gov); Gov tornado info sheet (Ready.gov); Guide for alerts and warnings 2021.pdf
(Ready.gov); Emergency preparedness curriculum grades (Ready.gov); 6.4.4. Winter Storms (6. Weather) — USAF AFH
10-644.

**Open questions:** The library has no NWS tornado-safety page (Ready.gov only links to it), so the card rests on
FEMA/Ready.gov, which follows NWS guidance. Disagreement: the USAF survival handbook says get as far from cars as you
can and lie in a ditch; Ready.gov says stay in the car belted with your head down, or leave it only for ground clearly
lower than the road. I followed Ready.gov. Ready.gov also says both 'do not try to outrun a tornado' and 'you may
drive at right angles if it is far away and traffic is light'; the card keeps both, limited by distance and traffic.
Conflict with the existing Thunderstorm card, which says don't lie flat (lightning); for a tornado the guidance is to
lie flat, so the two cards give opposite body positions and the matcher must keep them apart. A ditch can flood in the
heavy rain that comes with tornadoes; no source addresses that trade-off, so I left it out. 'Flying debris causes most
injuries' paraphrases Ready.gov's 'deadly flying debris'. Watch vs warning definitions left out for length.

### Small engine won't start (`smallengine`)

**Sources:** Power Outages (Ready.gov); Carbon Monoxide Poisoning Basics (CDC).

**Open questions:** Almost all of this card rests on general knowledge. The government library has nothing on small-
engine troubleshooting; the only government passages used are Ready.gov's generator safety (let it cool before
refueling) and CDC carbon monoxide. --all found forum posts (se-diy 'Why won't my generator start', se-mechanics
flooded-engine and won't-start threads) that agree with the fuel / air / spark order and say old fuel and a clogged
carburetor are the most common cause; those are forum text. Differences by engine type: two-strokes (most chainsaws,
many older outboards and snowmobiles) run on oil mixed into the fuel or injected, so the wrong mix or no oil matters
and they foul plugs more easily; four-strokes (most generators, newer outboards, ATVs) have a crankcase with oil, and
many have a low-oil shutoff; fuel-injected machines (many modern snowmobiles, ATVs and outboards) have no choke and no
primer bulb, and for a flooded fuel-injected engine the clearing method is set by the maker (often holding the
throttle open while cranking cuts fuel, but not on all), so the reviewer may want 'choke' and 'flooded' steps marked
carburetor only. The 'wait 15 minutes' for a flood is a common rule of thumb, not a sourced number. Left out: spark
testing by grounding the plug (shock risk), starting fluid (can damage two-strokes; product-specific), carburetor
cleaning, plug gaps, fuel-age limits (depends on fuel and stabilizer), and outboard-specific checks such as the tilt
or water intake.
