# prototype
{.experimental.}

import asyncdispatch
import asyncnet
import msgpack
import msgpack_rpc
import locks
import queues

type AllocFn = proc (): AsyncSocket
type Pool = ref object
  lock: TLock
  free: seq[AsyncSocket]
  used: seq[AsyncSocket]
  allocFn: AllocFn

proc mkPool(f: AllocFn): Pool =
  result = Pool(
    free: newSeq[AsyncSocket](),
    used: newSeq[AsyncSocket](),
    allocFn: f
  )
  # FIXME deinitLock on freeing (destructor?)
  initLock(result.lock)

proc size(pool: var Pool): int =
  pool.lock.acquire
  result = len(pool.free) + len(pool.used)
  pool.lock.release

type MultiFuture = ref object
  futs: seq[Future[Msg]]
  pool: Pool
 
proc acquire(pool: var Pool): AsyncSocket =
  pool.lock.acquire
  if len(pool.free) > 0:
    let i = high(pool.free)
    result = pool.free[i]
    pool.free.delete(i)
    pool.used.add(result)
  pool.lock.release
 
proc release(pool: var Pool, sock: AsyncSocket) =
  pool.lock.acquire
  let i = pool.used.find(sock)
  pool.used.delete(i)
  pool.free.add(sock)
  pool.lock.release

proc mkMultiFuture*(f: proc (): AsyncSocket): MultiFuture =
  discard

proc join(mfut: MultiFuture): seq[Msg] =
  for fut in mfut.futs:
    result.add(waitFor(fut))

proc add(mfut: MultiFuture, name: string, args: seq[Msg]) =
  var mfut = mfut # without this, "illegal capture" error
  let sock = mfut.pool.acquire()
  let cli = mkClient(sock)
  var fut = cli.call(sock.getFd().int, name, args)
  fut.callback = proc () =
    mfut.pool.release(sock)
  mfut.futs.add(fut)
