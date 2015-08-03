#!/bin/sh
# important don't use sh -e for this script, need it to be resilient to failure


# nothing in the first 5 min
sleep 300

while [ true ]
do
  # on average spike every 5 min
  sleep `echo "600 * $RANDOM / 32768" | bc`
  blocking_seconds=`echo "scale=2; 10 * $RANDOM / 32768" | bc`
  echo "lock tables BLC_PRODUCT_OPTION_XREF write; select sleep($blocking_seconds)" | mysql --user=root --password=password heatclinic
done
