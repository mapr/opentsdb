#!/bin/sh
# Small script to setup the tables used by OpenTSDB.

TSDB_TABLE=${TSDB_TABLE:-'/tsdb'}
UID_TABLE=${UID_TABLE:-'/tsdb-uid'}
TREE_TABLE=${TREE_TABLE:-'/tsdb-tree'}
META_TABLE=${META_TABLE:-'/tsdb-meta'}
LOGFILE=${OT_HOME}/var/log/opentsdb/opentsdb_create_table_$$.log

for t in $TSDB_TABLE $UID_TABLE $TREE_TABLE $META_TABLE; do
   maprcli table info -path $t> $LOGFILE 2>&1
   RC1=$?
   if [ $RC1 -ne 0 ]; then
     echo "Creating $t table..."
     maprcli table create -path $t -defaultreadperm p -defaultwriteperm p -defaultappendperm p > $LOGFILE 2>&1
     RC2=$?
     if [ $RC2 -ne 0]; then
       echo "Create table failed for $t"
       return $RC2 2>/dev/null || exit $RC2
     fi
     if [ "$t" == "$UID_TABLE" ]; then
       for columnFamily in "id" "name"; do
         echo "Creating CF $columnFamily for Table $t"
         maprcli table cf create -path $t -cfname $columnFamily -maxversions 1 -inmemory true -compression lzf -ttl 0 > $LOGFILE 2>&1
         RC2=$?
         if [ $RC2 -ne 0]; then
           echo "Create CF $columnFamily failed for table $t"
           return $RC2 2>/dev/null || exit $RC2
         fi
       done
     elif
       if [ "$t" == "$META_TABLE" ]; then
         columnFamily="name"
       elif
         columnFamily="t"
       fi
       echo "Creating CF $columnFamily for Table $t"
       maprcli table cf create -path $t -cfname $columnFamily -maxversions 1 -inmemory false -compression lzf -ttl 0 > $LOGFILE 2>&1
       RC2=$?
       if [ $RC2 -ne 0]; then
         echo "Create CF $columnFamily failed for table $t"
         return $RC2 2>/dev/null || exit $RC2
       fi
    fi
  else
    echo "$t exists."
  fi
done
echo "Complete!"

true

