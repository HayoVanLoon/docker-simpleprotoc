#!/usr/bin/env bash

set -eo pipefail

WARNINGS=

# Path to api-common-protos. PROTO_GOOGLEAPIS is used for historical reasons.
PROTO_GOOGLEAPIS="/proto/googleapis"

SRC=
TARGET=

GO_OUT=
GO_GRPC_OUT=
GO_GAPIC_OUT=
DESCRIPTOR_OUT=

GAPIC_PACKAGE=

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
	--out | -o)
		GO_OUT="${2}"
		shift 2
		;;
	--grpc-out)
		GO_GRPC_OUT="${2}"
		shift 2
		;;
	--gapic-out)
		GO_GAPIC_OUT="${2}"
		shift 2
		;;
	--descriptor-out | -d)
		DESCRIPTOR_OUT="${2}"
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
	*)
		if [ -n "${1}" ]; then
			echo "Unexpected parameter ${1}"
			exit 3
		fi
		break
		;;
	esac
done

if [ -z "${SRC}" ]; then
	echo >&2 "Missing -i <source directory>"
	exit 3
fi

protoc_descriptor() {
	_TARGET="${1}"
	_DESCRIPTOR_OUT="${2}"

	if [ -z "${_TARGET}" ]; then
		_TARGET=".*"
	fi

	FILES=$(find "${SRC}/${TARGET}" -type f -name "*.proto" | sort)
	if [ -z "${FILES}" ]; then
		echo >&2 "Could not find any proto files starting with ${SRC}/${_TARGET}"
		exit 3
	fi

	protoc \
		--descriptor_set_out=${_DESCRIPTOR_OUT} \
		--include_imports \
		--include_source_info \
		-I"${PROTO_GOOGLEAPIS}" \
		-I"${SRC}" \
		${FILES}

	echo
	echo "Generated ${_DESCRIPTOR_OUT}"
}

protoc_protobuf() {
	_TARGET="${1}"
	_OUT="${2}"
	_NO_SOURCE_RELATIVE="${3}"

	_GO_OPT_PATH=
	if [ -z "${_NO_SOURCE_RELATIVE}" ]; then
		_GO_OPT_PATH=--go_opt=paths=source_relative
	fi

	if [ -z "${_TARGET}" ]; then
		_TARGET=".*"
	fi

	FILES=$(find "${SRC}/${TARGET}" -type f -name "*.proto" | sort)
	if [ -z "${FILES}" ]; then
		echo >&2 "Could not find any proto files starting with ${SRC}/${_TARGET}"
		exit 3
	fi

	mkdir -p ${_OUT}

	protoc \
		--go_out="${_OUT}" \
		${_GO_OPT_PATH} \
		-I"${PROTO_GOOGLEAPIS}" \
		-I"${SRC}" \
		${FILES}

	echo
	report "${_OUT}" "message"

	echo
	init_mods "${_OUT}"
}

protoc_grpc() {
	_TARGET="${1}"
	_OUT="${2}"

	if [ -z "${_TARGET}" ]; then
		_TARGET=".*"
	fi

	FILES=$(find "${SRC}/${TARGET}" -type f -name "*.proto" | sort)
	if [ -z "${FILES}" ]; then
		echo >&2 "Could not find any proto files starting with ${SRC}/${_TARGET}"
		exit 3
	fi

	mkdir -p ${_OUT}

	protoc \
		--go_out="${_OUT}" \
		--go_opt=paths=source_relative \
		--go-grpc_out="${_OUT}" \
		--go-grpc_opt=paths=source_relative \
		-I"${PROTO_GOOGLEAPIS}" \
		-I"${SRC}" \
		${FILES}

	echo
	report "${_OUT}" "gRPC"
	echo
	init_mods "${_OUT}"
}

protoc_gapic() {
	_TARGET="${1}"
	_OUT="${2}"
	_GAPIC_PACKAGE="${3}"
	_GAPIC_MODULE_PREFIX="${4}"

	if [ -z "${_TARGET}" ]; then
		_TARGET=".*"
	fi
	GAPIC_MODULE_PARAM=
	if [ -n "${_GAPIC_MODULE_PREFIX}" ]; then
		GAPIC_MODULE_PARAM="--go-gapic_opt=module=${_GAPIC_MODULE_PREFIX}"
	fi

	FILES=$(find "${SRC}/${TARGET}" -type f -name "*.proto" | sort)
	if [ -z "${FILES}" ]; then
		echo >&2 "Could not find any proto files starting with ${SRC}/${_TARGET}"
		exit 3
	fi

	mkdir -p ${_OUT}

	protoc \
		--go-gapic_out=${_OUT} \
		--go-gapic_opt=go-gapic-package=${_GAPIC_PACKAGE} \
		${_GAPIC_MODULE_PARAM} \
		-I"${PROTO_GOOGLEAPIS}" \
		-I"${SRC}" \
		${FILES}

	report "${_OUT}" "GAPIC"
}

init_mods() {
	_OUT=${1}
	echo "Initialising modules ..."
	SAFE_PATH=$(sed -E 's/\//\\\//g' <<<${_OUT})
	PACKAGES=$(find ${_OUT} -type f | sed -E "s/^${SAFE_PATH}\/(.+)\/.+\.go$/\1/g" | uniq)
	for package in $PACKAGES; do
		NOT_V1=$(sed -E 's/\/v[01]$//g' <<<${package})
		cd "${_OUT}/${package}"
		echo "Initialising ${NOT_V1} ..."
		go mod init "${NOT_V1}"
		# requires /go/pkg to be writable (like via tmpfs), will fail otherwise
		if [ $(go mod tidy -e) ]; then
			WARNINGS="${WARNINGS}Error tidying dependencies of module ${NOT_V1} \n"
		fi
		echo "... done (${NOT_V1})"
	done
	echo ".. done (initialising modules)"
}

report() {
	COUNT=$(find "${1}" -type f | wc -l)
	echo "Produced ${COUNT} ${2} file(s)."
	if [ "${COUNT}" -lt 10 ]; then
		for file in $(find "${1}" -type f); do
			echo "    ${file}"
		done
	fi
}

echo

if [ -n "${DESCRIPTOR_OUT}" ]; then
	protoc_descriptor "${TARGET}" "${DESCRIPTOR_OUT}"
fi

if [ -n "${GO_OUT}" ]; then
	protoc_protobuf "${TARGET}" "${GO_OUT}"
fi

if [ -n "${GO_GRPC_OUT}" ]; then
	protoc_grpc "${TARGET}" "${GO_GRPC_OUT}"
fi

if [ -n "${GO_GAPIC_OUT}" ] && [ -n "${GAPIC_PACKAGE}" ]; then
	protoc_gapic "${TARGET}" "${GO_GAPIC_OUT}" "${GAPIC_PACKAGE}" "${GAPIC_MODULE_PREFIX}"
fi

if [ -n "${WARNINGS}" ]; then
	printf "${WARNINGS}"
fi

echo
