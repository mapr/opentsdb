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

HADOOP_VERSION := 2.7.0-mapr-1506
HADOOP := third_party/hadoop/hadoop-common-$(HADOOP_VERSION).jar
USE_MAPR_SNAPSHOTS := 1
ifeq ($(USE_MAPR_SNAPSHOTS),1)
RELEASE_TYPE := "snapshots"
HADOOP_VERSION_STR := $(HADOOP_VERSION)-SNAPSHOT
else
RELEASE_TYPE := "releases"
HADOOP_VERSION_STR := $(HADOOP_VERSION)
endif

HADOOP_BASE_URL := $(MAPR_MAVEN_REPO)/org/apache/hadoop/hadoop-common/$(HADOOP_VERSION_STR)
DIRECTORY := third_party/hadoop/apacheds-jdbm1-2.0.0-M2.jar
DIRECTORY_VERSION := 2.0.0-M2
DIRECTORY_BASE_URL := http://artifactory.devops.lab/artifactory/list/maven-corp-releases/org/apache/directory/jdbm/apacheds-jdbm1/$(DIRECTORY_VERSION)/

$(DIRECTORY):
	set dummy "$(DIRECTORY_BASE_URL)" "$(DIRECTORY)"; shift; mvn -B org.apache.maven.plugins:maven-dependency-plugin:2.4:get -DrepoUrl=$(DIRECTORY_BASE_URL) -Dartifact=org.apache.directory.jdbm/:apacheds-jdbm1:$(DIRECTORY_VERSION) -Ddest=$(DIRECTORY)

$(HADOOP):
	set dummy "$(HADOOP_BASE_URL)" "$(HADOOP)"; shift; mvn -B org.apache.maven.plugins:maven-dependency-plugin:2.4:get -DrepoUrl=$(MAPR_MAVEN_REPO) -Dartifact=org.apache.hadoop:hadoop-common:$(HADOOP_VERSION) -Ddest=$(HADOOP)

THIRD_PARTY += $(HADOOP)
