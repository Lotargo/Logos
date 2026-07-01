s = open(r'F:\Кейс\AGI-lite\v9\verification_report\regression-v1\session-337116\dashboard.html').read()
idx = s.find('var raw = ')
q1 = s.index('"', idx)
end_marker = s.find('";', q1 + 1)
print(f'Opening quote at: {q1}')
print(f'Closing quote+semicolon at: {end_marker}')
raw_content = s[q1+1:end_marker]
print(f'Content length: {len(raw_content)}')
print(f'Has semicolons inside: {raw_content.count(";")}')
after = s[end_marker:end_marker+30]
print(f'After string: {repr(after)}')

# Also check what the IIFE looks like
iife_start = s.rfind('(function()', max(0, idx-200), idx)
print(f'\nIIFE starts at: {iife_start}')
iife_end = s.find('})();', end_marker)
print(f'IIFE ends at: {iife_end}')
print(f'Full IIFE length: {iife_end - iife_start}')

# Check if marked.parse call exists
has_marked = 'marked.parse(raw)' in s
has_render = 'renderMathInElement' in s
print(f'\nHas marked.parse: {has_marked}')
print(f'Has renderMathInElement: {has_render}')
