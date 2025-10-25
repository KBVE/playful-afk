import re

# Read the file
with open('npc_data_warehouse.rs', 'r') as f:
    content = f.read()

# Remove SafeString::from(...) and SafeValue::from(...) wrappers
content = re.sub(r'SafeString::from\(([^)]+)\)', r'\1', content)
content = re.sub(r'SafeValue::from\(([^)]+)\)', r'\1', content)

# Remove SafeString(...) and SafeValue(...) wrappers  
content = re.sub(r'SafeString\(([^)]+)\)', r'\1', content)
content = re.sub(r'SafeValue\(([^)]+)\)', r'\1', content)

# Write back
with open('npc_data_warehouse.rs', 'w') as f:
    f.write(content)

print("Removed SafeString/SafeValue wrappers")
