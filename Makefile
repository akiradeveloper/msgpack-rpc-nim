test:
	nim c example
	./example server &
	./example client
	kill -9 `pidof example`
