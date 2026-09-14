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
