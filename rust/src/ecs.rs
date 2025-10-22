use godot::prelude::*;
use godot::classes::Sprite2D;

#[derive(GodotClass)]
#[class(base=Sprite2D)]
struct UnitECS {
    speed: f64,
    angular_speed: f64,

    base: Base<Sprite2D>
}
