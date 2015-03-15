import msgpack_rpc
import msgpack
import asyncdispatch
import asyncnet
import os

when isMainModule:
  let
    addrUse = "127.0.0.1"
    portUse = Port(20001)
  let cl = commandLineParams()
  assert(len(cl) == 1)
  let t = cl[0] # server or client
  if t == "server":
    let sock = newAsyncSocket()
    defer: sock.close()
    sock.bindAddr(address=addrUse, port=portUse)
    sock.listen()
    var server = mkServer(sock)
    server.addMethod("double", proc (args: openArray[Msg]): Msg =
      let a = unwrapInt(args[0])
      wrap(a * 2))
    asyncCheck server.run
    runForever()
  elif t == "client":
    let sock = newAsyncSocket()
    defer: sock.close()
    let client = mkClient(sock)
    waitFor sock.connect(address=addrUse, port=portUse)
    echo "call start"
    let fut1 = client.call(id=0, "double", @[PFixNum(100)])
    echo "call end"
    let ret1: Msg = waitFor(fut1)
    echo "ret: ", unwrapInt(ret1)
  else:
    assert(false)
