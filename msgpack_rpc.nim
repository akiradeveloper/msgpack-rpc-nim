{.experimental.}

#
# MessagePack-RPC
#

import msgpack
import asyncdispatch
import asyncnet
import rawsockets
import streams
import tables

# BUG!! don't use this. too big?
# let READFULL = 1 shl 63 # as large as to read full data sequence
let READFULL = 1000

# openArray?
type RPCMethod* = proc (args: openArray[Msg]): Msg
## TODO desc

type Server* = object
  sock: AsyncSocket
  methods: TableRef[string, RPCMethod]

proc mkServer*(sock: AsyncSocket): Server =
  Server(
    sock: sock,
    methods: newTable[string, RPCMethod]()
  )

proc addMethod*(server: var Server, name: string, f: RPCMethod) =
  # check (echo and return bool?)
  server.methods.add(name, f)

proc decompose(data: string): seq[Msg] =
  echo "len: ", len(data)
  let st = newStringStream(data)
  let msg = st.unpack
  msg.unwrapArray

proc handleRequest(server: Server, conn: AsyncSocket): Future[void] {.async.} =
  proc noMethod(server: Server, name: string) =
    if not server.methods.hasKey(name):
      raise newException(KeyError, "no method found")

  let inData: string = await conn.recv(READFULL)
  echo "decomp server"
  let inMsg: seq[Msg] = decompose(inData)
  let typ = unwrapInt(inMsg[0])
  case typ:
  of 0: # request: [0, id, method, params]
    # let id = unwrapInt(inMsg[1])
    let name = unwrapStr(inMsg[2])
    echo name

    # respose: [1, id, error, retval]
    let outMsg: Msg = try:
      noMethod(server, name)
      let f: RPCMethod = server.methods[name]
      let ret = f(unwrapArray(inMsg[3]))
      FixArray(@[PFixNum(1), inMsg[1], Nil, ret])
    except Exception:
      echo "error"
      FixArray(@[PFixNum(1), inMsg[1], (-1).toMsg, Nil])

    echo "ack start"
    echo outMsg
    var st = newStringStream()
    st.pack(outMsg)
    # st.setPosition(0)
    await conn.send(st.data)
    echo "ack end"
  of 2: # notify: [2, method, params]
    let name = unwrapStr(inMsg[1])
    try:
      noMethod(server, name)
      let f = server.methods[name]
      discard f(unwrapArray(inMsg[2]))
    except Exception:
      discard
  else:
    echo "bad request (request type isn't either 0 or 2) received"
    discard

proc run*(server: Server) {.async.} =
  proc loop(server: Server): Future[void] {.async.} =
    while true:
      echo "loop"
      let conn = await server.sock.accept
      echo "start to handle conn"
      # shouldn't be await which really waits for return before proceed to next loop
      asyncCheck server.handleRequest(conn)
  await server.loop() # () required otherwise compile fails

type Client = object
  sock: AsyncSocket

proc mkClient*(sock: AsyncSocket): Client =
  Client(sock: sock)

# TODO varargs (illegal capture?)
proc call*(cli: Client, id: int, name: string, args: seq[Msg]): Future[Msg] {.async.} =
  let reqMsg: Msg = FixArray(@[PFixNum(0), wrap(id), wrap(name), wrap(args)])
  echo reqMsg
  var st = newStringStream()
  st.pack(reqMsg)
  # st.setPosition(0)
  echo "cli: send start"
  echo len(st.data)
  let fut = cli.sock.send(st.data) # return to caller
  echo "cli: send end"
  await fut
  echo fut.finished
  echo fut.failed
  let ackData = await cli.sock.recv(READFULL)
  echo "cli: recv end"
  # Response: [1, id, error, retval]
  echo "decomp cli"
  let ackMsg = decompose(ackData)
  let typ = unwrapInt(ackMsg[0])
  result =
    case typ:
    of 1:
      let id = unwrapInt(ackMsg[1])
      if ackMsg[2].kind == mkNil:
        ackMsg[3]
      else:
        ackMsg[2] # FIXME don't return different type. (ok, val) pattern?
    else:
      echo "server replies with bad response type ", typ
      assert(false)
      Nil

proc notify(cli: Client, fun: Msg, args: openArray[Msg]): Future[void] {.async.} =
  discard
