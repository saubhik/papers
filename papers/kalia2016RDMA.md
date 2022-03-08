# Design Guidelines for High Performance RDMA Systems

Paper: [Anuj Kalia, Michael Kaminsky, and David G. Andersen. 2016. Design
guidelines for high performance RDMA systems. In Proceedings of the 2016 USENIX
Conference on Usenix Annual Technical Conference (USENIX ATC '16).  USENIX
Association, USA, 437–450.](https://dl.acm.org/doi/10.5555/3026959.3027000)

Context
-------

This paper gives the guidelines for high-performance RDMA systems, which
emphasizes paying attention to low-level details such as individual PCIe
transactions & NIC architecture.

There has been a lot of iterest in using RDMAs in DCs. RDMA networks provide
very high bandwidth and low latency and advanced features at surprisingly low
price.

An InfiniBand NIC used in the experiments is Mellanox Connect-IB which provides:
- 2x56 Gbps InfiniBand (throughput)
- ~2 micros RTT (latency)
- supports RDMA (access remote memory without involving remote CPU)
- $1300 (dollars per unit b/w << commonly used 10Gbps Ethernet cards)

A machine in an RDMA cluster consists of a multi-core CPU connected to a
RDMA-capable NIC via the PCIe bus. When an RDMA read request comes from the
network at this NIC, the NIC reads the data from the CPU's memory using a DMA
over PCIe. This DMA involves components of the CPU (PCIe controller, L3 cache)
but doesn't involve the cores. After completing the DMA read, the NIC sends the
RDMA read response back on the network.

Problem with RDMA - Large Design Space
--------------------------------------

One of the main problems with using RDMA is that it is difficult to achieve high
end-to-end system performance. This is because performance depends on a lot of
not-well-understood low-level factors such as the
- CPU-NIC interaction
- the NIC architecture
- details of the PCIe bus

What's the extent to which these low-level factors can affect end-to-end RDMA
performance?

The main reason why it is difficult to achieve high end-to-end system
performance with RDMA is because it provides us a large number of options to
work with:
- multiple types of operations: one-sided, two-sided
- multiple transports implemented by NIC:
	- "reliable" guarantees in-order delivery of messages using acks
	- "unreliable" with no acks
	- "connected"
	- "datagram"
- multiple optimizations depending on app:
	- inlined
	- unsignaled
	- doorbell batching
	- WQE (Work Queue Element) shrinking
	- 0B Recvs

Navigating this design space is difficult because:
- determining which design space option is better requires understanding
	low-level factors (NIC architecture, PCIe bus)
- some of the options seem like a good fit for our apps at a high-level but
	might not provide the best performance: e.g. fetch-and-add for sequencers.
 
Guidelines to navigate the RDMA design space
--------------------------------------------

- Parallel architecture of NICs. Modern high-speed NICs have multiple processing
	units, PUs, such as DMA engines and packet-processing engines. A good design
	should:
	- avoid contention among PUs
	- exploit parallelism among PUs
- Use of PCIe bus: if we can reduce the number or size of the PCIe messages, we
	can get better performance. PCIe messages are generated when:
	- the CPU accesses the NIC's memory: CPUs access NIC's memory by mapping it
		into a process's address space and then by reading or writing it using MMIO
		(memory mapped I/O). MMIO accesses are expensive in terms of CPU cycles.
	- the NIC accesses the CPU's memory (by DMA).

They use an RDMA based system called sequencer to demonstrate how the guidelines
and optimizations work. A sequencer is a server in a cluster that hands out an
increasing sequence of 64-bit integers to clients. They are useful building
blocks in distributed systems: to assign timestamps to distributed transactions,
for example. Whenever a client sends a request to the server, the server
responds with the next integer in the sequence. The main performance metric is
the overall throughput achieved by all clients - rate at which the server hands
out these sequence numbers to clients.

They also use the guidelines and optimizations for other systems such as a
key-value store.

RDMA supports a variety of different ops:
- those that bypass the remote CPU, called one-sided RDMA. This includes RDMA
	reads and writes and also atomic ops such as `fetch-and-add` & compare-and-swap.
	We can do atomic ops on remote memory without involving the remote CPU.
- more traditional messaging ops, send & recv ops. These are two-sided ops
	because they involve both the local & the remote CPU.

With `fetch-and-add`, the sequencer server needs to expose a 64-bit counter over
RDMA & the clients need to issue fetch-and-add on the counter's address. It
gives 2.2M ops/s which is not impressive. This is comparable to TCP/IP over
1Gbps Ethernet and we expect much more performance from 100Gbps RDMA infra. They
improved the throughput of the sequencer by 50x.

*Avoid Contentions - Atomics vs RPC-based sequencers*

`fetch-and-add` based sequencer has poor performance because it introduces
contention among the NIC's processors. The sequencer server has a sequence
counter A in the L3 cache. When a `fetch-and-add` request for address A comes at
the server's NIC, one of the NIC's processors grabs an internal lock for address
A using the NIC's internal concurrency control mechanism. Then this PU reads the
current value of A using a DMA read and increments it using a DMA write. As
there is only one lock, no other PU can make progress for this read-modify-write
over PCIe. The latency of the PCIe bus is ~500ns & the throughput achieved by
this design is ~2M/s (inverse of the latency).

If we want lower contention, we cannot use RDMA atomics because the NIC's PUs
are 500ns away from the L3 cache where the counter is stored. However, the CPU
cores can access the counter in the L3 cache in around 20ns. Instead of
bypassing the server CPU cores, clients involve the server CPU cores using an
RPC-like mechanism. Clients write their request to the server's memory using an
RDMA write. One of the server's CPU cores detect this write by polling on
memory. It atomically increments the counter & sends a response back to the
client. This response can be sent using another RDMA write, but the send op can
be used for higher scalability. In the atomics-based sequencer, there was only
one operation per 500ns because the NIC PU was holding this lock for 500ns for
the read-modify-write over PCIe & no one else could make progress.

Going from atomics to RPC-based design for sequencer gives us 3x improvement in
performance (throughput in M ops/s) even when the RPC-based design uses only 1
core. They tried to improve the single-core performance first. The sequencer
throughput is bottlenecked by the single CPU core. To improve throughput, we
reduce CPU use by reducing the number of MMIOs issued by the CPU core.

*Reduce CPU-to-NIC MMIOs - Doorbell Batching*

For every cache line spanned by the responses, the core issues 1 write to mapped
device memory using MMIO. In this mode, the CPU does a lot of work because it
actively pushes these responses to NIC memory. Instead of pushing the responses
to the NIC, we can use a pull-based model saving CPU cycles: the CPU rings a
small doorbell message on the NIC telling the NIC there are more responses
available, and this is commonly called "ringing-the-doorbell". On detecting the
doorbell, the NIC reads the responses from the CPU's memory using a DMA read. We
can ring a single doorbell even when the responses are destined for different
clients - this optimization is called doorbell batching.

Without doorbell batching, when the CPU core gets new requests, it does some
computation and pushes out the responses one-by-one using MMIO. With doorbell
batching, after doing the computation, the CPU rings a single doorbell on the
NIC, the NIC pulls the responses from the CPU's memory & sends them out to
clients. With doorbell batching, the CPU core's throughput increases by 2x.

Throughput with doorbell batching decreases when we increase the number of CPU
cores, after a point. This is due to reduction in average response batch size
per doorbell because the same client load is now spread across more CPU cores.

*Actively Exploit NIC Parallelism - Multiple Qs*

They achieve higher performance with a single CPU core. The problem with the
current design is that it does not use the NIC's parallelism effectively. A CPU
core can use a network I/O queue to issue responses. As the operations on a
queue need to handled in order, they are all handled by the corresponding NIC PU
to avoid synchronization among multiple PUs. As a result, the other NIC PUs are
idle, the NIC PU handling all of the CPU core's responses is the throughput
bottleneck. We can create another queue (on another NIC PU) and alternate
between these queues across response batches. When we give the core 3 queues to
work with, it's throughput increases to 27.4M ops/s & the combined effect of
doorbell batching & 3 queues is a 4x improvement in single-core throughput. This
is what they acheived with single-core. The next step is to use multiple cores.
The throughput increases almost linearly with cores, and saturates at 97.2M
ops/s with 6 cores. At this point, the sequencer is bottlenecked by the PCIe DMA
b/w.

The HERD key-value store does not benefit from using multiple response queues
per CPU core. Using one queue per CPU core is a problem only when the CPU core
can overwhelm the NIC PU handling it's queue. This does happen for the sequencer
where the per-request processing done by the CPU core is very small. The
key-value store, however, does much more processing per request, so one NIC PU
is sufficient. So, not all guidelines are useful for all applications and these
optimizations require a lot of care. If we use multiple queue for HERD,
performance actually drops a little bit. This is because the additional memory
buffers required for the new queue increase the cache pressure in the CPU.

*Reduce NIC-to-CPU DMAs - Header-only SENDs*

To reach the 50x performance goal, they had to solve the PCIe bandwidth limit.
The current sequencer uses the PCIe bandwidth inefficiently. When the NIC polls
one response from the CPU's memory, it reads 128B of data:
- the first cache line contains a 64B header,
- the second cache line contains the app payload (4B size, 8B data) followed by
	52B of unused space

To reduce PCIe bandwidth use, they brought down the number of cache lines used
from 2 to 1. They used an "Immediate" data field in the header for the payload.
After doing this, the response consists of only the header and fits in 1 cache
line. An interesting challenge is that the "Immediate" data field in InfiniBand
is only 32 bits (4B). They implemented a 64-bit sequencer using only 32-bits of
data per message.

After using the header-only optimization, the throughput increases to 122M
ops/s, and exceeds the 50x design goal. At this point, the sequencer is
bottlenecked by the NIC's processing power.

They evaluate the optimizations on 3 generations of RDMA hardware to ensure that
the performance improvements are not just due to intricacies of a particular
NIC's hardware implementation. They also explain how RDMA ops used PCIe and a
method to measure PCIe's usage using h/w counters.

Strengths
---------

- This paper lays out guidelines that can be used by system designers to
	navigate the RDMA design space. The guidelines emphasize paying attention to
	low-level details such as individual PCIe transactions and NIC architecture,
	which are complicated and there is little existing literature describing them
	or studying their relevance to networked systems.
- They are able to prove that their guidelines and optimizations work and are
	general. They design and implement a network sequencer which is ~50x faster
	than existing designs and scales. Their optimized HERD key-value store is 83%
	faster than the original.

Weaknesses
----------

- The problem with the 500ns latency with atomics-based sequencer was that it
	was restricting the throughput to a very low value. In terms of raw
	operational latency, they have not measured the latency of the atomics-based
	sequencer vs the RPC-based sequencer. The atomics-based sequencer provides
	very low throughput even though it might provide slightly better latency. The
	RPC-based design might suffer a bit due to some additional CPU processing and
	a bit of PCIe latency. (Even though both designs use a single network round
	trip, which is the dominant latency.)

Future Work
-----------

- There needs to be better understanding of low-level factos in network I/O.
	Analyzing RDMA NICs using a PCIe analyzer may reveal more insights into their
	behavior than what is achievable using PCIe counters.
- Designing high-performance RDMA systems is an active area of research. A key
	design decision is the choice of verbs made using a microbenchmark-based
	performance comparison. But there are more dimensions to these comparisons -
	exploring the space of low-level factors and optimizations can offset verb
	performance by several factors.

