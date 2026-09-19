# Memo, 2026-09-18 21:02 (Carl and Julian, a play session with the mic open)

Source: `memos/2026-09-18 21-02-05.mp3` (raw transcript beside it, `.raw.txt`)
Duration: 3:22:15, 630 spoken segments; long silences while agents ran
Speakers: Carl and Julian. Whisper has no speaker labels; who said what is
inferred from context and marked where it matters.

The evening started with a Free-for-all on Kopje Crossing (the Safari map) in
the pre-letters build, with the sword's reach turned up to its maximum. Carl's
agents were rebuilding the letters game (one letter at a time, the capture
performance, the guide line and minimap) and remaking two maps; Julian was
downloading a mining asset pack and having his Claude remake Twin Quarry with a
tunnel. Around 1:42 they tried Carl's new exe and it froze both lobbies; that
was fixed the same night (commit 6b1ab6c, "a tutorial drawing loop that could
step by nothing and froze two players' lobbies"). From 1:56 Carl set up Linear
and walked Julian through the MCP server. Julian asked at 1:40 whether it was
still recording; Carl said the whole memo would be handed to Claude, and both
agreed that anything said as brainstorming should be flagged as such.

## Wants

1. **A Bog can emote while carrying a letter.**
   `[0:03:43]` "You can't emote while you have a letter." `[0:03:45]` "I don't
   think that matters, but like, I'd rather, I want to taunt people, bro."
   `[0:03:59]` "Yeah, you definitely should be able to."
   Touches: `BogCombat.can_emote()` refuses while `is_holding_letter()`; no
   D-record explains the gate, so it is a rule nobody chose. Both agreed.

2. **The sword's swing shows its reach: a visible arc or swipe, and a hit
   shape that matches it.**
   `[0:04:17]` "Sword needs to be completely redone, I feel like." `[0:04:21]`
   "It needs like some visual to see like where it's like swinging, like its
   death range... like a wind-like swipe." `[0:11:47]` "I'm curious how the
   range works... I think it's just like a rectangle in front of me so like if
   you're a little to the side it doesn't kill you." `[0:11:59]` "That's why I
   was thinking we need some sort of like animation or like effect to see where
   it's actually swinging." Also on the number: `[0:02:56]` "I maxed that shit
   out to six meters"; `[0:09:29]` "the sword is not too bad, if you just bump
   up the radius up a bit... maybe it's just fine tuning"; `[0:11:28]` "6 is
   too big bro."
   Touches: `MatchConfig.sword_reach` (default 1.43, max 6.0), the sword chain
   in D-121/D-122, `tools/combat_range.tscn -- sword`. Not a reach change: they
   found 6 too big and default a bit short, and the real ask is seeing it.

3. **Kopje Crossing's high ground has more than one way up.**
   `[0:05:29]` "This map sucks, bro. Who made this map?" `[0:05:30]` "It's fun
   once you get up top... If you're down below, it's kinda ass." `[0:05:44]`
   "You can't even make that jump anymore." `[0:05:47]` "Yeah, I think there's
   literally only one way to get up there." `[0:05:55]` "once you get up there
   first, it's pretty fucked up."
   Touches: `scenes/world/maps/safari.tscn`, the parkour report; "that jump"
   probably stopped working when the jump arc changed (D-123/D-125). The
   movement round (BOG-44) is the other answer to this.

4. **Movement on the maps, and a movement item everyone carries.**
   `[0:03:34]` "We need to add some movement to this map, bro." `[0:07:16]` "we
   need map made movement items... or we should give everyone a movement item,
   you should equip like a movement item... more like a quick one, like a
   shockwave." `[0:07:50]` "or a hamster ball that has a plunger suction cup."
   `[0:08:10]` "a knockback grenade would be cool but it's just the opposite of
   the magnet."
   Touches: BOG-44 (the movement round, Backlog, waiting on Carl's §7 call in
   `docs/PLAN_MOVEMENT.md`). New in this memo: an *equipped* movement item
   rather than a pickup, and knockback as a candidate.

5. **Items are assigned at the start; deaths drop letters only, with a rare
   "wizard item" drop.** Said with hedges; treat as a lean, not a decision.
   `[0:08:25]` "you don't get items very much, items should maybe instead of
   people dropping you should just assign them at the start." `[0:08:33]`
   "Let's make it the only thing people drop are letters." `[0:08:36]` "Except
   that's what I'm actually going to do. So we're not going to drop items
   anymore. I don't know, I guess you can drop items. Maybe only sometimes
   you'll drop a wizard item, something that you become that for a second. And
   then the kind of items, the throwables, you assign yourself those. But it
   doesn't make sense because then you have to worry about like a cooldown on
   them."
   Touches: `MatchState` drop rates (`match_config.gd` ~261, shield/magnet 2%),
   D-129 (letters deal on death), the weapon pick in the lobby (D-069).

6. **Bunny-hopping is too strong.**
   `[0:03:05]` "you better stay away from your boy, the bunny hoppers is
   completely broken."
   Touches: BOG-28 (jump fatigue, Todo).

7. **A map-building skill, with the theming brief written into it.** Said
   three times, and "next".
   `[0:00:37]` (the prompt that worked for Rust) "look at the Enchanted Forest
   map, and make sure to put the same amount of effort into the theming and the
   ambiance and the general feel and lighting... ambiance, lighting, theme,
   background, like skybox." `[0:52:27]` "we should make a map building skill
   bro." `[1:10:24]` "a map building skill. It should describe like, to make
   sure Claude puts like a lot of effort into the skybox and into the lighting,
   not like low lighting, like just like intentional cool lighting. Like the
   background, like the far distance, the clouds... It should probably have its
   own asset pack or build new versions based off of asset packs. We should
   avoid just making them out of nothing. Because then Claude just makes up
   random shapes that aren't too good. Asset packs have textures." `[1:11:13]`
   "it should also ask like a bunch of questions at the start... we should try
   to move away from maps just being like a one square with just like a bunch
   of models rendered on top, like ideally the actual structure of it can be
   more complex... like Fortnite has hills and stuff... structural
   differences, not just a flat thing." `[2:50:10]` "i really think we should
   make a map making skill next."
   Touches: BOG-29 (Todo, Medium). The ticket has the contract list; it lacks
   the theming brief, the asset-pack rule, the opening questions and the
   terrain point.

8. **The aim camera sits further to the right.** Ambiguous: said before the
   PvP camera rework merged (22:57, which is 1:55 into the memo), and Carl may
   have done it for the bow already.
   `[0:58:08]` "i feel like the camera when you're ADS needs to be a little
   more over to the right." `[1:03:06]` "yeah i did that but yeah i did that
   with the bow." `[1:03:17]` "i only told it to move like 10 degrees."
   Touches: `BogCamera.SHOULDER_AIMING` 0.48 against `SHOULDER_DEFAULT` 0.62
   (aiming pulls the camera *toward* centre today), D-045's aim section,
   `docs/PLAN_CAMERA.md`.

9. **Twin Quarry is remade from a mining asset pack, with a tunnel or cave
   under it.** Julian's work, in progress on his machine.
   `[0:34:33]` "it's a quarry so I want like mining stuff like slightly
   industrial." `[0:35:55]` "you can make like an underground part to it...
   a cave under there." `[1:14:06]` "the quarry is going to have a tunnel. And
   then I kind of want to make a whole map that is inside a tunnel, way more
   like mining. I'll do that later." `[2:52:57]` "i'm still working on
   textures but like that only affects that map."
   Touches: `scenes/world/maps/quarry.tscn`, BOG-20 (quarry kerb nav links).
   The pack was 5 GB, trimmed to 62 MB through the decimate pipeline.

10. **The guide line may be unnecessary now the minimap exists.**
    `[2:49:49]` (Julian) "i don't like that fucking line bro." (Carl) "it's
    done right now but i'm just gonna test and see how it worked out, like the
    real thing is just like it's on the mini map, so yeah it's not necessary."
    Touches: BOG-35 (guide line, In Review), BOG-37 (minimap, In Review). A
    verdict for the review queue, not a new ticket.

11. **An FPS counter.**
    `[1:05:28]` "when you got a fps counter man it has to be down there, we
    also go to steam we can use steams because there's no way you're getting
    like the same fps in the maps as this one."
    Touches: Settings panel (`scripts/ui`), nothing tracked.

12. **Another melee weapon and another ranged weapon.**
    `[3:08:12]` "I think we should add another melee weapon and another ranged
    weapon." "okay yeah i agree i agree."
    Touches: the weapon pick (D-069), `scripts/items`, BOG-25 (spear carry
    pose). Nothing tracked; which weapons is open.

13. **Process, not a ticket: before a change with a big blast radius,
    investigate and raise the issues first.**
    `[0:12:52]` "for these more complex changes make sure you have it talk to
    you about any issues in my cause first so you can make decisions on them...
    if the change has like a big blast radius or is kind of unclear, before you
    actually go off and do it, do some investigating and let me know if there's
    any issues you foresee so we can figure it out first... because if that
    comes up later it's like oh actually i didn't want that, i just wasted a
    bunch of shit."
    Kept as a working rule (memory), not in Linear.

## Not wants

- `[0:02:41]` "a mini map is currently being added" and `[0:10:13]` one letter
  at a time: both landed that night (BOG-37, BOG-34 / D-129, D-132).
- `[0:42:56]` the capture animation and arrows: BOG-36, In Review.
- `[1:42:31]`–`[1:49:19]` the lobby freezing on NEXT, "a main thread loop that
  never ends": fixed in 6b1ab6c. `[1:43:08]` "you should add end task" was a
  joke about the frozen window.
- `[0:06:03]` "that's a spear in your back, why you ain't dead" and `[0:06:55]`
  "how did you lose half your hp though, maybe fall damage": one-off confusion
  in a fight; there is no fall damage in the code. Watch for it in play.
- `[0:00:18]`, `[0:12:30]` Carl remaking two maps with the theming prompt:
  Carl's own in-flight work, the prompt itself is want 7.
- `[1:14:36]` naming the AI so it can be addressed in a memo; `[1:12:55]` say
  "brainstorming" out loud when it is: both are now in the memo skill.
- `[2:40:52]`–`[2:41:40]` money, skins, Roblox; `[3:02:20]` what Claude Max
  makes possible; `[0:30:49]`–`[0:33:45]` usage limits and agents; `[1:04:01]`
  fishing on Saturday; `[2:29:50]` "why do we need tickets, there's only two of
  us": chat.
- `[0:01:47]` "I don't go bow", `[0:01:52]` "I love the spear too much",
  `[0:09:38]` "have to commit to something so early on": preferences about the
  weapon pick, no ask attached.
