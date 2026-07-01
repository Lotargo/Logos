import re

with open(r'F:\Кейс\AGI-lite\v9\verification_report\regression-v1\session-337116\dashboard.html', 'r') as f:
    html = f.read()

# Find var raw = "..." 
# Search for the pattern
idx = html.find('var raw = ')
if idx == -1:
    print("NOT FOUND")
else:
    # Skip to the opening quote
    quote_start = html.index('"', idx)
    pos = quote_start + 1
    while pos < len(html):
        ch = html[pos]
        if ch == '\\' and pos + 1 < len(html):
            pos += 2  # skip escaped char
        elif ch == '"':
            break
        else:
            pos += 1
    
    raw_string = html[quote_start:pos+1]
    print(f"Raw string length: {len(raw_string)}")
    print(f"First 80: {raw_string[:80]}")
    print(f"Last 80: {raw_string[-80:]}")
    print(f"Ends with quote+semicolon: {html[pos:pos+3]}")
    
    # Now check what comes after
    print(f"\nAfter the string: {html[pos:pos+20]}")
    
    # Check the actual file size
    print(f"\nTotal HTML size: {len(html)}")
    print(f"Line count: {html.count(chr(10))}")
