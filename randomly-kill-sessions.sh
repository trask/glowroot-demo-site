#!/bin/sh
# important don't use sh -e for this script, need it to be resilient to failure


# first kill sessions after 10 minutes so there will always be an error in default errors view (which covers past 2 hours)
# (even if the restarted toward end of 1.75 hour draught)
sleep 600

while [ true ]
do
  mysql --user=root --password=password -e 'show processlist' | grep heatclinic | awk {'print "kill "$1";"'} | mysql --user=root --password=password
  # at most 1.75 hours apart so there will always be an error in default errors view (which covers past 2 hours)
  sleep `echo "1.75 * 3600 * $RANDOM / 32768" | bc`
done
