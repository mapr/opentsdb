# Copyright (C) 2011-2013  The OpenTSDB Authors.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#   - Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   - Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#   - Neither the name of the StumbleUpon nor the names of its contributors
#     may be used to endorse or promote products derived from this software
#     without specific prior written permission.
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

APACHE_ANT_VERSION := 1.10.8
APACHE_ANT := third_party/apache/ant-$(APACHE_ANT_VERSION).jar
APACHE_ANT_BASE_URL := https://repo.maven.apache.org/maven2/org/apache/ant/ant/$(APACHE_ANT_VERSION)

APACHE_MATH_VERSION := 3.4.1
APACHE_MATH := third_party/apache/commons-math3-$(APACHE_MATH_VERSION).jar
APACHE_MATH_BASE_URL := https://repo.maven.apache.org/maven2/org/apache/commons/commons-math3/$(APACHE_MATH_VERSION)

APACHE_LANG_VERSION := 3.0
APACHE_LANG := third_party/apache/commons-lang3-$(APACHE_LANG_VERSION).jar
APACHE_LANG_BASE_URL := https://repo.maven.apache.org/maven2/org/apache/commons/commons-lang3/$(APACHE_LANG_VERSION)

APACHE_TAPESTRY_FRAMEWORK_VERSION := 4.1.6
APACHE_TAPESTRY_FRAMEWORK := third_party/apache/tapestry-framework-$(APACHE_TAPESTRY_FRAMEWORK_VERSION).jar
APACHE_TAPESTRY_FRAMEWORK_BASE_URL := https://repo.maven.apache.org/maven2/org/apache/tapestry/tapestry-framework/$(APACHE_TAPESTRY_FRAMEWORK_VERSION)

$(APACHE_ANT): $(APACHE_ANT).md5
	set dummy "$(APACHE_ANT_BASE_URL)" "$(APACHE_ANT)"; shift; $(FETCH_DEPENDENCY)

$(APACHE_MATH): $(APACHE_MATH).md5
	set dummy "$(APACHE_MATH_BASE_URL)" "$(APACHE_MATH)"; shift; $(FETCH_DEPENDENCY)

$(APACHE_LANG): $(APACHE_LANG).md5
	set dummy "$(APACHE_LANG_BASE_URL)" "$(APACHE_LANG)"; shift; $(FETCH_DEPENDENCY)

$(APACHE_TAPESTRY_FRAMEWORK): $(APACHE_TAPESTRY_FRAMEWORK).md5
	set dummy "$(APACHE_TAPESTRY_FRAMEWORK_BASE_URL)" "$(APACHE_TAPESTRY_FRAMEWORK)"; shift; $(FETCH_DEPENDENCY)

THIRD_PARTY += $(APACHE_MATH)
THIRD_PARTY += $(APACHE_LANG)
THIRD_PARTY += $(APACHE_TAPESTRY_FRAMEWORK)
THIRD_PARTY += $(APACHE_ANT)

