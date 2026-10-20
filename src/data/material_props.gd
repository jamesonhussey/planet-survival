class_name MaterialProps
extends RefCounted
## Typed view of one entry in data/materials.json. Hazard sims index an
## Array[MaterialProps] by block id and read only these fields.

var id: int = 0
var name: String = "air"
var display: String = "Air"
var solid: bool = false
var fluid: bool = false
var transparent: bool = false
var hardness: float = 0.0
var tool: String = "none"
var drop: String = ""
var waterproof: bool = false
var airtight: bool = false
var opacity: float = 0.0
var heat_resistance: float = 0.0
var flammability: float = 0.0
var strength: float = 0.0
var buoyancy: float = 0.0
var weight: float = 0.0
var emissive: float = 0.0     # self-illumination (rendered via vertex colour alpha)
var light: float = 0.0        # omni light range in blocks (0 = none)
var heat: float = 0.0         # warmth source strength 0..1
var station: String = ""      # crafting station this block provides
var texture: Dictionary = {}


static func from_dict(d: Dictionary) -> MaterialProps:
	var m := MaterialProps.new()
	m.id = int(d.get("id", 0))
	m.name = str(d.get("name", "air"))
	m.display = str(d.get("display", m.name.capitalize()))
	m.solid = bool(d.get("solid", true))
	m.fluid = bool(d.get("fluid", false))
	m.transparent = bool(d.get("transparent", false))
	m.hardness = float(d.get("hardness", 1.0))
	m.tool = str(d.get("tool", "none"))
	var drop_v: Variant = d.get("drop", "")
	m.drop = "" if drop_v == null else str(drop_v)
	m.waterproof = bool(d.get("waterproof", false))
	m.airtight = bool(d.get("airtight", false))
	m.opacity = clampf(float(d.get("opacity", 1.0)), 0.0, 1.0)
	m.heat_resistance = clampf(float(d.get("heat_resistance", 0.0)), 0.0, 1.0)
	m.flammability = clampf(float(d.get("flammability", 0.0)), 0.0, 1.0)
	m.strength = float(d.get("strength", 0.0))
	m.buoyancy = clampf(float(d.get("buoyancy", 0.0)), -1.0, 1.0)
	m.weight = float(d.get("weight", 0.0))
	m.emissive = clampf(float(d.get("emissive", 0.0)), 0.0, 1.0)
	m.light = float(d.get("light", 0.0))
	m.heat = clampf(float(d.get("heat", 0.0)), 0.0, 1.0)
	m.station = str(d.get("station", ""))
	var tex: Variant = d.get("texture", {})
	m.texture = tex if tex is Dictionary else {}
	return m


## True if a gas/light/fluid cell can be "inside" this block (i.e. it does not
## fill the cell). Air and fluids count as open for different sims, so sims
## should still check the specific property they care about.
func is_open() -> bool:
	return not solid
