from pathlib import Path

path = Path('apps/mobile/lib/girls_app.dart')
text = path.read_text(encoding='utf-8')
old = 'const Color _cream = Color(0xFFFFF5E1);\n'
count = text.count(old)
if count != 1:
    raise RuntimeError(
        f'Expected exactly one _cream declaration, found {count}. Refusing to modify girls_app.dart.'
    )
path.write_text(text.replace(old, '', 1), encoding='utf-8', newline='\n')
