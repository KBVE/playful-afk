use crate::holymap::HolyMap;
use godot::prelude::*;
use godot::builtin::VariantType;
use once_cell::sync::Lazy;
use dashmap::DashMap;

// ============================================================================
// Tile metadata
// ============================================================================

/// Axial coordinates for hex-based tile systems (pointy-top or flat-top).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct HexCoord {
    pub q: i32,
    pub r: i32,
}

impl HexCoord {
    pub const fn new(q: i32, r: i32) -> Self {
        Self { q, r }
    }

    /// Convert to cube coordinates (with s = -q - r) for internal math.
    pub fn to_cube(self) -> (i32, i32, i32) {
        let s = -self.q - self.r;
        (self.q, self.r, s)
    }
}

/// Tile presentation data shared across layers.
#[derive(Clone, Debug)]
pub struct TileDefinition {
    /// Identifier exposed to Godot (e.g. "grass_plains").
    pub name: String,
    /// PackedScene path for instancing the tile (hex mesh / sprite).
    pub scene: GString,
    /// Optional metadata encoded as JSON string (biome tags, height, etc.).
    pub metadata_json: Option<String>,
}

impl TileDefinition {
    pub fn new<T: Into<String>, S: Into<GString>>(
        name: T,
        scene: S,
        metadata_json: Option<String>,
    ) -> Self {
        Self {
            name: name.into(),
            scene: scene.into(),
            metadata_json,
        }
    }
}

/// Runtime reference to a specific tile instance on the map.
#[derive(Clone, Debug)]
pub struct TileInstance {
    pub coord: HexCoord,
    pub definition: TileDefinition,
    /// Unique key for Godot to track instanced nodes for re-parenting/despawning.
    pub ulid_bytes: [u8; 16],
}

// ============================================================================
// Layer registry
// ============================================================================

/// Simplified layer identifier (terrain, decor, etc.).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct MapLayerId(String);

impl MapLayerId {
    pub fn new<T: Into<String>>(id: T) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Global registry describing which PackedScenes represent each tile type.
pub static TILE_DEFINITIONS: Lazy<DashMap<String, TileDefinition>> = Lazy::new(|| DashMap::new());

/// Each layer maintains a HolyMap giving fast spatial lookups by axial coordinate.
pub struct MapLayer {
    pub id: MapLayerId,
    tiles: HolyMap<HexCoord, TileInstance>,
}

impl MapLayer {
    pub fn new(id: MapLayerId, sync_interval_ms: u64) -> Self {
        Self {
            id,
            tiles: HolyMap::new(sync_interval_ms),
        }
    }

    pub fn get_tile(&self, coord: HexCoord) -> Option<TileInstance> {
        self.tiles.get(&coord)
    }

    pub fn insert_tile(&self, coord: HexCoord, tile: TileInstance) -> Option<TileInstance> {
        self.tiles.insert(coord, tile)
    }

    pub fn remove_tile(&self, coord: HexCoord) -> Option<TileInstance> {
        self.tiles.remove(&coord)
    }
}

// ============================================================================
// Warehouse entry point
// ============================================================================

pub struct MapDataWarehouse {
    /// Registered map layers keyed by layer identifier.
    layers: DashMap<MapLayerId, MapLayer>,
}

impl MapDataWarehouse {
    pub fn new() -> Self {
        Self {
            layers: DashMap::new(),
        }
    }

    /// Register or replace a tile definition available for instancing.
    pub fn register_tile_definition(&self, definition: TileDefinition) {
        TILE_DEFINITIONS.insert(definition.name.clone(), definition);
    }

    /// Fetch a tile definition by name.
    pub fn get_tile_definition(&self, name: &str) -> Option<TileDefinition> {
        TILE_DEFINITIONS.get(name).map(|entry| entry.value().clone())
    }

    /// Ensure a layer exists with the provided identifier.
    pub fn ensure_layer(&self, id: MapLayerId, sync_interval_ms: u64) -> MapLayerId {
        if !self.layers.contains_key(&id) {
            self.layers.insert(id.clone(), MapLayer::new(id.clone(), sync_interval_ms));
        }
        id
    }

    /// Internal helper to check if a layer exists.
    pub fn has_layer(&self, id: &MapLayerId) -> bool {
        self.layers.contains_key(id)
    }
}

// ============================================================================
// Godot bindings
// ============================================================================

#[derive(GodotClass)]
#[class(base=Node)]
pub struct GodotMapDataWarehouse {
    warehouse: MapDataWarehouse,
    base: Base<Node>,
}

#[godot_api]
impl INode for GodotMapDataWarehouse {
    fn init(base: Base<Node>) -> Self {
        godot_print!("=== MapDataWarehouse Initializing ===");
        Self {
            warehouse: MapDataWarehouse::new(),
            base,
        }
    }
}

#[godot_api]
impl GodotMapDataWarehouse {
    /// Placeholder API: Godot will register tile definitions via scene name + metadata.
    #[func]
    fn register_tile(
        &self,
        name: GString,
        scene_path: GString,
        metadata_json: Variant,
    ) {
        let metadata = if metadata_json.get_type() == VariantType::NIL {
            None
        } else {
            Some(format!("{:?}", metadata_json))
        };

        let definition = TileDefinition::new(name.to_string(), scene_path, metadata);
        self.warehouse.register_tile_definition(definition);
    }
}
