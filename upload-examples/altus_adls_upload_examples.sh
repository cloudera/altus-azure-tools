#!/bin/bash

#
# Copyright (c) 2017 Cloudera, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# make sure this has a forward slash at the end
SRC_URL=https://cloudera-altus-data-engineering-samples.s3.amazonaws.com/
TMPDIR=

ADLS_ACCOUNT=
ADLS_JAR_PATH=
ADLS_PATH=

DOWNLOAD_ONLY=

print_usage() {
  echo "Copies data files and a jar file to given paths in an ADLS account."\
  echo "Usage:"
  echo "-a|--adls-account a     ADLS account to use, required"
  echo "-p|--adls-path d        Path in ADLS to store files"
}

for i in "$@"
do
  case $i in
    -h|--help)
    print_usage
    exit 0
    ;;

    -a|--adls-account)
    shift
    ADLS_ACCOUNT=$1
    shift
    ;;

    -p|--adls-path)
    shift
    ADLS_PATH=$1
    # strip off the trailing slash if it exists
    ADLS_PATH=${ADLS_PATH%/}
    shift
    ;;

    -d|--download-only)
    DOWNLOAD_ONLY=YES
    shift
    ;;

    #*)
    #>&2 printf "Unrecgonized argument: '$1'\n\n"
    #print_usage
    #exit 1
    #;;
  esac
done

# print error strings
err() {
  for arg in "$@" ; do
    >&2 printf "$arg\n"
  done
}

rm_tmpdir() {
  if [ "x$TMPDIR" != "x" ] ; then
    rm -rf $TMPDIR
  fi
}

# if last command failed, print argument, do cleanup, and exit
test_fail () {
  if [ $? -ne 0 ] ; then
    err "$@"

    rm_tmpdir
    exit 1
  fi
}

# check required arg
required () {
  if [ "x$1" == "x" ] ; then
    err "required parameter $2 not provided"
    exit 1
  fi
}

#######################################################################
###### Function declarations
#######################################################################

# call this repeatedly to parse an xml document one element at a time
parse_tag () {
  local IFS='>'
  read -d '<' TAG VALUE
}

# get a listing of all the files in an aws bucket's subfolder
# this will not preserve subdirectores
# results are space seperated full urls and stored in FILE_URLS
get_file_paths() {
  FILE_URLS=
  local URL=$1

  local XML_LISTING=$(curl -sS $URL)

  while parse_tag ; do
    if [[ "$TAG" == 'Key' ]] ; then
      # if this is a KEY, then the value is a file path
      echo $VALUE | grep -q '/$'
      if [ $? -ne 0 ] ; then
        FILE_URLS="$FILE_URLS $URL$VALUE"
      fi
    fi
  done < <(echo $XML_LISTING)
}

# curl a set of file(s) and save them to ADLS
# global variables needed:
#   TMPDIR - temporary directory, must be non null
#   ADLS_ACCOUNT - ADLS account name
move_to_adls() {
  local ADLS_PATH="$1"
  local URLS=$2

  for f in $URLS; do
    local BASENAME=$(basename $f)
    local FILE_PATH=$(echo $f | sed -E "s/http(s)?:\/\/[^\/]+\/(.*)/\2/")

    printf "Downloading $FILE_PATH\n"
    curl -sS $f > "$TMPDIR/$BASENAME"
    test_fail "Unable to download $f"

    if [[ "$DOWNLOAD_ONLY" != 'YES' ]] ; then
      printf "Copying $FILE_PATH to ADLS...\n"
      az dls fs upload --account "$ADLS_ACCOUNT" --overwrite\
        --destination-path "$ADLS_PATH/$FILE_PATH"\
        --source-path "$TMPDIR/$BASENAME"
      test_fail "Unable to upload $BASENAME to '$ADLS_PATH' in account '$ADLS_ACCOUNT'"
      rm $TMPDIR/$BASENAME
    fi
  done
}

#######################################################################
###### Main path of execution begins here
#######################################################################

required "$ADLS_ACCOUNT" '--adls-account'
required "$ADLS_PATH" '--adls-path'

if [[ "$DOWNLOAD_ONLY" != 'YES' ]] ; then
  # test that we can access the dfs account using az cli
  az dls fs list --account "$ADLS_ACCOUNT" --path / > /dev/null
  test_fail "Unable to access ADLS account '$ADLS_ACCOUNT' using Azure CLI."\
            "Please verify that your account credentials are correct and the 'az'"\
            "executable is in your PATH."
fi

TMPDIR=$(mktemp -d)
test_fail "Error creating a temporary directory. Exiting."

printf "* Starting copying of files to '$ADLS_PATH' in account '$ADLS_ACCOUNT'...\n\n"

get_file_paths $SRC_URL
# FILE_URLS set by get_file_paths
move_to_adls "$ADLS_PATH" "$FILE_URLS"

if [[ "$DOWNLOAD_ONLY" == 'YES' ]] ; then
  printf "\nSample job files and data downloaded to: '$TMPDIR/$BASENAME'\n"
else
  rm_tmpdir
fi
