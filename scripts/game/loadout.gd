class_name Loadout
extends RefCounted
## Which weapon a player brought (D-069). One value, chosen in the lobby, and
## the only thing about a Gub's armament that is a choice.
##
## It is deliberately **not** a `MatchConfig` field. The dials in that resource
## are the host's — one value for the whole match, pushed to everybody — and
## this is the opposite shape: one value *per player*, requested by that player
## and kept in their roster row beside their name and their team. So it lives
## where the rest of a player's row lives (`Net.players`) and travels the way
## the rest of it travels: host-authoritative, rebroadcast whole, never diffed
## (D-004). There is no parallel channel and no second copy.
##
## Why a class of static helpers rather than an enum dropped into `MatchConfig`
## or `Net`: four files ask this question — `Net` stores it, `GubCombat` gates
## on it, `GubBackdrop` and `MatchState` seed a Gub from it, and the lobby draws
## it — and three of those must not have to load the other two to name a
## constant. A `class_name` with nothing but statics on it is reachable from all
## of them and owned by none.

## The three weapons, in the order the picker shows them.
##
## **Appended to, never reordered**, and for the same reason
## `MatchConfig.WinCondition` carries that warning: the *ordinal* is what goes on
## the wire and what sits in a roster row, so inserting a weapon in the middle
## would silently turn every peer's spear into somebody else's bow.
##
## `SPEAR` is zero on purpose. It is the default (below), and zero is what an
## absent key, a cleared dictionary and a roster row written by a harness that
## predates this all read as.
enum Weapon {
	SPEAR,  ## a one-shot you have to lead (D-025, D-062)
	BOW,    ## a 20-80 draw that out-ranges everything (D-065)
	SWORD,  ## a melee one-shot that is also the best mobility in the game (D-068)
}

## What a player who never opens the picker plays.
##
## The spear, because it is what every Gub carried before this existed: the
## whole point of the default is that a lobby which ignores the feature plays
## exactly the match it played yesterday.
const DEFAULT := Weapon.SPEAR

## Indexed by the enum. Kept here rather than in the lobby so that the picker,
## the chat line a change could produce and any future scoreboard column all
## spell a weapon the same way.
const NAMES := ["Spear", "Bow", "Great sword"]

## One line each, for under the buttons. Short enough to sit on a strip and
## specific enough to be a reason rather than flavour — each says the thing that
## makes that weapon a different match to play.
const BLURBS := [
	"One throw, one kill. Lead your target.",
	"Hold to draw. The longest reach in the game.",
	"A spinning one-shot that carries you forward.",
]


## Turn anything that arrived from outside into a weapon.
##
## **The host's validation, and the reason a client cannot lie about its
## weapon** (D-004, D-024). There is no restriction to enforce — all three are
## always available to everyone, which was decided before this step started — so
## what is left to check is the only thing a peer could get wrong or malicious
## about: an ordinal that is not one of the three. Anything out of range, of the
## wrong type, or missing entirely reads as the default, which is the same
## answer an old roster row gives and is therefore one rule rather than two.
static func sanitize(value: Variant) -> int:
	if value is not int and value is not float:
		return DEFAULT
	var index := int(value)
	if index < 0 or index >= NAMES.size():
		return DEFAULT
	return index


## The weapon's name, for anything that shows one.
static func weapon_name(weapon: Variant) -> String:
	return NAMES[sanitize(weapon)]


## The one line under it in the picker.
static func blurb(weapon: Variant) -> String:
	return BLURBS[sanitize(weapon)]


## Every weapon, in picker order. A helper rather than `Weapon.values()` at each
## call site, so the strip and the harnesses iterate the same list.
static func all() -> Array[int]:
	return [Weapon.SPEAR, Weapon.BOW, Weapon.SWORD]


## The clip a Gub stands in while it is carrying this weapon and doing nothing
## else with it (D-070), indexed by the enum.
##
## **This is the one table in the game that is indexed by the weapon**, and it is
## a table rather than a branch on purpose. D-069's own record is emphatic that
## *"nothing anywhere branches on which weapon a Gub has"* — the three gates are
## four clauses of one sentence, the input polls all three unconditionally, and
## the hand is drawn from the gates. A carry pose cannot be any of that: a bow is
## held differently from a great sword, and no amount of phrasing makes those one
## pose. So the difference lives here, beside `NAMES` and `BLURBS`, in the file
## that already exists to say what the three weapons *are* — and every reader of
## it is a lookup rather than a `match`. `GubAnimator` asks it once a frame and
## hands the answer to a `Transition` node; nothing else asks it at all.
##
## **The spear's row is the Gub's own `Idle`, and it is the one entry here that
## is not a weapon clip at all** (D-072). The user, shown the spear standing in
## `SwordCarry`: *"This spear is only thrown so 2 hands doesnt make sense. I like
## the original one because it looks like hes holding it up with one hand ready
## to throw."*
##
## That is a statement about the **weapon**, and it is the thing D-070 had no way
## to score. D-070 put three candidate poses to `-- solve` and took the one that
## laid 1.24 m of shaft flattest:
##
##   pose over which the grip was solved   flattest   floor    trunk
##   Idle, the Gub's own boxer's guard       12 deg    0.45 m   0.09 m
##   BowCarry, a longbow at rest             55 deg    0.12 m   0.25 m
##   SwordCarry, a great sword at rest      **5 deg**  0.33 m   0.15 m
##
## `SwordCarry` won because it is the only genuine **two-handed** pose in the
## project — both fists together in front at waist height, 0.22 m apart — which
## puts the shaft across the body where no amount of hip pitch can tilt it. Every
## word of that is still true and it was still the wrong answer: a thrown spear
## is held in **one** hand, and port arms is the stance of somebody carrying a
## pole rather than somebody about to throw. The flattest pose and the right pose
## were not the same pose, and no number in that table could have said so.
##
## So the spear goes back on `Idle` — the hunched guard this game has always had,
## right fist up beside the head — **with the grip re-solved underneath it**, so
## that the shaft out of that raised fist lies level and leads forward instead of
## standing up. `HeldGear.GRIP_ROTATION` carries the derivation and the bearing.
##
## **Pointing `carry` at `Idle` is not the same as pointing it at nothing**, and
## the difference is the whole reason this row is a clip name rather than `""`.
## The layer still holds `UPPER_BODY_BONES` in one pose across the whole
## locomotion plane, which is what gives the grip a single hand orientation to be
## solved against — and a Gub standing still is in exactly the clip it would have
## been in anyway, so the idle the user asked for is the idle they get, in the
## ring and in a match. Taking the layer away was measured and is a different
## animal: the shaft swings 64 deg across the set, ploughs the grass in six of
## the twelve clips and passes 0.002 m from the chest in `StrafeRight` — and it
## crashes `GubAnimator._build_graph`, which cannot build an
## `AnimationNodeAnimation` out of an empty clip name.
##
## A spear Gub and a sword Gub now stand differently, which is the read
## `HeldGear`'s header wanted all along. **A spear idle of its own is no longer
## waiting on anybody**: what a download would buy is a pose built around the
## prop, and the pose the user asked for is the one already on disk.
const CARRY_CLIPS := ["Idle", "BowCarry", "SwordCarry"]


## The carry clip for `weapon`, or "" for one with none.
static func carry_clip(weapon: Variant) -> String:
	return CARRY_CLIPS[sanitize(weapon)]


## A weapon named on a command line, for the harnesses. Case-insensitive on the
## first word of `NAMES`, so `sword` finds "Great sword".
static func from_name(text: String) -> int:
	var want := text.strip_edges().to_lower()
	for weapon in all():
		if NAMES[weapon].to_lower().begins_with(want) \
				or NAMES[weapon].to_lower().ends_with(want):
			return weapon
	return DEFAULT
