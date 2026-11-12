# Library sources and licenses

BackcountryAI is a paid app, so the library holds only sources that allow commercial redistribution:
U.S. government works (public domain), UK public sector information (Open Government Licence) and Creative Commons
Attribution-ShareAlike text. Every article in the app shows its source, license and original address.
`scripts/check-licenses.sh` refuses any library with a non-commercial, no-derivatives, "not for resale" or
unlicensed source, and every release runs it.

The build scripts in `library/` are adapted from [Survival LLM](https://github.com/anonnerdfrenzy/survival-llm)
(MIT, `library/LICENSE-survival-llm`), whose license review (2026-10-24) this table builds on.

| Source | License |
|---|---|
| WikiMed, Wikipedia's medical articles (Kiwix `wikipedia_en_medicine`) | CC BY-SA 4.0, Wikipedia contributors |
| MedlinePlus, NLM-written pages only (Kiwix `medlineplus.gov_en_all`) | Public domain (U.S. National Library of Medicine) |
| UK Medicines A to Z (Kiwix `nhs.uk_en_medicines`) | Contains public sector information licensed under the Open Government Licence v3.0. Not presented as the NHS website. |
| CDC Travelers' Health, including the online Yellow Book (Kiwix `wwwnc.cdc.gov_en_all`) | Public domain (CDC) |
| Ready.gov (Kiwix `ready.gov_en_all`) | Public domain (FEMA) |
| Military medicine manuals (Kiwix `irp.fas.org_en_military-medicine`) | Public domain (U.S. government) |
| U.S. government survival and first-aid manuals: AFH 10-644 SERE, ATP 3-50.21 Survival, ATP 4-02.11 First Aid, TC 21-3 Cold Weather, ATP 4-25.12 Field Sanitation, TB MED 577 Field Water, TB MED 507 Heat, FEMA Are You Ready?, FEMA CERT, JTS Prolonged Casualty Care | Public domain (17 U.S.C. 105) |
| U.S. government safety guides (`library/guides.tsv`, 63 pages): National Park Service (bears, mountain lions, moose, lightning, flash floods, getting lost), National Weather Service and NOAA (lightning, floods, cold water, winter, heat, clouds), U.S. Coast Guard (cold water), Forest Service (avalanches, chain saw course, fire, hiking), OSHA (chainsaws, generators), CDC (downed power lines, carbon monoxide, food after floods, snakes, ticks, cold and heat stress), CPSC (carbon monoxide from camping gear), FDA and USDA (food after floods and outages), National Eye Institute (eye first aid), Ready.gov (avalanche) | Public domain (17 U.S.C. 105) |
| Risk references: SSA life table, CDC mortality reports, NHTSA crash overview, NWS lightning odds, plus Wikipedia's micromort and risk articles | Public domain; Wikipedia articles CC BY-SA 4.0 |
| USDA Complete Guide to Home Canning (Kiwix `usda-2015_en`) | Public domain (USDA) |
| Appropedia, Energypedia, WikiCiv | CC BY-SA 3.0 or 4.0 (per page) |
| Stack Exchange: Home Improvement, The Great Outdoors, Cooking, Gardening, Lifehacks, Sustainable Living, Amateur Radio, Medical Sciences, Motor Vehicle Repair, Bicycles, Pets | CC BY-SA 2.5, 3.0 or 4.0 by post date, with each post's author |

## Left out

- **Non-commercial:** wikiHow and iFixit (CC BY-NC-SA 3.0), the IFRC First Aid Guidelines, and WHO's
  Basic Emergency Care, childbirth and drinking-water guides (CC BY-NC-SA 3.0 IGO).
- **Not for resale:** the Emergency Response Guidebook 2024.
- **Copyrighted additions:** Nuclear War Survival Skills (1986 additions copyright Cresson H. Kearny).
- **Third-party licensed sections of MedlinePlus:** the A.D.A.M. encyclopedia (`/ency/`), ASHP drug
  information and Natural Medicines (`/druginfo/`).
- **Military volumes that reprint copyrighted material:** Military Dermatology, War Psychiatry, FM 21-11.
- **Mixed or unknown rights:** Kiwix "zimgit" collections and Gardenology.
- **No longer published:** WikEM. Kiwix dropped it; the only copies left are from 2018.
- **All rights reserved:** Hesperian books, MSF guidelines, Red Cross manuals and commercial survival books.

## Still to confirm before release

- **NHS medicines:** the Open Government Licence allows commercial use. The nhs.uk terms also say not to
  imply NHS endorsement or use its logo. The app doesn't do either, but read the current terms once.
- **CDC Yellow Book:** the online text is a CDC work, while Oxford University Press publishes the print
  edition. Check that the online chapters carry no separate copyright notice.
