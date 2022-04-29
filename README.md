# Simple Protoc 

A script that uses conventions to provide simplified, containerised compilation
of protocol buffers. Compiling Protocol Buffers can be as simple as:
```
./sprotoc.sh
```

## Usage

Build the image, then use the `sprotoc.sh` script with applicable parameters.

If you build the image with a custom name, you should set the environment
variable `SPROTOC_IMAGE_NAME` to this name before running `sprotoc.sh`.

See `sprotoc.sh --help` for a complete overview of options.

## Support

In addition to the languages in the table below, descriptor file generation is
also supported.

| Language | protobuf | grpc | gapic         |
|---------|----------|------|---------------|
| Go      | x        | x    | -<sup>1</sup> |

<sup>1</sup> Work in progress, requires publicly available generated protobuf
module.

## Expected Directory Structure

The script expect a directory structure similar to the one found in
the [Google APIs repository](https://github.com/googleapis/googleapis). But a
simpler tree structure will also suffice, i.e.:

```
.
`-- myproject
    |-- package1
    |   `-- somefile.proto
    `-- service1
        `-- otherfile.proto
```

## Output

Using `sprotoc.sh --out out --flavours dpg` on the simple example structure
above.

### Go

```
out/
|-- descriptor.pb
|-- grpc
|   `-- myproject
|       |-- package1
|       |   |-- go.mod
|       |   |-- go.sum
|       |   `-- somefile.pb.go
|       `-- service1
|           |-- go.mod
|           |-- go.sum
|           |-- otherfile.pb.go            
|           `-- otherfile_grpc.pb.go
`-- protobuf
    `-- myproject
        |-- package1
        |   |-- go.mod
        |   |-- go.sum
        |   `-- somefile.pb.go
        `-- service1
            |-- go.mod
            |-- go.sum
            `-- otherfile.pb.go
```

## Examples

```
sprotoc.sh --out out
```

Generates a message code for proto specifications found recursively from the
current directory.

```
sprotoc.sh --out out --flavours dpg
```

Generates a descriptor, message and server code for proto specifications found
recursively from the current directory.

```
sprotoc.sh --out out --flavours d --extra-opts "--no-googleapis-import"
```

When run from the root of the googleapis repository, generates a descriptor. The
extra option avoids clashes in this case.

```
sprotoc.sh --out out --target google/firestore --flavours dp \
    --extra-opts "--no-googleapis-import"
```

When run from the root of the googleapis repository, generates a descriptor and
message code for Firestore. The extra option avoids clashes in this case.

# License

Copyright 2022 Hayo van Loon

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

       http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
