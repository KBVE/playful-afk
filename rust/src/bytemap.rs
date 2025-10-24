use dashmap::DashMap;

/// ByteMap - Specialized DashMap for byte array keys
///
/// Uses [u8; 16] as keys for efficient ULID storage.
/// Simple wrapper around DashMap for strong consistency.
pub struct ByteMap {
    inner: DashMap<[u8; 16], String>,
}

impl ByteMap {
    /// Create a new ByteMap (sync_interval_ms ignored, kept for API compatibility)
    pub fn new(_sync_interval_ms: u64) -> Self {
        Self {
            inner: DashMap::new(),
        }
    }

    /// Insert a value with a byte array key
    pub fn insert(&self, key: &[u8], value: String) {
        if key.len() == 16 {
            let mut arr = [0u8; 16];
            arr.copy_from_slice(key);
            self.inner.insert(arr, value);
        }
    }

    /// Get a value by byte array key
    pub fn get(&self, key: &[u8]) -> Option<String> {
        if key.len() == 16 {
            let mut arr = [0u8; 16];
            arr.copy_from_slice(key);
            self.inner.get(&arr).map(|entry| entry.value().clone())
        } else {
            None
        }
    }

    /// Remove a value by byte array key
    pub fn remove(&self, key: &[u8]) -> Option<String> {
        if key.len() == 16 {
            let mut arr = [0u8; 16];
            arr.copy_from_slice(key);
            self.inner.remove(&arr).map(|(_, v)| v)
        } else {
            None
        }
    }

    /// Check if a key exists
    pub fn contains_key(&self, key: &[u8]) -> bool {
        if key.len() == 16 {
            let mut arr = [0u8; 16];
            arr.copy_from_slice(key);
            self.inner.contains_key(&arr)
        } else {
            false
        }
    }

    /// Get the number of entries
    pub fn read_count(&self) -> usize {
        self.inner.len()
    }

    /// Get the number of entries (same as read_count for DashMap)
    pub fn write_count(&self) -> usize {
        self.inner.len()
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
        self.inner.insert(*ulid, value);
    }

    /// Get with a 16-byte ULID key
    pub fn get_ulid(&self, ulid: &[u8; 16]) -> Option<String> {
        self.inner.get(ulid).map(|entry| entry.value().clone())
    }

    /// Remove with a 16-byte ULID key
    pub fn remove_ulid(&self, ulid: &[u8; 16]) -> Option<String> {
        self.inner.remove(ulid).map(|(_, v)| v)
    }

    /// Check if ULID exists
    pub fn contains_ulid(&self, ulid: &[u8; 16]) -> bool {
        self.inner.contains_key(ulid)
    }
}
