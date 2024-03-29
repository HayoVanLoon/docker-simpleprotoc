#!/usr/bin/env bash

# Copyright 2022 Hayo van Loon
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

if [ -z "${SPROTOC_IMAGE_NAME}" ]; then
	SPROTOC_IMAGE_NAME="simpleprotoc:go"
fi

VOLUME_SRC=/proto
VOLUME_OUT=/out

usage() {
	B=$(tput bold)
	X=$(tput sgr0)
	echo -e "
${B}NAME${X}
    ${0} - generate code from Protocol Buffers specifications

${B}SYNOPSIS${X}
    ${0}  [--source-dir DIR] [--target DIR] [--out DIR] [--flavours FLAVOURS] [-f] [-i] [--extra-opts TEXT]

${B}DESCRIPTION${X}
    Runs the protoc compiler docker image for the requested output.

    ${B}--source-dir${X} DIR
        Directory that will be mounted as (read-only) source. Defaults to
        current directory.

    ${B}--target${X} DIR
        Directory with target the Protocol Buffers specifications. This is
        useful if the source directory contains external dependencies that need
        not be compiled.

    ${B}--out${X} DIR
        Location of the Protocol Buffers specifications. Defaults to 'out'.

    ${B}--flavours${X} FLAVOURS
        FLAVOURS is a string containing the output types. Valid characters are:
        p - Protocol Buffers message code (default)
        g - gRPC server code
        d - Descriptor set
        c - GAPIC client code

    ${B}-f${X}
        Do no ask to overwrite output directory if present.

    ${B}-i${X}
        Run interactive shell (for debugging).

    ${B}--extra-opts${X} TEXT
        Appends additional options (in text) to the build container's entrypoint
        script.

${B}EXAMPLES${X}
    ${B}${0}${X}

    Generates a message code for proto specifications found recursively from the
    current directory.

    ${B}${0} --out out --flavours dpg${X}

    Generates a descriptor, message and server code for proto specifications
    found recursively from the current directory.

    ${B}${0} --out out --flavours d --extra-opts \"--no-googleapis-import\"${X}

	When run from the root of the googleapis repository, generates a descriptor.
	The extra option avoids clashes in this case.

    ${B}${0} --out out --target google/firestore --flavours dp
	    --extra-opts \"--no-googleapis-import\"${X}

	When run from the root of the googleapis repository, generates a descriptor
	and message code for Firestore. The extra option avoids clashes in this
	case.
"
}

SRC=
TARGET=
OUT=
FLAVOURS=p

GO_GAPIC_PACKAGE=
GO_GAPIC_MODULE_PREFIX=

EXTRA_OPTS=

FORCE=
CMD=

while true; do
	case "${1}" in
	--source-dir)
		SRC="${2}"
		shift 2
		;;
	--target)
		TARGET="${2}"
		shift 2
		;;
	--out)
		OUT="${2}"
		shift 2
		;;
	--flavours)
		FLAVOURS="${2}"
		shift 2
		;;
	--go-gapic-package)
		GO_GAPIC_PACKAGE="${2}"
		shift 2
		;;
	--go-gapic-module-prefix)
		GO_GAPIC_MODULE_PREFIX="${2}"
		shift 2
		;;
	--extra-opts)
		EXTRA_OPTS="${2}"
		shift 2
		;;
	--lang)
		case "${2}" in
		go)
			SPROTOC_IMAGE_NAME=go-simpleprotoc
			;;
		*)
			echo >&2 "Unsupported language '${2}'"
			exit 3
			;;
		esac
		shift 2
		;;
	-i)
		CMD="bash"
		shift 1
		;;
	-f)
		FORCE=1
		shift 1
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		if [ -n "${1}" ]; then
			usage
			echo "Unexpected parameter '${1}'"
			exit 3
		fi
		break
		;;
	esac
done

if [ -z "${OUT}" ]; then
	OUT=out
fi

if [ -z "${SRC}" ]; then
	SRC=.
fi

GO_OUT=
GO_GRPC_OUT=
GO_GAPIC_OUT=
DESCRIPTOR_OUT=

for ((i = 0; i < ${#FLAVOURS}; i += 1)); do
	case ${FLAVOURS:$i:1} in
	d) DESCRIPTOR_OUT="/out/descriptor.pb" ;;
	p) GO_OUT="/out" ;;
	g) GO_GRPC_OUT="/out" ;;
	c)
		if [ -z "${GO_GAPIC_PACKAGE}" ]; then
			echo >&2 "Missing --gapic-package <client package name>"
			exit 3
		fi
		GO_GAPIC_OUT="/out"
		;;
	*)
		echo >&2 "Unknown flavour '${FLAVOURS:$i:1}'"
		exit 3
		;;
	esac
done

if [ -z "${FORCE}" ] && [ -e "${OUT}" ]; then
	echo "Output directory '${OUT}' is not empty, use -f to ignore"
	exit 3
fi

rm -rf "${OUT}"
mkdir -p "${OUT}"

if [ "${SRC:0:1}" = "/" ]; then
	ABS_SRC=${SRC}
else
	ABS_SRC="$(pwd)/${SRC}"
fi

if [ "${OUT:0:1}" = "/" ]; then
	ABS_OUT=${OUT}
else
	ABS_OUT="$(pwd)/${OUT}"
fi


docker run --rm \
	-e SRC="${VOLUME_SRC}" \
	-e TARGET="${TARGET}" \
	-e GO_OUT="${GO_OUT}" \
	-e GO_GRPC_OUT="${GO_GRPC_OUT}" \
	-e GO_GAPIC_OUT="${GO_GAPIC_OUT}" \
	-e DESCRIPTOR_OUT=${DESCRIPTOR_OUT} \
	-e GO_GAPIC_PACKAGE="${GO_GAPIC_PACKAGE}" \
	-e GO_GAPIC_MODULE_PREFIX="${GO_GAPIC_MODULE_PREFIX}" \
	-e EXTRA_OPTS="${EXTRA_OPTS}" \
	-v "${ABS_SRC}:${VOLUME_SRC}/" \
	-v "${ABS_OUT}:${VOLUME_OUT}" \
	-i -t ${SPROTOC_IMAGE_NAME} ${CMD}

if [ -n "${CMD}" ]; then
	exit 0
fi

echo Using sudo to chown output to current user ...
U=$(whoami) && sudo chown -R "${U}" "${OUT}"
