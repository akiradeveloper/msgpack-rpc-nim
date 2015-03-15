example: msgpack_rpc.nim example.nim
	nim c example

test:
	nim c example
	./example server &
	./example client
	kill -9 `pidof example`

# for testing
# TODO tcpdump
server:	example
	./example server 2>&1 1>log-server

client:	example
	./example client 2>&1 1>log-client
