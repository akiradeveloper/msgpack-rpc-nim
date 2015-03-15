import msgpack_rpc
import msgpack
import asyncdispatch
import asyncnet
import os

when isMainModule:
  let
    portUse = Port(20001)
  let cl = commandLineParams()
  assert(len(cl) == 1)
  let t = cl[0] # server or client
  if t == "server":
    let sock = newAsyncSocket()
    sock.bindAddr(address="localhost", port=portUse)
    sock.listen()
    var server = mkServer(sock)
    server.addMethod("double", proc (args: openArray[Msg]): Msg =
      let a = unwrapInt(args[0])
      wrap(a * 2))
    asyncCheck server.run
    runForever()
    sock.close()
  elif t == "client":
    let sock = newAsyncSocket()
    let client = mkClient(sock)
    asyncCheck sock.connect(address="localhost", port=portUse)
    let fut1 = client.call(id=0, "double", @[PFixNum(100)])
    let ret1 = waitFor(fut1)
    echo "ret: ", unwrapInt(ret1)
  else:
    assert(false)
