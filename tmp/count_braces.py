
with open(r'c:\Users\user\Documents\mini project\rainnest\lib\services\database_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()
    opens = content.count('{')
    closes = content.count('}')
    print(f"Opens: {opens}, Closes: {closes}")
