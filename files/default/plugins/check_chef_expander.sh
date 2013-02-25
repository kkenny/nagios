#!/bin/bash
name="chef-expander"
pidfile="/var/run/chef/expander.pid"

if [ -f $pidfile ]; then
   pid=$(cat ${pidfile})
else
   echo "CRITICAL: $pidfile not found"
   exit 2
fi

procs=$(ps -elf | awk '{ print $4 }' | grep ${pid} | grep -v grep | wc -l)

if [ ${procs} -eq 0 ]; then
   echo "CRITICAL: 0 Process with the name ${name}"
   exit 2
fi

if [ ${procs} -ge 1 ]; then
   echo "OK: ${procs} Processes with the name ${name} with PID:${pid}"
   exit 0
fi

