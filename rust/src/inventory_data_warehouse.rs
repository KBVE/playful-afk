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
    /// Fast in-memory cache for direct iteration and modification.
    inventory_cache: DashMap<[u8; 16], InventoryItem>,
    /// Reverse lookup from ULID -> slot for quick slot updates.
    ulid_to_slot: DashMap<[u8; 16], InventorySlotId>,
}

impl InventoryDataWarehouse {
    /// Create a new warehouse instance with the desired sync cadence.
    pub fn new(sync_interval_ms: u64) -> Self {
        Self {
            slot_index: HolyMap::new(sync_interval_ms),
            item_store: HolyMap::new(sync_interval_ms),
            byte_index: ByteMap::new(sync_interval_ms),
            inventory_cache: DashMap::new(),
            ulid_to_slot: DashMap::new(),
        }
    }

    /// Store/update an inventory entry (slot + ULID + payload).
    pub fn store_item(&self, slot: InventorySlotId, ulid: [u8; 16], item: InventoryItem) {
        let mut sanitized_item = item;

        if sanitized_item.amount < 0 {
            godot_error!(
                "InventoryDataWarehouse: negative amount ({}) for ULID {:?}; clamping to zero",
                sanitized_item.amount,
                ulid
            );
            sanitized_item.amount = 0;
        }

        self.slot_index.insert(slot, ulid);
        self.item_store.insert(ulid, sanitized_item.clone());
        self.inventory_cache.insert(ulid, sanitized_item.clone());

        if let Some(previous_slot) = self.ulid_to_slot.insert(ulid, slot) {
            if previous_slot != slot {
                self.slot_index.remove(&previous_slot);
            }
        }

        if let Some(serialized) = serialize_inventory_item(&sanitized_item) {
            self.byte_index.insert_ulid(&ulid, serialized);
        }
    }

    /// Fetch inventory data by ULID (returns current copy).
    pub fn get_item(&self, ulid: &[u8; 16]) -> Option<InventoryItem> {
        self.inventory_cache
            .get(ulid)
            .map(|item| item.clone())
            .or_else(|| {
                self.item_store.get(ulid).map(|item| {
                    // Back-fill cache to keep stores consistent for future reads.
                    self.inventory_cache.insert(*ulid, item.clone());
                    item
                })
            })
    }

    /// Fetch serialized JSON representation by ULID (for direct FFI transfer).
    pub fn get_item_json(&self, ulid: &[u8; 16]) -> Option<String> {
        self.byte_index.get_ulid(ulid)
    }

    /// Resolve the ULID assigned to a particular inventory slot.
    pub fn get_slot_ulid(&self, slot: InventorySlotId) -> Option<[u8; 16]> {
        self.slot_index.get(&slot)
    }

    /// Reduce quantities for all items flagged with SPOILS.
    ///
    /// `amount_or_percent` - interprets as flat amount when `percent == false`.
    /// When `percent == true`, treated as percentage (e.g. 1 == 1%).
    /// Returns the number of stacks updated.
    pub fn process_spoilage(&self, amount_or_percent: i64, percent: bool) -> usize {
        if amount_or_percent <= 0 {
            return 0;
        }

        let effective_value = if percent && amount_or_percent > 100 {
            godot_warn!(
                "InventoryDataWarehouse: spoilage percent {} > 100, clamping to 100",
                amount_or_percent
            );
            100
        } else {
            amount_or_percent
        };

        let mut updated = 0usize;

        for entry in self.inventory_cache.iter_mut() {
            let update = {
                let mut entry = entry;

                if !entry.value().state.contains(InventoryState::SPOILS) {
                    None
                } else {
                    let current_amount = entry.value().amount.max(0);
                    if current_amount == 0 {
                        None
                    } else {
                        let reduction = if percent {
                            let reduction =
                                ((current_amount as i128 * effective_value as i128) / 100) as i64;
                            reduction.max(0)
                        } else {
                            effective_value
                        };

                        if reduction <= 0 {
                            None
                        } else {
                            let new_amount = current_amount.saturating_sub(reduction);
                            if new_amount == current_amount {
                                None
                            } else {
                                entry.value_mut().amount = new_amount;
                                let ulid = *entry.key();
                                let updated_item = entry.value().clone();
                                Some((ulid, updated_item))
                            }
                        }
                    }
                }
            };

            if let Some((ulid, updated_item)) = update {
                let slot = self.ulid_to_slot.get(&ulid).map(|guard| *guard.value());
                self.item_store.insert(ulid, updated_item.clone());
                if let Some(serialized) = serialize_inventory_item(&updated_item) {
                    self.byte_index.insert_ulid(&ulid, serialized);
                }
                if let Some(slot) = slot {
                    self.slot_index.insert(slot, ulid);
                }
                updated += 1;
            }
        }

        updated
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
        let mut desired_state = match InventoryState::from_bits(state_bits) {
            Some(bits) => bits,
            None => {
                if state_bits != 0 {
                    godot_error!(
                        "InventoryDataWarehouse: state bits {:#010b} include unknown flags; truncating",
                        state_bits
                    );
                }
                let masked_bits = state_bits & InventoryState::all().bits();
                InventoryState::from_bits(masked_bits).unwrap_or(InventoryState::NONE)
            }
        };

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

    #[func]
    fn process_spoilage(&self, amount: i64, percent: bool) -> i64 {
        if amount <= 0 {
            godot_error!(
                "InventoryDataWarehouse: process_spoilage requires positive amount, received {}",
                amount
            );
            return 0;
        }
        self.warehouse.process_spoilage(amount, percent) as i64
    }
}
