import re

with open('npc_data_warehouse.rs', 'r') as f:
    content = f.read()

# Replace ByteMap methods with DashMap equivalents
# .insert_ulid(key, value) -> .insert(*key, value)
content = re.sub(r'\.insert_ulid\(([^,]+),\s*([^)]+)\)', r'.insert(*\1, \2)', content)

# .get_ulid(key) -> .get(key).map(|v| v.value().clone())
content = re.sub(r'\.get_ulid\(([^)]+)\)', r'.get(\1).map(|v| v.value().clone())', content)

# .remove_ulid(key) -> .remove(key).map(|(_, v)| v)
content = re.sub(r'\.remove_ulid\(([^)]+)\)', r'.remove(\1).map(|(_, v)| v)', content)

# .contains_ulid(key) -> .contains_key(key)
content = re.sub(r'\.contains_ulid\(([^)]+)\)', r'.contains_key(\1)', content)

with open('npc_data_warehouse.rs', 'w') as f:
    f.write(content)

print("Replaced ByteMap methods")
