del /f containers\src\std\allocator.d

dmd^
 client.d^
 messages.d^
 stupidlog.d^
 msgpack-d/src/msgpack.d^
 -Imsgpack-d/src^
 -release -inline -O -wi^
 -ofdcd-client

dmd^
 actypes.d^
 conversion/astconverter.d^
 conversion/first.d^
 conversion/second.d^
 conversion/third.d^
 autocomplete.d^
 constants.d^
 messages.d^
 modulecache.d^
 semantic.d^
 server.d^
 stupidlog.d^
 string_interning.d^
 libdparse/src/std/d/ast.d^
 libdparse/src/std/d/entities.d^
 libdparse/src/std/d/lexer.d^
 libdparse/src/std/d/parser.d^
 libdparse/src/std/lexer.d^
 libdparse/src/std/allocator.d^
 libdparse/src/std/d/formatter.d^
 containers/src/memory/allocators.d^
 containers/src/memory/appender.d^
 containers/src/containers/dynamicarray.d^
 containers/src/containers/ttree.d^
 containers/src/containers/unrolledlist.d^
 containers/src/containers/hashset.d^
 containers/src/containers/internal/hash.d^
 containers/src/containers/internal/node.d^
 containers/src/containers/slist.d^
 msgpack-d/src/msgpack.d^
 -Icontainers/src^
 -Imsgpack-d/src^
 -Ilibdparse/src^
 -wi -O -release^
 -ofdcd-server

