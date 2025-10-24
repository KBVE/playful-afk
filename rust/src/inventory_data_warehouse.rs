use crate::holymap::HolyMap;
use crate::bytemap::ByteMap;
use bitflags::bitflags;
use serde::{Deserialize, Serialize};
use ulid::Ulid;
use once_cell::sync::Lazy;
use dashmap::DashMap;
use std::sync::Arc;
use godot::classes::PackedByteArray;
use godot::prelude::*;

// ============================================================================
// Inventory flags and core data structures
// ============================================================================

bitflags! {
    /// Bitwise inventory state flags for rapid masking/matching across FFI.
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
    pub struct InventoryState: u32 {
        const NONE    = 0;
        const UNIQUE  = 1 << 0;
        const PASSIVE = 1 << 1;
        const SPOILS  = 1 << 2;
    }
}

/// Primary inventory payload stored in the warehouse.
#[derive(Clone, Debug)]
pub struct InventoryItem {
    /// Display name for the inventory item (mirrored in Godot).
    pub name: String,
    /// Amount/stack count (Godot treats this as 64-bit integer internally).
    pub amount: i64,
    /// Bitflags describing the item's semantic state.
    pub state: InventoryState,
}

impl InventoryItem {
    pub fn new<S: Into<String>>(name: S, amount: i64, state: InventoryState) -> Self {
        Self {
            name: name.into(),
            amount,
            state,
        }
    }
}

/// Canonical catalog entries shared between Godot and Rust.
const INVENTORY_ITEM_DEFINITIONS: &[(&str, &str, InventoryState)] = &[
    ("food", "01K8AF0059YG1T5NTJPFYJK03F", InventoryState::SPOILS),
    ("potion_basic", "01K8AF0182RWXTW3246E87KX0E", InventoryState::PASSIVE),
    ("quest_relic", "01K8AF01X5W5VY5ZCGRQZNQE9V", InventoryState::UNIQUE),
];

/// Build-time utility to convert ULID string literals into byte arrays.
fn ulid_bytes_from_str(ulid_str: &str) -> [u8; 16] {
    Ulid::from_string(ulid_str)
        .unwrap_or_else(|err| panic!("Invalid ULID literal '{}': {}", ulid_str, err))
        .to_bytes()
}

/// Fast lookup: item kind (string) -> ULID bytes.
pub static INVENTORY_KIND_TO_ULID: Lazy<DashMap<&'static str, [u8; 16]>> = Lazy::new(|| {
    let map = DashMap::with_capacity(INVENTORY_ITEM_DEFINITIONS.len());
    for (name, ulid_str, _) in INVENTORY_ITEM_DEFINITIONS {
        map.insert(*name, ulid_bytes_from_str(ulid_str));
    }
    map
});

/// Reverse lookup: ULID bytes -> canonical inventory template.
pub static INVENTORY_ULID_TO_ITEM: Lazy<DashMap<[u8; 16], InventoryItem>> = Lazy::new(|| {
    let map = DashMap::with_capacity(INVENTORY_ITEM_DEFINITIONS.len());
    for (name, ulid_str, state) in INVENTORY_ITEM_DEFINITIONS {
        let ulid_bytes = ulid_bytes_from_str(ulid_str);
        map.insert(
            ulid_bytes,
            InventoryItem::new(*name, 0, *state),
        );
    }
    map
});

/// Convenience to fetch ULID bytes for a given item kind.
pub fn lookup_ulid_for_kind(kind: &str) -> Option<[u8; 16]> {
    INVENTORY_KIND_TO_ULID
        .get(kind)
        .map(|entry| *entry.value())
}

/// Convenience to fetch the template item for a ULID key.
pub fn lookup_item_for_ulid(ulid: &[u8; 16]) -> Option<InventoryItem> {
    INVENTORY_ULID_TO_ITEM
        .get(ulid)
        .map(|entry| entry.value().clone())
}

/// Inventory slot identifier used by Godot (array index, bag position, etc.).
pub type InventorySlotId = u16;

/// JSON-friendly representation used when moving data over the FFI boundary.
#[derive(Clone, Debug, Serialize, Deserialize)]
struct InventoryItemWire {
    name: String,
    amount: i64,
    state: u32,
}

impl From<&InventoryItem> for InventoryItemWire {
    fn from(item: &InventoryItem) -> Self {
        Self {
            name: item.name.clone(),
            amount: item.amount,
            state: item.state.bits(),
        }
    }
}

impl From<InventoryItemWire> for InventoryItem {
    fn from(wire: InventoryItemWire) -> Self {
        Self {
            name: wire.name,
            amount: wire.amount,
            state: InventoryState::from_bits_retain(wire.state),
        }
    }
}

/// Serialize an inventory item into JSON string payload.
fn serialize_inventory_item(item: &InventoryItem) -> Option<String> {
    let wire: InventoryItemWire = item.into();
    match serde_json::to_string(&wire) {
        Ok(json) => Some(json),
        Err(err) => {
            godot_error!(
                "InventoryDataWarehouse: failed to serialize item '{}' -> {:?}",
                item.name,
                err
            );
            None
        }
    }
}

/// Godot-facing helper for serializing an inventory item into JSON.
pub fn inventory_item_to_json(item: &InventoryItem) -> GString {
    serialize_inventory_item(item)
        .map(GString::from)
        .unwrap_or_else(GString::new)
}

/// Convert PackedByteArray ULID representation (16 bytes) into a fixed array.
fn packed_bytes_to_ulid(bytes: &PackedByteArray) -> Option<[u8; 16]> {
    if bytes.len() != 16 {
        godot_error!(
            "InventoryDataWarehouse: expected 16-byte ULID, received length {}",
            bytes.len()
        );
        return None;
    }

    let vec = bytes.to_vec();
    let mut ulid = [0u8; 16];
    ulid.copy_from_slice(&vec);
    Some(ulid)
}

/// Convert ULID bytes into PackedByteArray for Godot interop.
fn ulid_to_packed_bytes(ulid: &[u8; 16]) -> PackedByteArray {
    PackedByteArray::from(&ulid[..])
}

/// Centralized data warehouse orchestrating inventory storage.
pub struct InventoryDataWarehouse {
    /// Maps numeric slots -> canonical ULID entries.
    slot_index: HolyMap<InventorySlotId, [u8; 16]>,
    /// Primary inventory store keyed by ULID.
    item_store: HolyMap<[u8; 16], InventoryItem>,
    /// Byte-based mirror for fast Godot lookups / serialization cache.
    byte_index: ByteMap,
}

impl InventoryDataWarehouse {
    /// Create a new warehouse instance with the desired sync cadence.
    pub fn new(sync_interval_ms: u64) -> Self {
        Self {
            slot_index: HolyMap::new(sync_interval_ms),
            item_store: HolyMap::new(sync_interval_ms),
            byte_index: ByteMap::new(sync_interval_ms),
        }
    }

    /// Store/update an inventory entry (slot + ULID + payload).
    pub fn store_item(&self, slot: InventorySlotId, ulid: [u8; 16], item: InventoryItem) {
        self.slot_index.insert(slot, ulid);
        self.item_store.insert(ulid, item.clone());

        if let Some(serialized) = serialize_inventory_item(&item) {
            self.byte_index.insert_ulid(&ulid, serialized);
        }
    }

    /// Fetch inventory data by ULID (returns current copy).
    pub fn get_item(&self, ulid: &[u8; 16]) -> Option<InventoryItem> {
        self.item_store.get(ulid)
    }

    /// Fetch serialized JSON representation by ULID (for direct FFI transfer).
    pub fn get_item_json(&self, ulid: &[u8; 16]) -> Option<String> {
        self.byte_index.get_ulid(ulid)
    }

    /// Resolve the ULID assigned to a particular inventory slot.
    pub fn get_slot_ulid(&self, slot: InventorySlotId) -> Option<[u8; 16]> {
        self.slot_index.get(&slot)
    }
}

// ============================================================================
// Godot FFI wrapper
// ============================================================================

#[derive(GodotClass)]
#[class(base=Node)]
pub struct GodotInventoryDataWarehouse {
    warehouse: Arc<InventoryDataWarehouse>,
    base: Base<Node>,
}

#[godot_api]
impl INode for GodotInventoryDataWarehouse {
    fn init(base: Base<Node>) -> Self {
        godot_print!("=== InventoryDataWarehouse Initializing ===");
        Self {
            warehouse: Arc::new(InventoryDataWarehouse::new(1000)),
            base,
        }
    }
}

#[godot_api]
impl GodotInventoryDataWarehouse {
    #[func]
    fn upsert_item(&self, slot: u16, item_kind: GString, amount: i64, state_bits: u32) -> bool {
        let kind = item_kind.to_string();

        let ulid = match lookup_ulid_for_kind(&kind) {
            Some(ulid) => ulid,
            None => {
                godot_error!(
                    "InventoryDataWarehouse: unknown item kind '{}', unable to upsert",
                    kind
                );
                return false;
            }
        };

        let existing = self.warehouse.get_item(&ulid);

        let mut item = existing
            .clone()
            .or_else(|| lookup_item_for_ulid(&ulid))
            .unwrap_or_else(|| InventoryItem::new(kind.clone(), 0, InventoryState::NONE));

        item.name = kind;
        let mut desired_state = InventoryState::from_bits_retain(state_bits);
        if desired_state == InventoryState::NONE {
            desired_state = item.state;
        }
        let is_unique = desired_state.contains(InventoryState::UNIQUE);

        if is_unique {
            if let Some(existing_item) = existing {
                if existing_item.amount > 0 {
                    godot_error!(
                        "InventoryDataWarehouse: '{}' is UNIQUE and already present; ignoring duplicate insert",
                        item.name
                    );
                    return false;
                }
            }
            item.amount = 1;
        } else {
            item.amount = amount.max(0);
        }

        item.state = desired_state;

        self.warehouse.store_item(slot, ulid, item);
        true
    }

    #[func]
    fn get_item_json(&self, ulid_bytes: PackedByteArray) -> GString {
        let Some(ulid) = packed_bytes_to_ulid(&ulid_bytes) else {
            return GString::new();
        };

        self.warehouse
            .get_item_json(&ulid)
            .map(GString::from)
            .unwrap_or_else(|| {
                godot_error!(
                    "InventoryDataWarehouse: item not found for ULID {:?}",
                    ulid
                );
                GString::new()
            })
    }

    #[func]
    fn get_slot_item_json(&self, slot: u16) -> GString {
        match self.warehouse.get_slot_ulid(slot) {
            Some(ulid) => self
                .warehouse
                .get_item_json(&ulid)
                .map(GString::from)
                .unwrap_or_else(|| {
                    godot_error!(
                        "InventoryDataWarehouse: JSON missing for slot {} (ULID {:?})",
                        slot,
                        ulid
                    );
                    GString::new()
                }),
            None => {
                godot_error!(
                    "InventoryDataWarehouse: slot {} has no assigned ULID",
                    slot
                );
                GString::new()
            }
        }
    }

    #[func]
    fn get_slot_ulid_bytes(&self, slot: u16) -> PackedByteArray {
        self.warehouse
            .get_slot_ulid(slot)
            .map(|ulid| ulid_to_packed_bytes(&ulid))
            .unwrap_or_else(|| {
                godot_error!(
                    "InventoryDataWarehouse: slot {} has no assigned ULID",
                    slot
                );
                PackedByteArray::new()
            })
    }

    #[func]
    fn get_ulid_for_kind(&self, item_kind: GString) -> PackedByteArray {
        let kind = item_kind.to_string();
        lookup_ulid_for_kind(&kind)
            .map(|ulid| ulid_to_packed_bytes(&ulid))
            .unwrap_or_else(|| {
                godot_error!(
                    "InventoryDataWarehouse: unknown item kind '{}'",
                    kind
                );
                PackedByteArray::new()
            })
    }
}
