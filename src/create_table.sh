#!/bin/sh
# Small script to setup the tables used by OpenTSDB.

TSDB_TABLE=${TSDB_TABLE-'/tsdb'}
UID_TABLE=${UID_TABLE-'/tsdb-uid'}
TREE_TABLE=${TREE_TABLE-'/tsdb-tree'}
META_TABLE=${META_TABLE-'/tsdb-meta'}

maprcli table info -path $TSDB_TABLE > /dev/null
RC=$?
if [ $RC -ne 0 ]; then
  echo "Creating $TSDB_TABLE table..."
  maprcli table create -path $TSDB_TABLE -defaultreadperm p -defaultwriteperm p -defaultappendperm p
  maprcli table cf create -path $TSDB_TABLE -cfname t -maxversions 1 -inmemory false -compression lzf -ttl 0
elif
  echo "$TSDB_TABLE exists."
fi

maprcli table info -path $UID_TABLE > /dev/null 
RC=$?
if [ $RC -ne 0 ]; then
  echo "Creating $UID_TABLE table..."
  maprcli table create -path $UID_TABLE -defaultreadperm p -defaultwriteperm p -defaultappendperm p
  maprcli table cf create -path $UID_TABLE -cfname id -maxversions 1 -inmemory true -compression lzf -ttl 0
  maprcli table cf create -path $UID_TABLE -cfname name -maxversions 1 -inmemory true -compression lzf -ttl 0
elif
    echo "$UID_TABLE exists."
fi

maprcli table info -path $TREE_TABLE > /dev/null
RC=$?
if [ $RC -ne 0 ]; then
  echo "Creating $TREE_TABLE table..."
  maprcli table create -path $TREE_TABLE -defaultreadperm p -defaultwriteperm p -defaultappendperm p
  maprcli table cf create -path $TREE_TABLE -cfname t -maxversions 1 -inmemory false -compression lzf -ttl 0
elif
  echo "$TREE_TABLE exists."
fi

maprcli table info -path $META_TABLE > /dev/null
RC=$?
if [ $RC -ne 0 ]; then
  echo "Creating $META_TABLE table..."
  maprcli table create -path $META_TABLE -defaultreadperm p -defaultwriteperm p -defaultappendperm p
  maprcli table cf create -path $META_TABLE -cfname name -maxversions 1 -inmemory false -compression lzf -ttl 0
elif
  echo "$META_TABLE exists."
fi

echo "Complete!"

