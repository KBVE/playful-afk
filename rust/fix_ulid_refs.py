import re

with open('npc_data_warehouse.rs', 'r') as f:
    lines = f.readlines()

# Fix lines that have .get(&ulid_bytes) - should be .get(ulid_bytes)
for i, line in enumerate(lines):
    if '.get(&ulid_bytes)' in line:
        lines[i] = line.replace('.get(&ulid_bytes)', '.get(ulid_bytes)')
    if '.remove(&ulid_bytes)' in line:
        lines[i] = line.replace('.remove(&ulid_bytes)', '.remove(ulid_bytes)')
    if '.contains_key(&ulid_bytes)' in line:
        lines[i] = line.replace('.contains_key(&ulid_bytes)', '.contains_key(ulid_bytes)')

with open('npc_data_warehouse.rs', 'w') as f:
    f.writelines(lines)

print("Fixed &ulid_bytes references")
