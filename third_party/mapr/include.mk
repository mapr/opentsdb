# Copyright (C) 2015  The OpenTSDB Authors.
#
# This library is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation, either version 2.1 of the License, or
# (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this library.  If not, see <http://www.gnu.org/licenses/>.
MAPR_VERSION := 6.0.1-mapr
#KAFKA_VERSION := 0.9.0.0-mapr-1607-streams-5.2.0
KAFKA_VERSION := 1.0.1-mapr
MAPR := third_party/mapr/maprfs-$(MAPR_VERSION).jar
if USE_MAPR_SNAPSHOTS
RELEASE_TYPE := "snapshots"
MAPR_VERSION_STR := $(MAPR_VERSION)-SNAPSHOT
KAFKA_VERSION_STR := $(KAFKA_VERSION)-SNAPSHOT
else
RELEASE_TYPE := "releases"
MAPR_VERSION_STR := $(MAPR_VERSION)
KAFKA_VERSION_STR := $(KAFKA_VERSION)
endif

#temporarily switch to snapshot for 6.0.0
MAPR_BASE_URL := http://maven.corp.maprtech.com/nexus/content/repositories/${RELEASE_TYPE}/com/mapr/hadoop/maprfs/${MAPR_VERSION_STR}/

$(MAPR):
	set dummy "$(MAPR_BASE_URL)" "$(MAPR)"; shift; mvn -B org.apache.maven.plugins:maven-dependency-plugin:2.4:get -DrepoUrl=$(MAPR_MAVEN_REPO) -Dartifact=com.mapr.hadoop:maprfs:$(MAPR_VERSION_STR) -Ddest=$(MAPR)

MAPR_STREAMS := third_party/mapr/mapr-streams-$(MAPR_VERSION_STR).jar
MAPR_STREAMS_BASE_URL := http://maven.corp.maprtech.com/nexus/content/repositories/${RELEASE_TYPE}/com/mapr/streams/mapr-streams/${MAPR_VERSION_STR}/

$(MAPR_STREAMS):
	set dummy "$(MAPR_STREAMS_BASE_URL)" "$(MAPR_STREAMS)"; shift; mvn org.apache.maven.plugins:maven-dependency-plugin:2.4:get -DrepoUrl=$(MAPR_MAVEN_REPO) -Dartifact=com.mapr.streams:mapr-streams:$(MAPR_VERSION_STR) -Ddest=$(MAPR_STREAMS)

KAFKA := third_party/mapr/kafka-clients-$(KAFKA_VERSION_STR).jar
#KAFKA_BASE_URL := http://maven.corp.maprtech.com/nexus/content/repositories/${RELEASE_TYPE}/org/apache/kafka/kafka-clients/${KAFKA_VERSION_STR}/
KAFKA_BASE_URL := http://maven.corp.maprtech.com/nexus/content/repositories/${RELEASE_TYPE}/org/apache/kafka/connect-runtime/${KAFKA_VERSION_STR}/

$(KAFKA):
	set dummy "$(KAFKA_BASE_URL)" "$(KAFKA)"; shift; mvn org.apache.maven.plugins:maven-dependency-plugin:2.4:get -DrepoUrl=$(MAPR_MAVEN_REPO) -Dartifact=org.apache.kafka:kafka-clients:$(KAFKA_VERSION_STR) -Ddest=$(KAFKA)

THIRD_PARTY += $(MAPR) $(MAPR_STREAMS) $(KAFKA)
