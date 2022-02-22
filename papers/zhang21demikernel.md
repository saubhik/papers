# The Demikernel Datapath OS Architecture for Microscale Datacenter Systems

[Irene Zhang, Amanda Raybuck, Pratyush Patel, Kirk Olynyk, Ja- cob Nelson, Omar
S. Navarro Leija, Ashlie Martinez, Jing Liu, Anna Kornfeld Simpson, Sujay
Jayakar, Pedro Henrique Penna, Max Demoulin, Piali Choudhury, Anirudh Badam.
2021. The Demiker- nel Datapath OS Architecture for Microsecond-scale Datacenter
Systems. In ACM SIGOPS 28th Symposium on Operating Systems Principles (SOSP
’21), October 26–29, 2021, Virtual Event, Ger- many. ACM, New York, NY, USA, 17
pages. https://doi.org/10.1145/
3477132.3483569](https://dl.acm.org/doi/10.1145/3477132.3483569)

Datacenter systems and I/O devices now run at single-digit microsecond
latencies, requiring ns-scale OSes. Traditional kernel-based OSs impose
unaffordable overhead, so we eliminate the OS kernel from I/O datapath.

Library OSes separate protection into the OS kernel and management into the
user-level library OSes to better meet custom app needs. Kernel-bypass
architectures offload protection into I/O devices, along with some OS
management. We need a portable OS architecture for microscale kernel-bypass
systems.

This paper proposes Demikernel, which offers a general-purpose datapath OS
replacement that meet the needs of microscale systems:

## 1. Support Heterogeneous OS Offloads

Today's datapath architectures are adhoc - different kernel-bypass libraries
offer different OS features atop kernel-bypass devices. Different devices
offload different OS features. E.g. DPDK provides a raw NIC interface, while
RDMA implements a network protocol with CC & ordered, reliable transmission. We
need to flexibly accommodate heterogeneous kernel-bypass devices.

*Solution: A portable datapath API & flexible OS architecture*

Each Demikernel datapath OS works with a legacy control path OS kernel &
consists of several interchangeable libOSes implemening a new high-level
datapath API called PDPIX (POSIX extension to support microscale kernel-bypass
I/O). PDPIX centers around I/O queue abstraction instead of pipe-based POSIX.
Offload OS features to device when possible (e.g. RDMA libOS offloads network
stack to RDMA NIC). Each Demikernel libOS:

- supports a single kernel-bypass I/O device type (DPDK, SPDK, RDMA)
- I/O processing stack for the device
- libOS-specific memory allocator
- a centralized coroutine scheduler

PDPIX is a POSIX extension tuned for kernel-bypass I/O:

- `accept` returns a queue descriptor instead of a file descriptor.
- `push` & `pop` are for submitting & receiving (both net & storage) I/O
  - input is a scatter-gather memory pointers array to avoid buffering & poor
    tail latencies.
  - non-blocking & return a `qtoken` for apps to fetch completion later (using
    `wait_*` lib calls).
- PDPIX requires all I/O must be from DMA-capable heap for UAF protection.
- `wait_*` solves POSIX's `epoll` inefficiencies:
  - `wait_*` directly returns data from the op for app to process immediately.
  - `wait_*` only wakes worker waiting on the specific `qtoken` on I/O
    completion.

## 2. Coordinate Zero-Copy Memory Access

Zero-copy I/O is critical for latency. Kernel-bypass zero-copy I/O requires 2
types of memory access coordination:

- IOMMU on I/O device needs to perform address translation. This requires
  coordination with CPU's IOMMU and TLB. To avoid page faults and ensure
  address mappings stay fixed during I/O, devices need designated DMA-capable
  memory, pinned in the OS kernel.
- Coordination among app, I/O stack and kernel-bypass device. The TCP
  stack might send memory to the NIC and if network loses the packet & app
  modified or freed the memory in the meantime, the TCP stack cannot
  retransmit.

*Solution: DMA-capable heap with Use-After-Free protection*

Three new features for zero-copy memory coordination:

- portable API with I/O memory buffer ownership semantics (in PDPIX)
  - apps pass ownership to datapath OS when invoking I/O & do not receive
    ownership back until I/O completes.
- zero-copy, DMA-capable heap
  - libOSes replaces the app's memory allocator to back the heap with
    DMA-capable memory in device-specific way.
  - Each libOS use a device-specific, modified Hoard (pool-based memory
    allocator) for memory management. Hoard memory pools, superblocks, are
    allocated with memory from the DPDK mempool for DMA-capable heap.
  - zero-copy I/O offers improvement for buffers only over 1kB.
- UAF protection
  - Demikernel libOS allocators do this with reference counting.
  - no write-protection: can't afford to protect apps from modifying in-use
    buffers

## 3. Multiplex and Schedule the CPU at microscale

Existing kernel-level abstractions like processes & threads are too
coarse-grained for microscale scheduling - they consume entire cores for 100s of
micros. Recent schedulers schedule app workers on a microscale per-I/O basis and
use coarse-grained abstractions for OS work - distributed scheduling. Scheduler
should multiplex app work & datapath OS tasks on single thread.

*Solution: Coroutines*

- Kernel-bypass scheduling on per-I/O basis but POSIX's `epoll` & `select` have
  "thundering herd" issue: cannot deliver events to just one worker. PDPIX
  introduces `wait` which lets app workers wait on specific I/O requests.
- Coroutines encapsulate OS & app work - they are lightweight with low-cost
  context switches well-suited for state-machine-based async event handling. No
  need for expensive global state management.
- A centralized coroutine scheduler: Cannot afford interrupts, so cooperative
  scheduling - coroutines yield after a few micros or less.
- Three states of coroutines: running, runnable, and blocked. Scheduler checks
  only runnable ones, since many coroutines blocked on infrequent I/O events.
- Three types of coroutines:
  - one fast-path I/O processing coroutine for each I/O stack polling for I/O.
  - many background coroutines for other I/O stack work:
    - sending outgoing packets
    - retransmitting lost packets
    - sending pure acks
    - managing connection close state transitions
  - one app coroutine per blocked `qtoken` for app worker.
- Single-threaded Demikernel libOS I/O stacks share app thread and aim for
  run-to-completion: the fast-path coroutine processes incoming data, finds the
  blocked `qtoken`, schedules the app coroutine & processes any outgoing
  messages before moving on to the next I/O. The fast-path coroutine yields
  after every n polls to let other I/O stacks & background work run.
- Using Rust (memory-safety!) requires just 12 cyles for coroutine context
  switch (since Rust compiles coroutines to regular function calls) using
  Lemire's algorithm using x86's `tzcnt` instruction on "waker blocks" for
  nanoscale scheduling.
- Multiplexes net & storage I/O stacks by splitting the fast-path coroutine
  between polling DPDK devices & SPDK completion queues in a round-robin manner
  for fair-share CPU cycle allocation.

The authors compare Demikernel to 2 kernel-bypass applications - testpmd and
perftest, and 3 kernel-bypass libraries - eRPC, Shenango, and Caladan. testpmd
(L2 packet forwarded) & perftest (measure RDMA NIC send and recv latency) are
included with DPDK & RDMA SDKs respectively.

The authors show result with 4 different microscale kernel-bypass systems:

- Echo Application:
  - Demikernel's API semantics & memory management let Demikernel's echo server
    implementation process messages without allocating or copying memory on the
    I/O processing path.
  - Demikernel portably achieves competitive microsecond latencies, ns-scale I/O
    processing, run-to-completion & zero-copy for networking & storage.
- UDP Relay Server:
  - Demikernel makes kernel-bypass easier to use for programmers that are not
    kernel-bypass experts.
- Redis In-memory Distributed Cache:
  - Demikernel lets Redis correctly implement zero-copy I/O from its heap with
    no code changes.
  - Demikernel provides existing microscale apps portable kernel-bypass network
    & storage access with low overhead.
- TxnStore Distributed Transactional Storage:
  - Compared to custom solutions, Demikernel simplifies the coordination needed
    to support zero-copy I/O.
  - Demikernel improves performance for higher-latency microscale datacenter
    apps compared to a naive custom RDMA implementation.

## Strengths

- Demikernel is a first step towards datapath OSes for microscale kernel-bypass
  apps. The work solves the big problems of portability,
  programmability, and performance in designing architectures for kernel-bypass
  systems.
    - Portability: This portability is across heterogeneous networking and
      storage devices, and the architecture can also accommodate future
      programmable devices.
    - Programmability: The extend the POSIX API to optimize and simplify
      microscale kernel-bypass I/O, exposing a friendly API to app programmers.
    - Performance: Demikernel datapath OSes have a per-I/O budget of less than 1
      microsecond for I/O processing & other OS services.
- Considerable engineering effort in implementing multiple libOSes with Linux as
  well as Windows as legacy OS for control path, and three libOS each for RDMA,
  DPDK & SPDK devices. The authors also integrate network & storage libOSes, and
  also developed a POSIX libOS to test and develop Demikernel apps without
  kernel-bypass hardware. This is a testament to the flexibility of the
  Demikernel architecture.

## Weaknesses

This paper gives a design and implementation of a general-purpose datapath OS
for microsecond-scale kernel-bypass apps. There is huge potential for future
work, but this paper does not seem to be short of anything, and accomplishes
what it set out to do.

## Future Work

Each Demikernel OS feature represents a rich area for future work:

- Investigate what semantics a microscale storage stack might supply. Their
  current implementation, Cattree, maps PDPIX queue abstraction onto an abstract
  log for SPDK devices. It is a minimal storage stack with few features and
  works well for logging-based applications. But, we might need to layer more
  complex storage systems above it.
- Investigate efficient microscale memory management with memory allocators. As
  they mention, one can use more modern memory allocators like `mimalloc`. Also,
  since the datapath OS is awaare of the memory access patterns of the
  application, it is possible to do I/O-aware memory scheduling.
- Scaling the coroutine design to multiple cores is not trivial - the Demikernel
  libOSes will need to be carefully designed to avoid shared state across cores.
- Demikernel currently does not eliminate all zero-copy coordination & we might
  need datapath OS features for more explicit memory ownership. Also, one can
  investigate an affordable way to provide write protection in addition to UAF
  for buffers in use.
