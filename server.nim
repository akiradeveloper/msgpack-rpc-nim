# Experiment

import asyncdispatch
import asyncnet
import rawsockets

proc run(sock: AsyncSocket): Future[void] {.async.} =
  while true:
    let conn: AsyncSocket = await sock.accept
    echo conn.isClosed #=> false
    let data: string = await conn.recv(10000)
    echo conn.isClosed #=> false
    echo len(data) #=> 0
    echo "start ack"
    await conn.send("ack")

proc serve() {.async.} =
  let sock = newAsyncSocket(buffered=false)
  sock.bindAddr(address="127.0.0.1", port=Port(20002))
  sock.listen()
  await sock.run()

asyncCheck serve()
runForever()
