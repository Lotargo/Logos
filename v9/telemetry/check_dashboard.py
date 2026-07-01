import json

with open(r'F:\Кейс\AGI-lite\v9\verification_report\regression-v1\session-337116\judge_report.md') as f:
    md = f.read()

dumped = json.dumps(md)
print(f"Markdown length: {len(md)} chars")
print(f"json.dumps length: {len(dumped)} chars")

# Check if the HTML file has valid JS
with open(r'F:\Кейс\AGI-lite\v9\verification_report\regression-v1\session-337116\dashboard.html') as f:
    html = f.read()

# Find the script block
import re
scripts = re.findall(r'<script>(.*?)</script>', html, re.DOTALL)
print(f"\nFound {len(scripts)} inline scripts")
for i, s in enumerate(scripts):
    print(f"  Script {i}: {len(s)} chars")
    # Check for common JS issues
    if 'var raw =' in s:
        # Extract the raw string value
        raw_match = re.search(r"var raw = (.*?);", s, re.DOTALL)
        if raw_match:
            raw_val = raw_match.group(1)
            print(f"  raw value length: {len(raw_val)} chars")
            print(f"  raw starts with: {raw_val[:50]}")
            print(f"  raw ends with: {raw_val[-50:]}")
            # Check if it starts/ends with quotes
            print(f"  starts with quote: {raw_val.startswith('\"')}")
            print(f"  ends with quote: {raw_val.endswith('\"')}")
