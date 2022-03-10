# PRISM: Rethinking the RDMA Interface for Distributed Systems

Matthew Burke, Sowmya Dharanipragada, Shannon Joyner, Adriana Szekeres, Jacob
Nelson, Irene Zhang, and Dan R. K. Ports. 2021. PRISM: Rethinking the RDMA
Interface for Distributed Systems. In ACM SIGOPS 28th Symposium on Operating
Systems Principles (SOSP ’21), October 26–29, 2021, Virtual Event, Germany. ACM,
New York, NY, USA, 15 pages. https://doi.org/10.1145/3477132.3483587

The past few years have seen a continual increase in network bandwidth and as
signaled by Moore's law, CPU speeds have become to stagnate. It has become
critical to reduce the involvement of the CPU when it comes to networking. RDMA
achieves this by providing a standard accelerated interface to access remote
memory directly through the network. Following these hardware trends, recent
years have seen a plethora of distributed systems work that have been redesigned
to utilize RDMA. These include key-value stores, distributed transactions, &
replicated storage systems.

The RDMA interface has two kinds of ops:

- Two-sided ops: they have standard message passing semantics. Here the client
	machine's CPU invokes an RDMA send op & the app running on the remote host
	invokes an RDMA receive op.
- One-sided ops: allow the client to read/write directly to a remote memory
	region with no additional CPU involvement on the remote host.

They both come with their own tradeoffs:

- one-sided ops are faster & more CPU efficient but their interface is
	restrictive allowing only reads & writes to pre-registered memory buffers.
- two-sided ops offer richer semantics but are often slower and less CPU
	efficient.

## Motivating Example

Many implementations of remote data structures use indirection. For example,
hash table used in Pilaf (ATC'13) and FaRM (NSDI'14) key-value stores, two
state-of-the-art RDMA systems, is a hash-based indexed data structure that
maintains pointers to the actual value stored inside the key-value store. A
`get` op could be implemented using RDMA as follows:

- we could issue the `get` as a standard two-sided RPC that is processed by the
	remote CPU and return the value to the client. This only takes 1 network
	roundtrip, but would consume CPU cycles on the remote host.
- we could issue 1 one-sided RDMA read to get the address of where the value is
	located, and another one-sided RDMA read to actually retrieve the value.
	There's no CPU involved, but we need at least 2 network roundtrips to process
	a `get`. The number of network roundtrips would increase in case of hash
	collisions.

Additional network roundtrips can make one-sided implementations slower. What
can we do about this?

- Forgo the use of one-sided ops completely by relying on RPCs. But this
	requires giving up CPU efficiencies that one-sided ops come with.  This is
	done in FaSST (OSDI'16), HERD (SIGCOMM'14).
- Allow apps to install their own custom one-sided logic at the NIC. But this
	comes with significant deployment & security challenges. Done in StRoM
	(EuroSys'20), RMC (HotNets'20).
- Standard Extensions to the RDMA Interface.
 
## PRISM: Primitives for Remote Interaction with System Memory

This work considers standard extensions to the RDMA interface. How to design the
API?

- The primitives must be generic.
- Primitives must express the application logic concisely and generalize to a
	large class of apps.
- Simple enough to be implemented on multiple platforms.


They present PRISM: Primitives for Remote Interaction with System Memory based
on:

- feasible to implement across different network stacks.
- implementable reusing existing RDMA mechanisms like retransmission & access
	control.

The PRISM API: list of proposed extensions to the traditional RDMA interface

- Indirect Read/Write/CAS: The target address specified by the operation can
	instead be interpreted as a pointer to the actual target.
- Enhanced Compare & Swap: Extends RDMA CAS to provide support for arithmetic
	comparisons (>,<) during the compare phase.
- Allocation: Allows memory allocation on the data-plane from a pre-registered
	pool of memory.
- Operation Chaining: Allows for the execution of a chain of other PRISM
	primitives at the NIC.

This is chosen based on their applicability to a large class of systems as well
as their feasibility to implement across different platforms.

## Indirect Reads with PRISM

Going back to the example, we can issue an indirect read PRISM call. The target
address specified by the indirect read is interpreted as an address of a
pointer. This pointer is then dereferenced to obtain the value that is returned
to the client.

- only one network roundtrip
- no CPU involved in the process

More complicated patterns of indirection can be implemented using operation
chaining.

Prototyped PRISM primitives on two different network stacks:

- Google Snap inspired Software RDMA prototype that partitions some CPU cores
	dedicated for packet processing.
- SmartNIC prototype using Mellanox BlueField-1 SmartNIC to execute the PRISM
	primitive.
- Also extensively discussed how the PRISM API could be added to a NIC ASIC
	while reusing underlying mechanisms that already exist in today's NICs.
 
Three case studies to demonstrate the benefits of PRISM:

- PRISM-KV: a key-value store that implements both read & write ops using the
	one-sided PRISM API.
- PRISM-TX: a transactional storage system that implements a timestamp-based
	optimistic concurrency control protocol using PRISM's primitives.
- PRISM-RS: a replicated storage system that implements the ABD quorum
	replication protocol.

Each of these apps are widely used in practice. The proposed extensions allows
us to efficiently implement all of these apps entirely in terms of one-sided
PRISM primitives.

Two kinds of benefits to using PRISM:

- Ops can take fewer network roundtrips with PRISM
	- `Get()` in Pilaf, a KV-Store.
	- `TxRead()` in FaRM, a Transactional Storage System.
	- `ReadPhase()` in ABD, a Replicated Block Store.
- Ops that previously used traditional RPCs can be implemented as one-sided
	PRISM ops.
	- `Put()` in Pilaf
	- `TxCommit()` in FaRM
	- `WritePhase()` in ABD

## Transaction Processing with PRISM - PRISM-TX

FaRM is a state-of-the-art transaction processing sytem over RDMA. We consider a
storage system where data is partitioned among multiple servers and clients
group their ops into transactions. During the execution phase, they either read
or write data from different servers. Reads use one-sided RDMA and writes are
buffered locally in the execution phase. After all the operations finish
executing, the transaction enters the commit phase. FaRM uses a variant of the
two-phase commit protocol:

- Lock: the first phase is obtain locks for the write set.
- Validate: if the lock phase succeeds, we validate the read set to ensure that
	the objects that have been read haven't changed since the execution phase.
- Update & Unlock: if the first two phases are successful, updates take effect &
	all locks are released.

In FaRM, the Update phase & Lock phase have to use RPCs but the read set can be
validated using one-sided RDMA reads.

Can we build something better than FaRM?

The execution phase of FaRM needs no further improvement since all communication
that occurs between client & servers here uses only one-sided ops. There is
scope for improvement in the commit phase. We can replace the RPCs in the Lock &
Update phases with the PRISM API. But we need to make some modifications first.

- In FaRM, data is stored in a hash table that's accessible via RDMA & each
	object is associated with a version number & a lock. This layout wasn't
	designed to allow non-local changes to the version numbers. In order to be
	able to prepare and commit transactions with no CPU involvement, these have to
	be accessible to clients via RDMA. So, we couple the version number with other
	metadata in the hash table's index so that they are available to the client.
- Version numbers must be client-generated since the ops are entirely one-sided.
	For this purpose, we use timestamps generated by loosely-synchronized clocks.
	For each object, we store timestamp of the latest reads, writes & commits that
	occurred to that object, followed by a pointer to it's current value.

With these changes, all the OCC checks in the commit phase can use PRISM's
Enhanced CAS primitives with no additional CPU involvement.

- At the beginning of the commit phase a timestamp is chosen such that it is
	larger than all the timestamps recorded in the read set during the execution
	phase.
- Locking for the write set is done by issuing an Enhanced CAS op on the write
	timestamp. If this PRISM Enhanced CAS succeeds, it is equivalent to obtaining
	a lock on this key & prevent any concurrent readers or writers with a lower
	timestamp from succeeding.
- In the validation phase, we validate the read set by ensuring that the write
	timestamp hasn't changed. This ensures that there are no concurrent writers
	with the intent to write and commit. Then, we update the read timestamp. This
	ensures that no other concurrent transaction with a lower timestamp that reads
	or writes to this object after this point can commit.
- If all the r/w validation checks succeed, in the update phase, we install the
	write by using a chain of PRISM's Allocate & Indirect Write primitives.

The primitives enable a new class of one-sided OCC mechanisms.

They compared PRISM-TX with their implementation of the FaRM protocol using both
hardware & software RDMA implementations for FaRM. PRISM-TX outperforms FaRM in
both throughput and latency with a lower message complexity enabled by PRISM's
primitives, about 5 micros faster than FaRM, & reached about a 1M more txns/s
before saturating the network.

PRISM significantly expands the design space for RDMA-based applications by
offering a middle ground between the restrictive RDMA R/W interface and the
full-generality of RPC communication.

## Strengths

- This paper presents an extended API for access to remote memory. PRISM
	expands the design space for network-accelerated apps, making it possible to
	build new types of apps with minimal server-side CPU involvement,
	demonstrated by their key-value store, replicated storage, and distributed
	transaction apps.
- Coming up with design of an RDMA interface that satisfies the need of
	RDMA-based applications requires understanding the network access patterns of
	different apps & in-depth understanding of current RDMA capabilities to
	extend them for maximal expressibility without requiring complexity and
	losing scalability (on different current & future platforms).

## Weaknesses

- Not a particular weakness, but extending or proposing a new API interface for
	a powerful technology such as the RDMA to be supported in
	commercially-available hardware NICs would require testing a prototype's
	performance on a larger number of applications to convince the NIC
	manufacturers. The paper demonstrates that three sophisticated applications -
	key-value stores, replicated block storage, and distributed transactions - can
	be implemented entirely using the PRISM interface & achieve latency and
	throughput benefits. However, these applications might not be representative
	of the overall class of RDMA-based applications. There is also a huge software
	development overhead of porting current applications to a new interface.

## Future Work

- Implementing the PRISM API in a RDMA-capable hardware NIC to prove their
	statement that their proposal reuses existing microarchitectural mechanisms.
- Investigating mechanisms for memory allocation & management primitives for
	RDMA NICs. Management of client-allocated memory is challenging, with specific
	memory management policies left to the discretion of the client application.
- Explore other communication patterns in apps or how apps can benefit from
	alternative patterns. For example HyperLoop implements a different form of
	chaining - with a specially crafted RDMA request, a sender can cause a
	receiver to initiate a RDMA request to a third machine.

