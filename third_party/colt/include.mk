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

COLT_VERSION := 1.2.0
COLT := third_party/colt/colt-$(COLT_VERSION).jar
COLT_BASE_URL := https://repo.maven.apache.org/maven2/colt/colt/$(COLT_VERSION)

$(COLT): $(COLT).md5
	set dummy "$(COLT_BASE_URL)" "$(COLT)"; shift; $(FETCH_DEPENDENCY)

THIRD_PARTY += $(COLT)
