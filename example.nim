# import msgpack_rpc
import msgpack
import asyncdispatch
import asyncnet
import os

when isMainModule:
  let cl = commandLineParams()
  assert(len(cl) == 1)
  let t = cl[0] # server or client
  if t == "server":
    while true:
      discard
    # let server = TCPServer("localhost", Port(20000))
    # server.addMethod(proc (x: openArray[Msg]): Msg =
    #   let a = unwrapInt(x)
    #   toMsg(a * 2))
    # server.run
  elif t == "client":
    discard
    # let client = TCPClient("localhost", Port(20000))

    # test sync call

    # test async call
  else:
    assert(false)
