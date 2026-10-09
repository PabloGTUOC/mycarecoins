#!/bin/bash
# Watch Antigravity in an Orca terminal for one ticket. Exits (waking the lead) on:
#   DONE     a test summary after the ticket's marker, screen idle on two checks
#   LIMIT    quota / rate-limit text after the marker
#   STALLED  idle at the prompt with no summary for ~2 minutes
# Usage: watch-antigravity.sh <terminal id> <marker text, e.g. P2-8.md>
# The terminal id comes from `orca terminal list`; it changes per machine/session.
T="$1"
MARK="$2"
done_n=0; stall_n=0
while true; do
  state=$(orca terminal read --terminal "$T" --json 2>/dev/null | MARK="$MARK" python3 -c "
import json,sys,re,os
t=json.load(sys.stdin)['result']['terminal']; L=[l for l in t.get('tail',[]) if l.strip()]
s='\n'.join(L); i=s.rfind(os.environ['MARK']); after=s[i:] if i>=0 else ''
spin=any(c in '\n'.join(L[-6:]) for c in '⣾⣽⣻⢿⡿⣟⣯⣷')
tail='\n'.join(L[-8:])
if re.search(r'(?i)quota exceeded|exceeded (your|the) quota|rate limit (exceeded|reached)|RESOURCE_EXHAUSTED|usage limit (reached|exceeded)|429 Too Many Requests|out of (credits|quota)|quota reached|Resets in', tail) and not spin: print('LIMIT')
elif re.search(r'\+\d+: All t\w*s passed|Some t\w*s failed|(?i:all \d+ \w*s? ?pass)|tests? (are )?failing', after) and not spin: print('DONE')
elif L and L[-1].strip()=='>' and not spin and i>=0: print('IDLE')
else: print('BUSY')" 2>/dev/null)
  case "$state" in
    DONE) done_n=$((done_n+1)); stall_n=0; [ $done_n -ge 2 ] && { echo DONE; exit 0; } ;;
    LIMIT) echo LIMIT; exit 0 ;;
    IDLE) done_n=0; stall_n=$((stall_n+1)); [ $stall_n -ge 4 ] && { echo STALLED; exit 0; } ;;
    *) done_n=0; stall_n=0 ;;
  esac
  sleep 30
done
