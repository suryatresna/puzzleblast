extends RefCounted
## Tetromino definitions in Super Rotation System (SRS) form.
##
## IMPORTANT: cells and kick offsets below use Godot's screen convention where
## +y points DOWN. The published SRS kick tables are written with +y UP, so
## every y here has already been negated. Do not flip them again.

enum { I, J, L, O, S, T, Z }

const COUNT := 7

const COLORS := [
	Color("22d3ee"), # I - cyan
	Color("5b7cfa"), # J - blue
	Color("ff9f45"), # L - orange
	Color("ffd452"), # O - yellow
	Color("4ade80"), # S - green
	Color("9b8cff"), # T - violet
	Color("fb7185"), # Z - rose
]

## Per type, per rotation state (0 = spawn, 1 = CW, 2 = 180, 3 = CCW),
## the four occupied cells within the piece's bounding box.
const SHAPES := [
	# I
	[[Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)],
	 [Vector2i(2,0), Vector2i(2,1), Vector2i(2,2), Vector2i(2,3)],
	 [Vector2i(0,2), Vector2i(1,2), Vector2i(2,2), Vector2i(3,2)],
	 [Vector2i(1,0), Vector2i(1,1), Vector2i(1,2), Vector2i(1,3)]],
	# J
	[[Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
	 [Vector2i(1,0), Vector2i(2,0), Vector2i(1,1), Vector2i(1,2)],
	 [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(2,2)],
	 [Vector2i(1,0), Vector2i(1,1), Vector2i(0,2), Vector2i(1,2)]],
	# L
	[[Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
	 [Vector2i(1,0), Vector2i(1,1), Vector2i(1,2), Vector2i(2,2)],
	 [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(0,2)],
	 [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(1,2)]],
	# O
	[[Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
	 [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
	 [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
	 [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)]],
	# S
	[[Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1)],
	 [Vector2i(1,0), Vector2i(1,1), Vector2i(2,1), Vector2i(2,2)],
	 [Vector2i(1,1), Vector2i(2,1), Vector2i(0,2), Vector2i(1,2)],
	 [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,2)]],
	# T
	[[Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
	 [Vector2i(1,0), Vector2i(1,1), Vector2i(2,1), Vector2i(1,2)],
	 [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(1,2)],
	 [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(0,2)]],
	# Z
	[[Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(2,1)],
	 [Vector2i(2,0), Vector2i(1,1), Vector2i(2,1), Vector2i(1,2)],
	 [Vector2i(0,1), Vector2i(1,1), Vector2i(1,2), Vector2i(2,2)],
	 [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(0,2)]],
]

## Wall kicks, keyed "<from>><to>". Each list is tried in order; the first
## offset that leaves the piece in a legal spot wins.
const KICKS_JLSTZ := {
	"0>1": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,2), Vector2i(-1,2)],
	"1>0": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,-2), Vector2i(1,-2)],
	"1>2": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,-2), Vector2i(1,-2)],
	"2>1": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,2), Vector2i(-1,2)],
	"2>3": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,-1), Vector2i(0,2), Vector2i(1,2)],
	"3>2": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,-2), Vector2i(-1,-2)],
	"3>0": [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,-2), Vector2i(-1,-2)],
	"0>3": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,-1), Vector2i(0,2), Vector2i(1,2)],
}

const KICKS_I := {
	"0>1": [Vector2i(0,0), Vector2i(-2,0), Vector2i(1,0), Vector2i(-2,1), Vector2i(1,-2)],
	"1>0": [Vector2i(0,0), Vector2i(2,0), Vector2i(-1,0), Vector2i(2,-1), Vector2i(-1,2)],
	"1>2": [Vector2i(0,0), Vector2i(-1,0), Vector2i(2,0), Vector2i(-1,-2), Vector2i(2,1)],
	"2>1": [Vector2i(0,0), Vector2i(1,0), Vector2i(-2,0), Vector2i(1,2), Vector2i(-2,-1)],
	"2>3": [Vector2i(0,0), Vector2i(2,0), Vector2i(-1,0), Vector2i(2,-1), Vector2i(-1,2)],
	"3>2": [Vector2i(0,0), Vector2i(-2,0), Vector2i(1,0), Vector2i(-2,1), Vector2i(1,-2)],
	"3>0": [Vector2i(0,0), Vector2i(1,0), Vector2i(-2,0), Vector2i(1,2), Vector2i(-2,-1)],
	"0>3": [Vector2i(0,0), Vector2i(-1,0), Vector2i(2,0), Vector2i(-1,-2), Vector2i(2,1)],
}


static func cells(type: int, rot: int) -> Array:
	return SHAPES[type][rot & 3]


## O never kicks (it is rotationally symmetric); I has its own table.
static func kicks(type: int, from_rot: int, to_rot: int) -> Array:
	if type == O:
		return [Vector2i.ZERO]
	var key := "%d>%d" % [from_rot & 3, to_rot & 3]
	if type == I:
		return KICKS_I.get(key, [Vector2i.ZERO])
	return KICKS_JLSTZ.get(key, [Vector2i.ZERO])
