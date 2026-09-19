## Topology generation. Stands in for discv5, which is out of scope: the harness
## wires the graph the discovery layer would otherwise have produced.
##
## Seeded throughout, so a run is reproducible. Note that logos-delivery calls
## `randomize()` at module scope (waku_node.nim:80), seeding std/random's global
## RNG from the clock -- we never use that global, only our own Rand instance.

{.push raises: [].}

import std/[random, sets, tables, algorithm, sequtils]

type Edge* = tuple[a, b: int]

proc randomRegular*(n, degree: int, seed: int64): seq[Edge] =
  ## Undirected graph where every node has ~`degree` neighbours.
  ##
  ## Pairing-model style: build a stub list with `degree` stubs per node, shuffle
  ## it, and pair off. Rejected pairs (self-loops, duplicates) are dropped rather
  ## than restarted, so the realised degree is slightly under the target -- fine
  ## for a topology that only has to *resemble* what discovery produces, and far
  ## cheaper than an exact k-regular construction at n=3000.
  doAssert degree >= 2, "degree must be >= 2"
  doAssert n > degree, "need n > degree"

  var rng = initRand(seed)
  var stubs = newSeqOfCap[int](n * degree)
  for i in 0 ..< n:
    for _ in 0 ..< degree:
      stubs.add(i)
  rng.shuffle(stubs)

  var seen = initHashSet[Edge]()
  var edges = newSeqOfCap[Edge](n * degree div 2)
  var i = 0
  while i + 1 < stubs.len:
    let a = stubs[i]
    let b = stubs[i + 1]
    i += 2
    if a == b:
      continue
    let e: Edge = if a < b: (a, b) else: (b, a)
    if e in seen:
      continue
    seen.incl(e)
    edges.add(e)

  # Connectivity guard: the pairing model can leave isolated nodes, and an
  # isolated node would show up as a delivery failure that has nothing to do
  # with gossipsub. Stitch any such node to a random other one.
  var deg = newSeq[int](n)
  for e in edges:
    inc deg[e.a]
    inc deg[e.b]
  for v in 0 ..< n:
    if deg[v] == 0:
      var u = rng.rand(n - 1)
      if u == v: u = (u + 1) mod n
      let e: Edge = if v < u: (v, u) else: (u, v)
      if e notin seen:
        seen.incl(e)
        edges.add(e)
        inc deg[v]
        inc deg[u]
  edges

proc ring*(n: int): seq[Edge] =
  for i in 0 ..< n:
    let j = (i + 1) mod n
    result.add(if i < j: (i, j) else: (j, i))

proc degreeStats*(n: int, edges: seq[Edge]): tuple[min, max: int, avg: float] =
  var deg = newSeq[int](n)
  for e in edges:
    inc deg[e.a]
    inc deg[e.b]
  (deg.min, deg.max, deg.foldl(a + b, 0).float / n.float)
