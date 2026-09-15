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
## **The spear borrows the great sword's, and that is the answer to "the spear
## should be horizontal".** There is no spear carry clip on disk — the two that
## arrived are a bow's and a sword's — so the spear's row is the one that had to
## be solved rather than downloaded, and the three candidates already built were
## scored against each other by `tools/preview_carry.tscn -- solve`:
##
##   pose over which the grip was solved   flattest   floor    trunk
##   Idle, the Gub's own boxer's guard       12 deg    0.45 m   0.09 m
##   BowCarry, a longbow at rest             55 deg    0.12 m   0.25 m
##   SwordCarry, a great sword at rest      **5 deg**  0.33 m   0.15 m
##
## `Idle` cannot be flat because its fist is up beside a head that is 0.5 m of
## blob: a level shaft from there either crosses the face or points backwards,
## and the best bearing that misses the Gub still swings 12 degrees across the
## set. `BowCarry` puts the right fist at the hip, which is where a javelin is
## really carried, and it reads beautifully in `Idle` — but the shaft then lies
## in the sagittal plane, so every degree of pelvis pitch is a degree of spear,
## and `Run` tips it to 55. `SwordCarry` holds both fists together in front at
## waist height, which puts the shaft **across** the body where no amount of hip
## pitch can tilt it, and both hands land on it. It is port arms, and it is the
## horizontal reading of D-065's own target — *"a Gub in a guard stance with a
## spear held upright reads as armed"* — with the word "upright" answered.
##
## A spear Gub and a sword Gub therefore stand identically and are told apart by
## what is in their hands, which is the read `HeldGear`'s header asks for anyway.
## A spear idle of its own is one Mixamo download and would close it; nothing
## waits on it.
const CARRY_CLIPS := ["SwordCarry", "BowCarry", "SwordCarry"]


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
