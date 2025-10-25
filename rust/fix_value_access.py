import re

with open('npc_data_warehouse.rs', 'r') as f:
    content = f.read()

# Fix .0.parse -> .value().parse
content = re.sub(r'(\w+)\.0\.parse', r'\1.value().parse', content)

# Fix .0.clone() -> .value().clone()  
content = re.sub(r'(\w+)\.0\.clone\(\)', r'\1.value().clone()', content)

# Fix &v.0 -> v.value()
content = re.sub(r'&v\.0\b', r'v.value()', content)

with open('npc_data_warehouse.rs', 'w') as f:
    f.write(content)

print("Fixed .0 field accesses")
