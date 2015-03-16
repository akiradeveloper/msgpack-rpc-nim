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
    # Note:
    # We need unbuffered sockets for both client and server.
    # The reason is not found.
    let sock = newAsyncSocket(buffered=false)
    defer: sock.close()
    sock.bindAddr(address=addrUse, port=portUse)
    sock.listen()
    var server = newServer(sock)
    server.addMethod("double", proc (args: openArray[Msg]): Msg =
      let a = unwrapInt(args[0])
      wrap(a * 2))
    asyncCheck server.run
    runForever()
  elif t == "client":
    var pool = newSocketPool(proc (): AsyncSocket =
      result = newAsyncSocket(buffered=false)
      echo "wait start"
      waitFor result.connect(address=addrUse, port=portUse)
      echo "wait end")
    var mfut = newMultiFuture(pool)

    # let N = 99
    let N = 1
    for i in 0..N:
      mfut.add("double", @[wrap(i)])
    let ret: seq[Msg] = mfut.join
    for i in 0..N:
      let e = unwrapInt(ret[i])
      echo e
      assert(e == (i * 2))
  else:
    assert(false)
