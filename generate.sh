#!/usr/bin/env bash

set -exo pipefail

IMAGE_NAME=go-simpleprotoc

VOLUME_SRC=/proto
VOLUME_OUT=/out
TMPFS_GO_PKG=/go/pkg

SRC=
TARGET=
OUT=

GAPIC_PACKAGE=

FORCE=
CMD=

while true; do
	case "${1}" in
	--lang)
		case "${2}" in
		go)
			IMAGE_NAME=go-simpleprotoc
			;;
		*)
			>&2 echo "Unsupported language '${2}'"
			exit 3
			;;
		esac
		shift 2
		;;
	--source-dir)
		SRC="${2}"
		shift 2
		;;
	--target)
		TARGET="${2}"
		shift 2
		;;
	--out | -o)
		OUT="${2}"
		shift 2
		;;
	--flavours)
		FLAVOURS="${2}"
		shift 2
		;;
	--gapic-package)
		GAPIC_PACKAGE="${2}"
		shift 2
		;;
	--gapic-module-prefix)
		GAPIC_MODULE_PREFIX="${2}"
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
	*)
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
if [ -z "${TARGET}" ]; then
	echo >&2 "Missing TARGET"
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
		if [ -z "${GAPIC_PACKAGE}" ]; then
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
	-e SRC="${VOLUME_SRC}/${TARGET}" \
	-e GO_OUT="${GO_OUT}" \
	-e GO_GRPC_OUT="${GO_GRPC_OUT}" \
	-e GO_GAPIC_OUT="${GO_GAPIC_OUT}" \
	-e DESCRIPTOR_OUT=${DESCRIPTOR_OUT} \
	-e GO_GAPIC_PACKAGE="${GO_GAPIC_PACKAGE}" \
	-e GAPIC_MODULE_PREFIX="${GAPIC_MODULE_PREFIX}" \
	--read-only -v "$(pwd)/${TARGET}":"${VOLUME_SRC}/${TARGET}/" \
	-v "$(pwd)/${OUT}":"${VOLUME_OUT}" \
	--tmpfs "${TMPFS_GO_PKG}" \
	-i -t ${IMAGE_NAME} ${CMD}

if [ -n "${CMD}" ]; then
	exit 0
fi

echo Using sudo to chown output to current user ...
U=$(whoami) && sudo chown -R "${U}" "${OUT}"
