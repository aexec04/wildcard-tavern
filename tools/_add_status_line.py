import sys
# usage: python3 tools/_add_status_line.py "<line>"  (inserts a STATUS bullet before "## Open items")
line = sys.argv[1]
p = 'claude/STATUS.md'
s = open(p).read()
i = s.index('## Open items')
s = s[:i].rstrip('\n') + '\n' + line + '\n\n' + s[i:]
open(p, 'w').write(s)
