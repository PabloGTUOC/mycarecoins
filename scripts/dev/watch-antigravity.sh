#!/bin/bash
# Watch Antigravity in an Orca terminal for one ticket. Exits (waking the lead) on:
#   DONE     a test summary after the ticket's marker, screen idle on two checks
#   LIMIT    quota / rate-limit text after the marker
#   STALLED  idle at the prompt with no summary for ~1 minute
#   PROMPT   waiting on a permission question it can't answer (answer it, restart the watcher)
# Read-only and test commands (SAFE below) are approved once, in place, without waking the lead.
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
tail='\n'.join(L[-40:])
m=re.search(r'Requesting permission for:\s*\n\s*(.+)', tail)
SAFE=r'^(cd fluterFront && )?(git (log|status|diff|show|grep)|find|grep|rg|ls|which|cat|head|tail|wc|sed -n|flutter (analyze|test|gen-l10n|pub get)|dart analyze|(cd backend && )?(npm (test|run test)|node --test))\b'
UNSAFE=r'[;|&]{1,2}\s*(rm|git (commit|push|checkout|reset|switch|merge|rebase)|curl|sudo)\b|>\s*[^&]'
if m and 'Run this command?' in tail and re.match(SAFE, m.group(1).strip()) and not re.search(UNSAFE, m.group(1)): print('SAFEPROMPT')
elif re.search(r'Run this command\?|Accept this file edit\?|Requesting permission for|Allow this (edit|change|action)\?|Do you want to (proceed|apply|make this edit)', '\n'.join(L[-40:])) and not spin: print('PROMPT')
elif re.search(r'(?i)quota exceeded|exceeded (your|the) quota|rate limit (exceeded|reached)|RESOURCE_EXHAUSTED|usage limit (reached|exceeded)|429 Too Many Requests|out of (credits|quota)|quota reached|Resets in', tail) and not spin: print('LIMIT')
elif re.search(r'\+\d+: All t\w*s passed|Some t\w*s failed|(?i:all \d+ \w*s? ?pass)|tests? (are )?failing', after) and not spin: print('DONE')
elif L and L[-1].strip()=='>' and not spin and i>=0: print('IDLE')
else: print('BUSY')" 2>/dev/null)
  case "$state" in
    DONE) done_n=$((done_n+1)); stall_n=0; [ $done_n -ge 2 ] && { echo DONE; exit 0; } ;;
    LIMIT) echo LIMIT; exit 0 ;;
    PROMPT) echo PROMPT; exit 0 ;;
    SAFEPROMPT) orca terminal send --terminal "$T" --text "1" >/dev/null 2>&1; sleep 3; continue ;;
    IDLE) done_n=0; stall_n=$((stall_n+1)); [ $stall_n -ge 4 ] && { echo STALLED; exit 0; } ;;
    *) done_n=0; stall_n=0 ;;
  esac
  sleep 15
done
