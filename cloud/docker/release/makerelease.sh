#!/bin/bash -e

# This script builds the Upspin commands and pushes them to release@upspin.io.
# It is executed by the release Docker container.
# The Docker container provides the Upspin repo in the /workspace directory and
# sets the environment COMMIT_SHA variable to the current Git commit hash of
# that repo.
# The Docker container is built atop xgo (https://github.com/karalabe/xgo)
# which is a framework for cross-compiling cgo-enabled binaries. Its magic
# environment variables are EXT_GOPATH, the location of the Go workspace, and
# TARGETS, a space-separated list of os/arch combinations.

# The commands to build and distribute.
# Command "upspin" must be one of these,
# as it is used to copy the files to release@upspin.io.
cmds="upspin upspinfs cacheserver"

# The operating systems and processor architectures to build for.
oses="darwin linux windows"
arches="amd64"

# Thet tree that contains the release binaries.
user="release@upspin.io"

echo 1>&2 "Repo has base path $1"
export EXT_GOPATH="/gopath"
mkdir -p $EXT_GOPATH/src
cp -R /workspace/ $EXT_GOPATH/src/$1

mkdir /build

for cmd in $cmds; do
	TARGETS=""
	for GOOS in $oses; do
		for GOARCH in $arches; do
			if [[ $GOOS == "windows" && $cmd == "upspinfs" ]]; then
				# upspinfs doesn't run on Windows.
				continue
			fi
			TARGETS="$TARGETS ${GOOS}/${GOARCH}"
		done
	done
	echo 1>&2 "Building $cmd for $TARGETS"
	export TARGETS
	$BUILD upspin.io/cmd/$cmd
done

function upspin() {
	/build/upspin-linux-amd64 -config=/config "$@"
}

for GOOS in $oses; do
	for GOARCH in $arches; do
		osarch="${GOOS}_${GOARCH}"
		destdir="$user/all/$osarch/$COMMIT_SHA"
		for cmd in $cmds; do
			if [[ $GOOS == "windows" && $cmd == "upspinfs" ]]; then
				# upspinfs doesn't run on Windows.
				continue
			fi
			# Use wildcard between os and arch to match OS version
			# numbers in the binaries produced by xgo's build script.
			src="/build/${cmd}-${GOOS}-*${GOARCH}"
			if [[ $GOOS == "windows" ]]; then
				# Windows commands have a ".exe" suffix.
				src="${src}.exe"
				cmd="${cmd}.exe"
			fi
			dest="$destdir/$cmd"
			link="$linkdir/$cmd"
			echo 1>&2 "Copying $src to $dest"
			upspin mkdir $destdir || echo 1>&2 "mkdir can fail if the directory exists"
			upspin cp $src $dest
		done
		link="$user/latest/$osarch"
		echo 1>&2 "Linking $link to $destdir"
		upspin rm $link || echo 1>&2 "rm can fail if the link does not already exist"
		upspin link $destdir $link
	done
done
