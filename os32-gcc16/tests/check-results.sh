#!/bin/sh
# check-results.sh [RESULTS]: judge the results an instance wrote (default results/).
# t1-t6, t10-t20: the program's own PASS/FAIL lines and return code (0 = right).
# t7-t9: the output must equal expected/ (made on a PC), line for line.
cd "$(dirname "$0")"; R=${1:-results}; fails=0
for f in $(cd "$R" && ls *.txt | grep -v summary); do
    t=${f%.txt}; base=${t%-*}
    case $base in
        t7|t8|t9) exp=expected/$(ls expected | grep "^${base}_"); if diff -q "$exp" "$R/$f" >/dev/null 2>&1; then echo "PASS $t (same as the PC)"; else echo "FAIL $t (differs from the PC):"; diff "$exp" "$R/$f" | head -6; fails=$((fails+1)); fi ;;
        *) rc=$(grep "^$t rc=" "$R/summary.txt" | sed 's/.*rc=//'); if [ "$rc" = 0 ]; then echo "PASS $t"; else echo "FAIL $t (rc=$rc)"; grep FAIL "$R/$f"; fails=$((fails+1)); fi ;;
    esac
done
echo "$fails failing"; [ $fails = 0 ]
