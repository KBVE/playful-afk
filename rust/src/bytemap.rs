use crate::holymap::HolyMap;

/// ByteMap - Specialized HolyMap for byte array keys
///
/// Uses Vec<u8> as keys for efficient ULID storage without string conversions.
/// Wraps HolyMap with a convenient API for byte-based operations.
pub struct ByteMap {
    inner: HolyMap<Vec<u8>, String>,
}

impl ByteMap {
    /// Create a new ByteMap with the specified sync interval
    pub fn new(sync_interval_ms: u64) -> Self {
        Self {
            inner: HolyMap::new(sync_interval_ms),
        }
    }

    /// Insert a value with a byte array key
    pub fn insert(&self, key: &[u8], value: String) {
        self.inner.insert(key.to_vec(), value);
    }

    /// Get a value by byte array key
    pub fn get(&self, key: &[u8]) -> Option<String> {
        self.inner.get(&key.to_vec())
    }

    /// Remove a value by byte array key
    pub fn remove(&self, key: &[u8]) -> Option<String> {
        self.inner.remove(&key.to_vec())
    }

    /// Check if a key exists
    pub fn contains_key(&self, key: &[u8]) -> bool {
        self.inner.contains_key(&key.to_vec())
    }

    /// Get the number of entries in the read store
    pub fn read_count(&self) -> usize {
        self.inner.read_count()
    }

    /// Get the number of entries in the write store
    pub fn write_count(&self) -> usize {
        self.inner.write_count()
    }

    /// Clear all entries
    pub fn clear(&self) {
        self.inner.clear();
    }
}

// Convenience methods for common patterns
impl ByteMap {
    /// Insert with a 16-byte ULID key
    pub fn insert_ulid(&self, ulid: &[u8; 16], value: String) {
        self.insert(ulid, value);
    }

    /// Get with a 16-byte ULID key
    pub fn get_ulid(&self, ulid: &[u8; 16]) -> Option<String> {
        self.get(ulid)
    }

    /// Remove with a 16-byte ULID key
    pub fn remove_ulid(&self, ulid: &[u8; 16]) -> Option<String> {
        self.remove(ulid)
    }

    /// Check if ULID exists
    pub fn contains_ulid(&self, ulid: &[u8; 16]) -> bool {
        self.contains_key(ulid)
    }
}
