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

JSINTEROP_BASE_VERSION := 1.0.0
JSINTEROP_BASE := third_party/jsinterop/base-$(JSINTEROP_BASE_VERSION).jar
JSINTEROP_BASE_BASE_URL := https://repo.maven.apache.org/maven2/com/google/jsinterop/base/$(JSINTEROP_BASE_VERSION)

$(JSINTEROP_BASE): $(JSINTEROP_BASE).md5
	set dummy "$(JSINTEROP_BASE_BASE_URL)" "$(JSINTEROP_BASE)"; shift; $(FETCH_DEPENDENCY)

JSINTEROP_ANNOTATIONS_VERSION := 2.0.0
JSINTEROP_ANNOTATIONS := third_party/jsinterop/jsinterop-annotations-$(JSINTEROP_ANNOTATIONS_VERSION).jar
JSINTEROP_ANNOTATIONS_BASE_URL := https://repo.maven.apache.org/maven2/com/google/jsinterop/jsinterop-annotations/$(JSINTEROP_ANNOTATIONS_VERSION)

$(JSINTEROP_ANNOTATIONS): $(JSINTEROP_ANNOTATIONS).md5
	set dummy "$(JSINTEROP_ANNOTATIONS_BASE_URL)" "$(JSINTEROP_ANNOTATIONS)"; shift; $(FETCH_DEPENDENCY)

THIRD_PARTY += $(JSINTEROP_ANNOTATIONS) $(JSINTEROP_BASE)
