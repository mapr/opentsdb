#!/usr/bin/env bash
# Small script to setup the tables used by OpenTSDB.

MONITORING_VOLUME_NAME=${MONITORING_VOLUME_NAME:-"monitoring"}
MONITORING_TSDB_TABLE=${MONITORING_TSDB_TABLE:-"/$MONITORING_VOLUME_NAME/tsdb"}
MONITORING_UID_TABLE=${MONITORING_UID_TABLE:-"/$MONITORING_VOLUME_NAME/tsdb-uid"}
MONITORING_TREE_TABLE=${MONITORING_TREE_TABLE:-"/$MONITORING_VOLUME_NAME/tsdb-tree"}
MONITORING_META_TABLE=${MONITORING_META_TABLE:-"/$MONITORING_VOLUME_NAME/tsdb-meta"}
LOGFILE="__INSTALL__/var/log/opentsdb/opentsdb_create_table_$$.log"
# Create $MONITORING_VOLUME_NAME volume before creating tables
maprcli volume info -name $MONITORING_VOLUME_NAME > $LOGFILE 2>&1
RC=$?
if [ $RC -ne 0 ]; then
  echo "Creating volume $MONITORING_VOLUME_NAME"
  maprcli volume create -name $MONITORING_VOLUME_NAME -path /$MONITORING_VOLUME_NAME > $LOGFILE 2>&1
  RC0=$?
  if [ $RC0 -ne 0 ]; then
    echo "Create volume failed for /$MONITORING_VOLUME_NAME"
    return $RC0 2> /dev/null || exit $RC0
  fi
fi

for t in $MONITORING_TSDB_TABLE $MONITORING_UID_TABLE $MONITORING_TREE_TABLE $MONITORING_META_TABLE; do
    maprcli table info -path $t > $LOGFILE 2>&1
    RC1=$?
    if [ $RC1 -ne 0 ]; then
        echo "Creating $t table..."
        maprcli table create -path $t -defaultreadperm p -defaultwriteperm p -defaultappendperm p >> $LOGFILE 2>&1
        RC2=$?
        if [ $RC2 -ne 0 ]; then
            # check if another node beat us too it
            if ! tail -1 $LOGFILE | fgrep $t | fgrep 'File exists' > /dev/null 2>&1 ; then
                echo "Create table failed for $t"
                return $RC2 2> /dev/null || exit $RC2
            else
                continue
            fi
        fi
        COLUMN_FLAG="false"
        if [ "$t" == "$MONITORING_UID_TABLE" ]; then
            OT_COLUMNS="id name"
            COLUMN_FLAG="true"
            elif [ "$t" == "$MONITORING_META_TABLE" ]; then
            OT_COLUMNS="name"
        else
            OT_COLUMNS="t"
        fi
        for columnFamily in $OT_COLUMNS ; do
            echo "Creating CF $columnFamily for Table $t"
            maprcli table cf create -path $t -cfname $columnFamily -maxversions 1 -inmemory $COLUMN_FLAG -compression lzf -ttl 0 >> $LOGFILE 2>&1
            RC2=$?
            if [ $RC2 -ne 0 ]; then
                echo "Create CF $columnFamily failed for table $t"
                return $RC2 2> /dev/null || exit $RC2
            fi
        done
    else
        echo "$t exists."
    fi
done
echo "Complete!"

true

