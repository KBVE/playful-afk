import re

with open('npc_data_warehouse.rs', 'r') as f:
    content = f.read()

# Replace HolyMap methods with DashMap equivalents
content = re.sub(r'\.read_count\(\)', '.len()', content)
content = re.sub(r'\.write_count\(\)', '.len()', content)
content = re.sub(r'\.sync\(\)', '', content)  # Remove sync calls entirely

# Clean up empty statements like "self.storage.;"
content = re.sub(r'self\.storage\.;', '', content)
content = re.sub(r'self\.error_log\.;', '', content)

with open('npc_data_warehouse.rs', 'w') as f:
    f.write(content)

print("Fixed HolyMap methods")
