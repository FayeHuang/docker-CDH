#!/bin/bash

SERF_BIN=$SERF_HOME/bin/serf
SERF_CONFIG_DIR=$SERF_HOME/etc
SERF_LOG_FILE=/var/log/serf.log

$SERF_BIN agent -config-dir $SERF_CONFIG_DIR -tag role=CM-SERVER $@ | tee -a $SERF_LOG_FILE
