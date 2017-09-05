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
HADOOP_BASE_URL := $(MAPR_MAVEN_REPO)/org/apache/hadoop/hadoop-common/$(HADOOP_VERSION)

$(HADOOP):
	set dummy "$(HADOOP_BASE_URL)" "$(HADOOP)"; shift; mvn -B org.apache.maven.plugins:maven-dependency-plugin:2.4:get -DrepoUrl=$(MAPR_MAVEN_REPO) -Dartifact=org.apache.hadoop:hadoop-common:$(HADOOP_VERSION) -Ddest=$(HADOOP)

THIRD_PARTY += $(HADOOP)
