use godot::prelude::*;

mod holymap;
mod bytemap;
mod npc_data_warehouse;

struct Godo;

#[gdextension]
unsafe impl ExtensionLibrary for Godo {
    fn on_level_init(level: InitLevel) {
        if level == InitLevel::Scene {
            godot_print!("Godo v0.1.0 - Bevy GDExtension loaded successfully!");
        }
    }
}