# Re-architecting datacenter networks and stacks for low latency and high performance

The goal of designing datacenter network is latency.

- Predictable low-latency, request-response behavior.
	- Zero-RTT setup.
	- Extremely fast start of connections.
	- Very short switch queues.
	- Graceful incast behavior, minimal collateral damage for the flows.
- Receiver prioritization
	- Receiver knows which flows are most important at this instant. 
- Predictable high throughput. 
	- Per-packet load balancing.

These goals interact with each other very badly. How close can we get to
achieving them all simultaneously.

Data sender: For minimal latency, start sending at line rate (blast without even
a connection-setup handshake). No prior handshake: zero RTT setup. What could go
wrong?

Modern datacenters have some variant of Clos topology. A Clos topology provides
enough bandwidth (capacity) for everyone to send at line rate. The problem is
not lack of capacity. The problem is comes out of how do route the flows. With
per-flow ECMP, then due to flow collisions which cause lots of loss, it's hard
to use all the capacity.

Solution: If every data sender starts at line rate and sprays packets equally
across all paths to destination, then you are not going to have flow collisions
and you can use the full capacity of the network core. The downside is this
requires lots of reordering which makes it a burden for transport protocol.

The other problem is if all the flows are sending to the same destination, then
we can have incast near the receiver.

At 10Gbps it takes 7.2us to serialize a 9KB packet. If there is no queueing,
then latency is dominated by serialization. A small control packet (like an ACK)
can traverse the whole network in < 7.2us.

Question: What should a switch do when the outgoing link is overloaded (like
with incast)?

- Loss: is bad but retransmission is cheap but per-packet multipath makes it
	difficult to tell if loss has occurred. This causes delay.
- ECN: leads to less loss. Need large queues to reduce loss with incast. This
	causes delay.
- Lossless Ethernet: no loss. But builds large queues. PFC delays other
	unrelated flows. This leads to delay & collateral damage.

Packet Trimming is a middle ground: When a queue fills, trim off the payload and
forward just the header. No metadata loss. Receiver knows exactly what was sent,
even with reordering. (Lossless metadata but data loss). To keep the latency
low, data packet queue of only 8 packets is enough. When the data queue
overflows, the payload is trimmed (dropped) from the arriving packets, and
forward the header in a priority queue (priority forwarded). This allows the
receiver to find out as soon as possible that the data packet didn't make it. We
also priority forward ACKs, and other control packets. This lets us do fast
retransmissions.

Let's send an incast to the destination. A queue starts building at the ToR
switch. A packet gets trimmed and receiver requests retransmission, which gets
priority forwarded. And then retransmission happens. Retransmission arrives
before queue has completely drained.

So, we just start, spray and trim.

- no prior handshake (0-RTT setup)
- send first RTT of data at line rate
- per-packet multipath load balancing
- packet trimming + prioritization + fast RTX

This gives us:

- fastest possible startup
- no traffic concentration in core
- low latency, high throughput for incast

But this also means:

- persistent high-rate flow collision near the receiver
- lots of trimming
- collateral damage to nearby flows

We can solve this by decoupling the ack clock. We can separate the acking from
the clocking:

- whenever a data packet arrives, ack or nack it immediately.
	- control packets get priority going through our network.
	- sender knows what happened to a packet within 400us.
- clock all senders from receiver with PULL packets.

When an incast starts at an NDP receiver, for every incoming packet or header,
we add a pull packet to the pull queue. When the receiver's link is overloaded,
headers start arriving and a pull queue builds. Pull packets are sent at the
rate we want the incoming packets to arrive. The receiver gets control of the
incoming traffic. After the first RTT, packets arrive at line rate. If the
receiver wants, the receiver can also prioritize traffic from one sender over
another. The receiver is controlling its own incoming traffic flow.

The sender sends at line rate for the first RTT. And then it stops. After that
receiver controls transmission by sending pulls. Pull packets from the receiver
will clock out data. Pulls trigger retransmissions or sending of new data.

The senders send at line rate for the first RTT. The small queue fills. Packets
are trimmed. After the first RTT, packets are pulled, no more trimming occurs.

So NDP is start, spray, trim, pull. This gives us:

- very quick setup (no prior handshake - zero-RTT setup)
- send 1st RTT of data at line rate
- per-packet multipath load balancing
- packet trimming + prioritization + fast RTX
- after 1st RTT, receiver pulls at its own rate
- receiver can choose which senders to pull first

The authors implemented NDP in:

- `htsim` packet-level simulation
- linux end-systems using DPDK
- custom linux switch using DPDK
- hardware switch using NetFPGA SUME
- P4 reference switch

Evaluations:

- NDP has low flow completion times, even in the presence of heavy background
	traffic. They managed to keep switch queues really short even when the network
	is running at max capacity.
- Linux/NetFPGA implementation has near-optimal incast behavior. NDP achieves
	near-optimal large incast completion times.
- All the new protocols like MPTCP, DCTCP, DCQCN and NDP can do incast. MPTCP
	requires 200 packet output buffers, DCTCP requires 200, DCQCN requires 10000
	packet shared buffers and NDP requires just 8 packet output buffers.

Incast is not hard if we don't care what happens to the neighbors. Suppose we
have one long-lived flow going to node A and 64 more incast flows to node B on
same switch as A but different switch port. With DCTCP when the incast flows
arrive, the neighboring long flow dies and it takes a while to recover. With
loss-less Ethernet, it's lot better but still the long flows suffer from bad
collateral damage and this is because there is so much incoming traffic that
they get paused up to the next switch up in the topology and that pauses the
long flow as well as the short flows. NDP causes minimal collateral damage to
neighboring flows. There is a little tiny 1 RTT glitch in the long flow, and in
the very next RTT, it is back to full rate again.

Receiver pulling allows the receiver to prioritize flows it cares about.

NDP also works well with:

- simultaneous incast and outcast.
- heterogeneous packet sizes, flow patterns.
- overcommitted or overloaded topologies.
- "failed" links, including linkspeed differences.
- virtual machines (with hypervisor support).

NDP does not work well:

- unequal length multipath, such as BCube. (doesn't make sense to spray equally
	among all paths)
	- can be very unfair without per-path rate control.
- public internet.

