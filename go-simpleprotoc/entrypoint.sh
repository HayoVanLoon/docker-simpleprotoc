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

WARNINGS=

# Path to api-common-protos. PROTO_GOOGLEAPIS is used for historical reasons.
if [ -z "${PROTO_GOOGLEAPIS}" ]; then
	echo >&2 "PROTO_GOOGLEAPIS has not been set"
	exit 3
fi

SRC=
TARGET=

GO_OUT=
GO_GRPC_OUT=
GO_GAPIC_OUT=
DESCRIPTOR_OUT=

GAPIC_PACKAGE=

IMPORT_GOOGLEAPIS=-I"${PROTO_GOOGLEAPIS}"
WITH_MOD=

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
	--gapic-config)
		GAPIC_CONFIG="${2}"
		shift 2
		;;
	--no-googleapis-import)
		IMPORT_GOOGLEAPIS=
		shift 1
		;;
	--with-mod)
		WITH_MOD=1
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

if [ -z "${SRC}" ]; then
	echo >&2 "Missing -i <source directory>"
	exit 3
fi

protoc_descriptor() {
	_TARGET="${1}"
	_DESCRIPTOR_OUT="${2}"

	echo "Creating ${_DESCRIPTOR_OUT}"

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
		${IMPORT_GOOGLEAPIS} \
		-I"${SRC}" \
		${FILES}

	echo
	echo "Generated ${_DESCRIPTOR_OUT}"
}

protoc_protobuf() {
	_TARGET="${1}"
	_OUT="${2}"
	_NO_SOURCE_RELATIVE="${3}"

	echo "Compiling Protocol Buffer message code"

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
		${IMPORT_GOOGLEAPIS} \
		-I"${SRC}" \
		${FILES}

	echo
	report "${_OUT}" "message"

	echo
}

protoc_grpc() {
	_TARGET=${1}
	_OUT=${2}
	_NO_SOURCE_RELATIVE=${3}

	echo "Compiling gRPC server code"

	_GO_OPT_PATH=
	_GO_GRPC_OPT_PATH=
	if [ -z "${_NO_SOURCE_RELATIVE}" ]; then
		_GO_OPT_PATH=--go_opt=paths=source_relative
		_GO_GRPC_OPT_PATH=--go-grpc_opt=paths=source_relative
	fi

	if [ -z "${_TARGET}" ]; then
		_TARGET=".*"
	fi

	FILES=$(find "${SRC}/${TARGET}" -type f -name "*.proto" | sort)
	if [ -z "${FILES}" ]; then
		echo >&2 "Could not find any proto files starting with ${SRC}/${_TARGET}"
		exit 3
	fi

	mkdir -p "${_OUT}"

	protoc \
		--go_out="${_OUT}" \
		${_GO_OPT_PATH} \
		--go-grpc_out="${_OUT}" \
		${_GO_GRPC_OPT_PATH} \
		${IMPORT_GOOGLEAPIS} \
		-I"${SRC}" \
		${FILES}

	echo
	report "${_OUT}" "gRPC"
	echo
}

protoc_gapic() {
	_TARGET="${1}"
	_OUT="${2}"
	_GAPIC_PACKAGE=${3}
	_GAPIC_MODULE_PREFIX="${4}"
	_GAPIC_CONFIG="${5}"

	echo "Generating GAPIC client code"

	if [ -z "${_TARGET}" ]; then
		_TARGET=".*"
	fi
	_GAPIC_MODULE_OPT=
	if [ -n "${_GAPIC_MODULE_PREFIX}" ]; then
		_GAPIC_MODULE_OPT="--go-gapic_opt=module=${_GAPIC_MODULE_PREFIX}"
	fi
	_GAPIC_CONFIG_OPT=
	if [ -n "${_GAPIC_CONFIG}" ]; then
		_GAPIC_CONFIG_OPT="--go-gapic_opt=grpc-service-config=${_GAPIC_CONFIG}"
	fi

	FILES=$(find "${SRC}/${TARGET}" -type f -name "*.proto" | sort)
	if [ -z "${FILES}" ]; then
		echo >&2 "Could not find any proto files starting with ${SRC}/${_TARGET}"
		exit 3
	fi

	mkdir -p ${_OUT}

	protoc \
		--go-gapic_out=${_OUT} \
		--go-gapic_opt=go-gapic-package="${_GAPIC_PACKAGE}" \
		${_GAPIC_MODULE_OPT} \
		${_GAPIC_CONFIG_OPT} \
		${IMPORT_GOOGLEAPIS} \
		-I"${SRC}" \
		${FILES}

	report "${_OUT}" "GAPIC"
}

init_mods() {
	_OUT=${1}
	echo "Initialising modules in ${1} ..."
	SAFE_PATH=$(sed -E 's/\//\\\//g' <<<${_OUT})
	PACKAGES=$(find ${_OUT} -type f | sed -E "s/^${SAFE_PATH}\/(.+)\/.+\.go$/\1/g" | uniq)
	for package in $PACKAGES; do
		NOT_V1=$(sed -E 's/\/v[01]$//g' <<<${package})
		cd "${_OUT}/${package}"
		echo "Initialising ${NOT_V1} ..."
		go mod init "${NOT_V1}"
		# requires /go/pkg to be writable (like via tmpfs), will fail otherwise
		if [ "$(go mod tidy -e)" ]; then
			WARNINGS="${WARNINGS}Error tidying dependencies of module ${NOT_V1} \n"
		fi
		echo "... done (${NOT_V1})"
	done
	echo ".. done (initialising modules in ${1})"
}

report() {
	COUNT=$(find "${1}" -type f | wc -l)
	echo "Produced ${COUNT} ${2} file(s)."
}

echo

if [ -n "${DESCRIPTOR_OUT}" ]; then
	protoc_descriptor "${TARGET}" "${DESCRIPTOR_OUT}"
fi

if [ -n "${GO_OUT}" ]; then
	protoc_protobuf "${TARGET}" "${GO_OUT}" 1
	[ -n "${WITH_MOD}" ] && init_mods "${GO_OUT}"
fi

if [ -n "${GO_GRPC_OUT}" ]; then
	protoc_grpc "${TARGET}" "${GO_GRPC_OUT}" 1
	[ -n "${WITH_MOD}" ] && init_mods "${GO_GRPC_OUT}"
fi

if [ -n "${GO_GAPIC_OUT}" ] && [ -n "${GAPIC_PACKAGE}" ]; then
	protoc_gapic "${TARGET}" "${GO_GAPIC_OUT}" "${GAPIC_PACKAGE}" "${GAPIC_MODULE_PREFIX}" "${GAPIC_CONFIG}"
fi

if [ -n "${WARNINGS}" ]; then
	printf "%s" "${WARNINGS}"
fi

echo
