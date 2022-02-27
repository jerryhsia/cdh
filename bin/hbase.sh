#!/bin/bash

# Copyright (c) 2011-2014 Cloudera, Inc. All rights reserved.

# Time marker for both stderr and stdout
date; date 1>&2

echo "Running on: $(hostname -f) ($(hostname -i))" 1>&2

cloudera_config=`dirname $0`
cloudera_config=`cd "$cloudera_config/../common"; pwd`
. ${cloudera_config}/cloudera-config.sh

# Load the parcel environment
source_parcel_environment

# attempt to find java
locate_cdh_java_home

echo "using $JAVA_HOME as JAVA_HOME"
echo "using $CDH_VERSION as CDH_VERSION"
echo "using $HBASE_HOME as HBASE_HOME"
echo "using $CONF_DIR as HBASE_CONF_DIR"
echo "using $CONF_DIR as HADOOP_CONF_DIR"
echo "using $HADOOP_HOME as HADOOP_HOME"

set_hbase_classpath
echo $CDH_HADOOP_HOME
export HADOOP_HOME=$CDH_HADOOP_HOME
export HBASE_HOME=$CDH_HBASE_HOME
export HBASE_MASTER_OPTS=$(replace_pid $HBASE_MASTER_OPTS)
export HBASE_REGIONSERVER_OPTS=$(replace_pid $HBASE_REGIONSERVER_OPTS)
export HBASE_REST_OPTS=$(replace_pid $HBASE_REST_OPTS)
export HBASE_THRIFT_OPTS=$(replace_pid $HBASE_THRIFT_OPTS)
export HBASE_MASTER_OPTS=$(replace_pid $HBASE_MASTER_OPTS)

# debug
set -x

# we set HADOOP_CONF_DIR explicitly to our CONF_DIR since otherwise the hbase
# script will use the default system hadoop configuration.
export HADOOP_CONF_DIR=$CONF_DIR

# OPSAPS-16739 - these 2 env vars are needed for HBase to pick its conf correctly
export HBASE_CONF_DIR=$CONF_DIR
export HADOOP_CONF=$CONF_DIR

# Search-replace {{CMF_CONF_DIR}} in files
replace_conf_dir

acquire_kerberos_tgt hbase.keytab

# Disable IPv6.
export HBASE_OPTS="-Djava.net.preferIPv4Stack=true $HBASE_OPTS"

locate_hbase_script

function canary_echo() {
  echo "`date` RS pid:$$ " "$@"
}

function hbase_canary() {
  canary_echo "Sleeping before starting the canary"
  sleep 30
  if [ "$JAAS_FILE" != "" ]; then
    export HBASE_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_OPTS"
  fi
  export HBASE_LOGFILE=$CANARY_LOG_FILE
  while true;
  do
    canary_echo "Starting the canary"
    $HBASE_BIN --config $CONF_DIR org.apache.hadoop.hbase.tool.Canary -t $CANARY_TIMEOUT -daemon \
      -interval $CANARY_INTERVAL -regionserver ${RS_HOST}
    CANARY_EXIT=$?

    if [ $CANARY_EXIT -gt 2 ]; then
      canary_echo "Canary exited with error code $CANARY_EXIT"
      # Kill the process if user specified so
      if [ "$KILL_ON_CANARY_ERROR" = "true" ]; then
        # Sleep for a little bit just in case this is just the RS going down gracefully
        sleep 5
        # Try to terminate the process
        if kill -0 $$; then
          canary_echo "Stopping RegionServer gracefully"
          kill -15 $$
          sleep 10
        fi
        if kill -0 $$; then
          canary_echo "Killing the RegionServer process"
          kill -9 $$
        fi
        exit 1
      fi
    fi

    # Finally check that the monitored process is still running (a bit of belt'n'suspenders)
    if ! kill -0 $$ ; then
      canary_echo "Looks like the RegionServer exited. Canary runner thread is now exiting..."
      exit 0
    fi
  done
}

function znode_cleanup() {
  echo "`date` Starting znode cleanup thread with HBASE_ZNODE_FILE=$HBASE_ZNODE_FILE for $1"
  HBASE_OPTS=$(replace_pid $HBASE_OPTS)
  if [ "$JAAS_FILE" != "" ]; then
    export HBASE_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_OPTS"
  fi
  LOG_FILE=$CONF_DIR/logs/znode_cleanup.log

  # Check if parent PID is not running anymore
  set +x # Turn off debugging to avoid lots of logs in stderr
  while kill -0 $$; do sleep 1; done
  set -x

  # If znode file still exists then parent didn't exit gracefully
  RET=0
  if [ -f $HBASE_ZNODE_FILE ]; then
    echo "`date` Znode file exists. Will clean up the znode" >> $LOG_FILE
    if [ "$1" = "master" ]; then
      $HBASE_BIN --config $CONF_DIR master clear >> $LOG_FILE 2>&1
      RET=$?
    else
      #call ZK to delete the node
      ZNODE=`cat $HBASE_ZNODE_FILE`
      $HBASE_BIN --config $CONF_DIR zkcli delete $ZNODE >> $LOG_FILE 2>&1
      RET=$?
    fi
    if [ $RET -ne 0 ]; then
      echo "`date` Failed to clear znode" >> $LOG_FILE
    fi
    rm $HBASE_ZNODE_FILE
    exit $RET
  fi
  echo "`date` Znode file does not exist. No cleanup required." >> $LOG_FILE
  exit 0
}

if [ "upgrade" = "$1" ]; then
  # simulate /etc/default/hadoop if necessary
  . ${cloudera_config}/cdh-default-hadoop
  HDFS_BIN=$HADOOP_HDFS_HOME/bin/hdfs
  $HDFS_BIN --config $CONF_DIR dfs -test -d $HBASE_ROOTDIR/.cdh4-snapshot
  if [ $? -eq 0 ]; then
    echo "Renaming snapshot directory to .hbase-snapshot"
    $HDFS_BIN --config $CONF_DIR dfs -mv $HBASE_ROOTDIR/.cdh4-snapshot $HBASE_ROOTDIR/.hbase-snapshot
    if [ $? -ne 0 ]; then
      echo "Failed to rename snapshot directory"
      exit 1
    fi
  fi
fi

if [ "region_mover" = "$1" ]; then
  REGION_MOVER_SCRIPT="${cloudera_config}/../hbase/region_mover.cdh$CDH_VERSION.rb"
  echo "Using $REGION_MOVER_SCRIPT as REGION_MOVER_SCRIPT"
  if [ ! -e $REGION_MOVER_SCRIPT ]; then
    echo "Error: $REGION_MOVER_SCRIPT not found"
    exit 1
  fi
  EXTRA_ARGS=""
  if [ "unload" = "$2" ]; then
    EXTRA_ARGS="-x $CONF_DIR/excludes.txt"
  elif [ "load" != "$2" ]; then
    echo "Error: Unknown argument $2. Must be either load or unload"
    exit 1
  fi
  if [ -n "$REGION_MOVER_MAX_THREADS" ]; then
    EXTRA_ARGS="$EXTRA_ARGS -m $REGION_MOVER_MAX_THREADS"
  fi

  # $2 = 'load' for reload and 'unload' for decommission
  # $3 is hostname to reload/decommission.
  exec $HBASE_BIN --config $CONF_DIR org.jruby.Main $REGION_MOVER_SCRIPT $EXTRA_ARGS $2 $3
elif [ "toggle_balancer" = "$1" ]; then
  # $2 tells whether to turn balancer on.
  SHELL_CMD="balance_switch $2"
  exec $HBASE_BIN --config $CONF_DIR shell <<< $SHELL_CMD
elif [ "shell" = "$1" ]; then
  SHELL_CMD="${@:2}"
  OUTPUT=$( $HBASE_BIN --config $CONF_DIR shell <<< $SHELL_CMD 2>&1 )
  # The return code is always 0 as the command is just the shell command.
  # Inspect the output to actually detect a failure.
  if [[ "$OUTPUT" == *Exception* || "$OUTPUT" == *Error* ]]; then
    echo "Failed to $SHELL_CMD"
    exit 1
  elif [[ "$SHELL_CMD" == *is_enabled* ]]; then
    if [[ "$OUTPUT" == *true* ]]; then
      cm_success_and_exit HBASE_TABLE_ENABLED
    fi
    cm_success_and_exit HBASE_TABLE_DISABLED
  fi
  exit 0
elif [ "hfileCheck" = "$1" ]; then
  HBASE_MASTER_OPTS=$(replace_pid $HBASE_MASTER_OPTS)
  HBASE_OPTS="$HBASE_MASTER_OPTS $HBASE_OPTS -Dhbase.log.dir=$HBASE_LOG_DIR"
  HBASE_OPTS="$HBASE_OPTS -Dhbase.log.file=$HBASE_LOGFILE"
  HBASE_OPTS="$HBASE_OPTS -Dhbase.root.logger=$HBASE_ROOT_LOGGER"

  if [ "$JAAS_FILE" != "" ]; then
    HBASE_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_OPTS"
  fi
  PATH_TO_JAR=$MGMT_HOME/commands/cdh4/hbase-hfileV1-check-0.94.15-cdh4.6.0.jar
  if [ ! -f $PATH_TO_JAR ]; then
    echo "Could not find $PATH_TO_JAR. Please make sure cloudera-manager-daemons package is installed."
    exit 1
  fi
  CP=`$HBASE_BIN --config $CONF_DIR classpath`
  CP="$PATH_TO_JAR:$CP"
  # OPSAPS-19772 - Solr doesn't set HBase classpath correctly
  CP=$(echo $CP | sed -e "s/ /:/g")
  exec $JAVA_HOME/bin/java $HBASE_OPTS -cp $CP org.apache.hadoop.hbase.util.HFileV1Detector
elif [ "remoteSnapshotTool" = "$1" ]; then
  if [ "export" = "$2" -o "import" = "$2" ]; then
    MR_CONF_DIR=${CONF_DIR}/mr-conf
    if [ "MAPREDUCE" = "$MAPREDUCE_SERVICE_TYPE" ]; then
      HADOOP_HOME=${CDH_MR1_HOME}
      echo "using $CDH_MR1_HOME as CDH_MR1_HOME"
      perl -pi -e "s#{{CDH_MR1_HOME}}#$CDH_MR1_HOME#g" $MR_CONF_DIR/*
    elif [ "YARN" = "$MAPREDUCE_SERVICE_TYPE" ]; then
      HADOOP_HOME=${CDH_HADOOP_HOME}
      echo "using $CDH_MR2_HOME as CDH_MR2_HOME"
      perl -pi -e "s#{{CDH_MR2_HOME}}#$CDH_MR2_HOME#g" $MR_CONF_DIR/*
    else
      echo "Invalid value for MAPREDUCE_SERVICE_TYPE: $MAPREDUCE_SERVICE_TYPE"
      exit 1
    fi
    TOOL_CONF_DIR=$MR_CONF_DIR
  else
    TOOL_CONF_DIR=$CONF_DIR
  fi

  REMOTE_SNAPSHOT_TOOL_JAR=$(ls ${MGMT_HOME}/lib/dr/hbase-remote-snapshot-utils-*.jar | head -n 1)
  HBASE_CLASSPATH="${HBASE_CLASSPATH}:${REMOTE_SNAPSHOT_TOOL_JAR}"
  TOOL_ARGS="${@:2}"
  exec $HBASE_BIN --config $TOOL_CONF_DIR com.cloudera.enterprise.bdr.snapshots.hbase.RemoteSnapshotTool $TOOL_ARGS
else
  # check if a jaas config file is provided for zookeeper authentication
  if [ "$JAAS_FILE" != "" ]; then
    echo "using $JAAS_FILE as JAAS_FILE"
    export HBASE_MANAGES_ZK=false
    if [ "master" = "$1" ]; then
      export HBASE_MASTER_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_MASTER_OPTS"
    elif [ "regionserver" = "$1" ]; then
      export HBASE_REGIONSERVER_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_REGIONSERVER_OPTS"
    elif [ "rest" = "$1" ]; then
      export HBASE_REST_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_REST_OPTS"
    elif [ "thrift" = "$1" ]; then
      export HBASE_THRIFT_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_THRIFT_OPTS"
    elif [ "upgrade" = "$1" ]; then
      export HBASE_OPTS="-Djava.security.auth.login.config=$CONF_DIR/$JAAS_FILE $HBASE_MASTER_OPTS $HBASE_OPTS"
    fi
  fi
  if [ "regionserver" = "$1" -a -n "$CANARY_TIMEOUT" ]; then
    hbase_canary &
  fi
  if [ "start" = "$2" -a $CDH_VERSION -gt 4 ]; then
    if [ "regionserver" = "$1" -o "master" = "$1" ]; then
      # Use PID for the znode file in case process auto-restart is enabled
      export HBASE_ZNODE_FILE="$CONF_DIR/znode$$"
      znode_cleanup $1 &
    fi
  fi
  #exec $HBASE_BIN --config $CONF_DIR "$@"
  
  if [ "thrift" = "$1" ];then
      exec $HBASE_BIN --config $CONF_DIR thrift2 start --port 9090 -threadpool --bind 0.0.0.0
  else
      exec $HBASE_BIN --config $CONF_DIR "$@"
  fi
fi