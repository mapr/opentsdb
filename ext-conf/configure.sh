#!/bin/bash


# Script to configure opentTsdb
#


# When called from the master installer, expect to see the following options:
#
# -nodeCount ${otNodesCount} -OT "${otNodesList}" -nodePort ${otPort} 
# -nodeZkCount ${zkNodesCount} -Z "${zkNodesList}" -nodeZkPort ${zkClientPort}
# 
# where the 
#
# -nodeCount    tells you how many openTsdb server configured in the cluster
# -OT           tells you the list of hosts to be configure as opentTsdb servers
#               the format of this list is {hostname[;ipaddress][:port][, ..]}
#
# -nodePort     is the port number openTsdb should be listening on
#
# -nodeZkCount  tells you how many Zookeeper nodes in the cluster
# -Z            tells you the list of Zookeeper nodes
# -nodeZkPort   the port Zookeeper is listening on



# The following configuration knobs needs to be set at a minimum:
# opentsdb.conf:tsd.network.port = 4242


# opentsdb.conf:# The IPv4 network address to bind to, defaults to all addresses
# opentsdb.conf:# tsd.network.bind = 0.0.0.0

# A space separated list of Zookeeper hosts to connect to, with or without
# port specifiers, default is "localhost"
# tsd.storage.hbase.zk_quorum = 10.10.88.98:5181


exit 0

