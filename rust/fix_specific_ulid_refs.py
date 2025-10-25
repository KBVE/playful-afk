import re

with open('npc_data_warehouse.rs', 'r') as f:
    lines = f.readlines()

# Only fix lines 2012 and 2028 specifically (change .get(&ulid_bytes) to .get(ulid_bytes))
# Line numbers are 1-indexed in compiler, 0-indexed in list
if '.get(&ulid_bytes)' in lines[2011]:  # Line 2012
    lines[2011] = lines[2011].replace('.get(&ulid_bytes)', '.get(ulid_bytes)')
    
if len(lines) > 2027 and '.get(&ulid_bytes)' in lines[2027]:  # Line 2028
    lines[2027] = lines[2027].replace('.get(&ulid_bytes)', '.get(ulid_bytes)')

with open('npc_data_warehouse.rs', 'w') as f:
    f.writelines(lines)

print("Fixed specific &ulid_bytes references on lines 2012, 2028")
