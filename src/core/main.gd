extends Node
## Root of main.tscn. Hands control to the Game autoload, which builds every
## other scene from code. This file stays tiny on purpose.


func _ready() -> void:
	Game.boot(self)
