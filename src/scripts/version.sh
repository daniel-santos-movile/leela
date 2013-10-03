#!/bin/sh

leela_root=${leela_root:-$(pwd)}
bin_sed=${bin_sed:-/bin/sed}

major=$1
minor=$2
build=$3

read_version () {
  if [ -z "$1" -a -z "$2" -a -z "$3" ]
  then
    major=$(sed -r '/^v/ba; d; :a s/v([0-9]+)\.[0-9]+\.[0-9]+.*/\1/; q' CHANGELOG)
    minor=$(sed -r '/^v/ba; d; :a s/v[0-9]+\.([0-9]+)\.[0-9]+.*/\1/; q' CHANGELOG)
    build=$(sed -r '/^v/ba; d; :a s/v[0-9]+\.[0-9]+\.([0-9]+).*/\1/; q' CHANGELOG)
  else
    [ -z "$major" ] && read -p "major: " major
    [ -z "$minor" ] && read -p "minor: " minor
    [ -z "$build" ] && read -p "build: " build
  fi
  version="$major.$minor.$build"
}

print_usage () {
  echo "[usage] version.sh MAJOR MINOR BUILD"
}

check_environ () {
  test -z "$major" && {
    print_usage
    echo "major can not be blank" >&2
    exit 1
  }

  test -z "$minor" && {
    print_usage
    echo "minor can not be blank" >&2
    exit 1
  }

  test -z "$build" && {
    print_usage
    echo "build can not be blank" >&2
    exit 1
  }

  test -x "$bin_sed" || {
    echo "$bin_sed (sed) program not found or not executable" >&2
    exit 1
  }
}

update_version () {
  local name
  name=$(basename $1)
  echo " updating file: $1"
  [ "$name" = project.clj     ] && $bin_sed -i '/^(defproject blackbox/c\(defproject blackbox "'$version'"' $1
  [ "$name" = warpdrive.cabal ] && $bin_sed -i -r 's/^version:( *).*/version:\1'$version'/' $1
}

write_pyversion () {
  echo " creating file: $1"
  cat <<EOF >"$1"
#!/usr/bin/python
# -*- coding: utf-8; -*-
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# DO NOT EDIT, AUTOMATICALLY GENERATED

major   = "$major"
minor   = "$minor"
build   = "$build"
version = "$major.$minor.$build"

EOF
}

write_hsversion () {
  echo " creating file: $1"
  cat <<EOF >"$1"
-- All Rights Reserved.
--
--    Licensed under the Apache License, Version 2.0 (the "License");
--    you may not use this file except in compliance with the License.
--    You may obtain a copy of the License at
--
--        http://www.apache.org/licenses/LICENSE-2.0
--
--    Unless required by applicable law or agreed to in writing, software
--    distributed under the License is distributed on an "AS IS" BASIS,
--    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--    See the License for the specific language governing permissions and
--    limitations under the License.
--
-- DO NOT EDIT, AUTOMATICALLY GENERATED

module Leela.Version where

major   = "$major"
minor   = "$minor"
build   = "$build"
version = "$major.$minor.$build"

EOF
}

write_clversion () {
  echo " creating file: $1"
  cat <<EOF >"$1"
;; All Rights Reserved.
;;
;;    Licensed under the Apache License, Version 2.0 (the "License");
;;    you may not use this file except in compliance with the License.
;;    You may obtain a copy of the License at
;;
;;        http://www.apache.org/licenses/LICENSE-2.0
;;
;;    Unless required by applicable law or agreed to in writing, software
;;    distributed under the License is distributed on an "AS IS" BASIS,
;;    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;    See the License for the specific language governing permissions and
;;    limitations under the License.
;;
;; DO NOT EDIT, AUTOMATICALLY GENERATED

(ns leela.version)

(def major "$major")

(def minor "$minor")

(def build "$build")

(def version "$major.$minor.$build")

EOF
}

read_version
check_environ
echo "version: $version"
write_pyversion $leela_root/src/python/src/leela/version.py
write_hsversion $leela_root/src/haskell/src/Leela/Version.hs
write_clversion $leela_root/src/clojure/src/leela/version.clj
update_version $leela_root/src/clojure/project.clj
update_version $leela_root/src/haskell/warpdrive.cabal
# update_version "$dracula_root/setup-shared.py"
# update_version "$dracula_root/setup-webapi.py"
# update_version "$dracula_root/setup-console.py"
# update_version "$dracula_root/doc/source/conf.py"
# update_version "$dracula_root/doc/source/index.rst"
# write_pyversion "$dracula_root/src/dracula/shared/version.py"