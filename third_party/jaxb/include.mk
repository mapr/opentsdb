# Copyright (C) 2017  The OpenTSDB Authors.
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

JAXB_RUNTIME_VERSION := 2.3.3
JAXB_RUNTIME := third_party/jaxb/jaxb-runtime-$(JAXB_RUNTIME_VERSION).jar
JAXB_RUNTIME_BASE_URL := https://repo.maven.apache.org/maven2/org/glassfish/jaxb/jaxb-runtime/$(JAXB_RUNTIME_VERSION)/jaxb-runtime-$(JAXB_RUNTIME_VERSION).jar

$(JAXB_RUNTIME): $(JAXB_RUNTIME).md5
	set dummy "$(JAXB_RUNTIME_BASE_URL)" "$(JAXB_RUNTIME)"; shift; $(FETCH_DEPENDENCY)

JAXB_API_VERSION := 2.3.1
JAXB_API := third_party/jaxb/jaxb-$(JAXB_API_VERSION).jar
JAXB_API_BASE_URL := https://repo.maven.apache.org/maven2/javax/xml/bind/jaxb-api/$(JAXB_API_VERSION)/jaxb-api-$(JAXB_API_VERSION).jar

$(JAXB_API): $(JAXB_API).md5
	set dummy "$(JAXB_API_BASE_URL)" "$(JAXB_API)"; shift; $(FETCH_DEPENDENCY)

THIRD_PARTY += $(JAXB_RUNTIME) $(JAXB_API)
