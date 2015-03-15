# Experiment

import asyncdispatch
import asyncnet
import rawsockets

let sock = newAsyncSocket()
asyncCheck sock.connect(address="127.0.0.1", port=Port(20002))

proc run(sock: AsyncSocket) {.async.} =
  await sock.send("send")
  echo "start recv"
  let ack = await sock.recv(10000)
  echo ack

waitFor(run(sock)) # OK (this is looping with polling)

# let fu = run(sock)
# asyncCheck fu
# while not fu.finished:
#   discard # NG
#   # poll() # OK
