#!/bin/bash
CEPH=/usr/bin/ceph
AWK=/usr/bin/awk
SORT=/bin/sort
HEAD=/usr/bin/head
DATE=/bin/date
SED=/bin/sed
GREP=/bin/grep
PYTHON=/usr/bin/python

#What string does match a deep scrubing state in ceph pg's output?
DEEPMARK="scrubbing+deep"
#Max concurrent deep scrubs operations
MAXSCRUBS=1

startdate=$($DATE +%s)
cat << __EOM__

***************************
* CEPH DEEP-SCRUB CRONJOB *
***************************

Started working:
    $($DATE -R)
    TS: $startdate

__EOM__

#Set work ratio from first arg; fall back to '8'.
workratio=$1
[ "x$workratio" == x ] && workratio=8

function isNewerThan() {
    # Args: [PG] [TIMESTAMP]
    # Output: None
    # Returns: 0 if changed; 1 otherwise
    # Desc: Check if a placement group "PG" deep scrub stamp has changed
    # (i.e != "TIMESTAMP")
    pg=$1
    ots=$2
    ndate=$($CEPH pg $pg query -f json-pretty | \
        $PYTHON -c 'import json;import sys; print json.loads(sys.stdin.read())["info"]["stats"]["last_deep_scrub_stamp"]')
    nts=$($DATE -d "$ndate" +%s)
    [ $ots -ne $nts ] && return 0
    return 1
}

function scrubbingCount() {
    # Args: None
    # Output: int
    # Returns: 0
    # Desc: Outputs concurent deep scrubbing tasks.
    cnt=$($CEPH -s | $GREP $DEEPMARK | $AWK '{ print $1; }')
    [ "x$cnt" == x ] && cnt=0
    echo $cnt
    return 0
}

function waitForScrubSlot() {
    # Args: None
    # Output: Informative text
    # Returns: true
    # Desc: Idle loop waiting for a free deepscrub slot.
    scount=$(scrubbingCount)
    if [ $scount -ge $MAXSCRUBS ]; then
        echo -n "Waiting for a scrub slot to free up... "
    fi
    while [ $(scrubbingCount) -ge $MAXSCRUBS ]; do
        sleep 1
    done
    echo 'OK'
    return 0
}

function deepScrubPg() {
    # Args: [PG]
    # Output: Informative text
    # Return: 0 when PG is effectively deep scrubing
    # Desc: Start a PG "PG" deep-scrub
    echo Scrubbing $1
    $CEPH pg deep-scrub $1
    #Must sleep as ceph does not immediately start scrubbing
    #So we wait until wanted PG effectively goes into deep scrubbing state...
    echo -n 'Waiting for PG to get into scrub mode... '
    while ! $CEPH pg $1 query | $GREP state | $GREP -q $DEEPMARK; do
        isNewerThan $1 $2 && echo -n "[PG scrub stamp got updated] " && break
        sleep 2
    done
    echo 'OK'
    echo
    return 0
}

function getOldestScrubs() {
    # Args: [num_res]
    # Output: [num_res] PG ids
    # Return: 0
    # Desc: Get the "num_res" oldest deep-scrubbed PGs
    numres=$1
    [ x$numres == x ] && numres=20
    $CEPH pg dump 2>/dev/null | \
        $AWK -F" " '{ if($10 == "active+clean") {  print $1,$23,$24 ; }; }' | \
        while read line; do set $line; echo $1 $($DATE -d "$2 $3" +%s); done | \
        $SORT -n -k2  | \
        $HEAD -n $numres
    return 0
}

function getPgCount() {
    # Args:
    # Output: number of total PGs
    # Desc: Output the total number of "active+clean" PGs
    $CEPH pg stat | $SED 's/^.* \([0-9]\+\) active+clean[^+].*/\1/g'
}

#Get PG count
pgcnt=$(getPgCount)
#Get the number of PGs we'll be working on
pgwork=$((pgcnt / workratio + 1))
count=1

#Actual work starts here, quite self-explanatory.
echo "About to scrub 1/${workratio} of $pgcnt PGs = $pgwork PGs to scrub"
getOldestScrubs $pgwork | while read line; do
    now=$($DATE +%s)
    set $line
    age=$(expr $now - $2)
    days=$((age / 3600 / 24))
    echo "The $count PG $1 is $days days - $age seconds old"
    count=$[$count+1]
    sleep 1
    waitForScrubSlot
    deepScrubPg $1 $2
done

echo "Finished batch"
enddate=$($DATE +%s)
echo "***EndOfRun $($DATE -R) // took $((enddate - startdate)) seconds"
