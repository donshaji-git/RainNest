
with open(r'c:\Users\user\Documents\mini project\rainnest\lib\services\database_service.dart', 'r', encoding='utf-8') as f:
    depth = 0
    for i, line in enumerate(f, 1):
        for char in line:
            if char == '{':
                depth += 1
            elif char == '}':
                depth -= 1
        if depth == 0:
            print(f"Depth 0 reached at line {i}: {line.strip()}")
        if depth < 0:
             print(f"DEEP ERROR: Depth below 0 at line {i}: {line.strip()}")
             break
