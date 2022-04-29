#!/usr/bin/env bash

set -eo pipefail

IMAGE_NAME=go-simpleprotoc

VOLUME_SRC=/proto
VOLUME_OUT=/out
TMPFS_GO_PKG=/go/pkg

usage() {
	B=$(tput bold)
	X=$(tput sgr0)
	echo -e "
${B}NAME${X}
    ${0} - generate code from Protocol Buffers specifications

${B}SYNOPSIS${X}
    ${0}  [--source-dir DIR] --target DIR --out DIR [--flavours FLAVOURS] [-f] [-i]

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
        Location of the Protocol Buffers specifications. Required.

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
"
}

SRC=
TARGET=
OUT=
FLAVOURS=p

GO_GAPIC_PACKAGE=
GO_GAPIC_MODULE_PREFIX=

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
	--lang)
		case "${2}" in
		go)
			IMAGE_NAME=go-simpleprotoc
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
		usage
		if [ -n "${1}" ]; then
			echo "Unexpected parameter ${1}"
			exit 3
		fi
		break
		;;
	esac
done

if [ -z "${OUT}" ]; then
	echo >&2 "Missing --out <output dir>"
	exit 3
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
	p) GO_OUT="/out/protobuf" ;;
	g) GO_GRPC_OUT="/out/grpc" ;;
	c)
		if [ -z "${GO_GAPIC_PACKAGE}" ]; then
			echo >&2 "Missing --gapic-package <client package name>"
			exit 3
		fi
		GO_GAPIC_OUT="/out/gapic"
		;;
	*)
		echo >&2 "Unknown flavour '${FLAVOURS:$i:1}'"
		exit 3
		;;
	esac
done

if [ -z "${FORCE}" ] && [ $(find "${OUT}" 2>/dev/null) ]; then
	echo "Output directory '${OUT}' is not empty, use -f to ignore"
	exit 3
fi

rm -rf "${OUT}"
mkdir -p "${OUT}"

docker run --rm \
	-e SRC="${VOLUME_SRC}" \
	-e TARGET="${TARGET}" \
	-e GO_OUT="${GO_OUT}" \
	-e GO_GRPC_OUT="${GO_GRPC_OUT}" \
	-e GO_GAPIC_OUT="${GO_GAPIC_OUT}" \
	-e DESCRIPTOR_OUT=${DESCRIPTOR_OUT} \
	-e GO_GAPIC_PACKAGE="${GO_GAPIC_PACKAGE}" \
	-e GO_GAPIC_MODULE_PREFIX="${GO_GAPIC_MODULE_PREFIX}" \
	--read-only -v "$(pwd)":"${VOLUME_SRC}/" \
	-v "$(pwd)/${OUT}":"${VOLUME_OUT}" \
	--tmpfs "${TMPFS_GO_PKG}" \
	-i -t ${IMAGE_NAME} ${CMD}

if [ -n "${CMD}" ]; then
	exit 0
fi

echo Using sudo to chown output to current user ...
U=$(whoami) && sudo chown -R "${U}" "${OUT}"
