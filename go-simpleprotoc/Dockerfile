FROM debian:stable-slim AS downloader

ARG VERSION="3.20.0"
ARG ARCH="linux-x86_64"

RUN  apt-get update && apt-get install -y --no-install-recommends \
     ca-certificates curl unzip

WORKDIR downloads
RUN curl -L -o protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v${VERSION}/protoc-${VERSION}-${ARCH}.zip
WORKDIR /downloads/protoc
RUN unzip ../protoc.zip

WORKDIR /downloads
RUN curl -L -o api-common-protos.zip https://github.com/googleapis/api-common-protos/archive/refs/heads/main.zip
RUN unzip api-common-protos.zip

FROM golang:latest

ARG GO_PLUGIN_VERSION="v1.28"
ARG GRPC_PLUGIN_VERSION="v1.2"
ARG GAPIC_PLUGIN_VERSION="latest"

# Install Protoc
WORKDIR /usr/local/protoc
COPY --from=downloader /downloads/protoc/ ./
RUN ln -s /usr/local/protoc/bin/protoc /usr/local/bin/protoc

# Copy API Common Protos
COPY --from=downloader /downloads/api-common-protos-main/ /proto/googleapis/

# Protobuf Go
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@${GO_PLUGIN_VERSION}

# gRPC Go
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${GRPC_PLUGIN_VERSION}

# GAPIC Go
RUN go install github.com/googleapis/gapic-generator-go/cmd/protoc-gen-go_gapic@${GAPIC_PLUGIN_VERSION}
# (hvl, 2022-04-26): workaround for misnamed executable in version 0.28.0
RUN mv "${GOPATH}/bin/protoc-gen-go_gapic" "${GOPATH}/bin/protoc-gen-go-gapic"


VOLUME /proto /out

WORKDIR /proto

ENV SRC=""
ENV TARGET=""

ENV GO_OUT="/out/protobuf"
ENV GO_GRPC_OUT="/out/grpc"
ENV GO_GAPIC_OUT="/out/gapic"
ENV DESCRIPTOR_OUT="/out/descriptor.pb"

ENV GO_GAPIC_PACKAGE=""
ENV GAPIC_MODULE_PREFIX=""

COPY entrypoint.sh /scripts/

CMD /scripts/entrypoint.sh \
    --source-dir "${SRC}" \
    --target "${TARGET}" \
    --descriptor-out "${DESCRIPTOR_OUT}" \
    --out "${GO_OUT}" \
    --grpc-out "${GO_GRPC_OUT}" \
    --gapic-out "${GO_GAPIC_OUT}" \
    --gapic-package "${GO_GAPIC_PACKAGE}" \
    --gapic-module-prefix "${GAPIC_MODULE_PREFIX}"