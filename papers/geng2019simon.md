# SIMON: A Simple and Scalable Method for Sensing, Inference and Measurement in DCNs

Yilong Geng, Shiyu Liu, Zi Yin, Ashish Naik, Balaji Prabhakar, Mendel Rosenblum,
and Amin Vahdat. 2019. SIMON: a simple and scalable method for sensing,
inference and measurement in data center networks. In Proceedings of the 16th
USENIX Conference on Networked Systems Design and Implementation (NSDI'19).
USENIX Association, USA, 549–564.

SIMON is about measuring accurate queue sizes in the network from the edge of
the data center network.

Network measurement is useful for:

- network health monitoring
- traffic engineering
- network capacity planning
- troubleshooting of performance problems, breakdowns & failures
- detecting anomalies and security threats

The main challenges are:

- accuracy: accurately observe & measure events or phenomena of interest
- scalability: large networks, high line rates, large event frequency
- speed: perform accurate & scalable measurement in near real-time as opposed to
	offline

Most solutions seek to make effective trade-offs among these conflicting
requirements.

Two classes of network measurement methods:

- switch-based measurement:
	- syslog & SNMP (polling switch port counters)
	- Netflow & sFlow (flow-level statistics)
	- in-band network telemetry (INT, per-packet information)
	- pros: widely available, can be accurate (especially INT)
	- cons: require h/w support, hard to reassemble global view (requires vendor
		agreement), overhead of data transfer, storage & processing
- edge-based measurements:
	- Trumpet, 007, PingMesh, and many others
	- Pros: flexible since not tied to switches, resources on end-hosts are abundant
	- Cons: obtains partial views (delay distributions, identifying lossy links
		etc.), not as accurate as switch-based

SIMON falls in edge-based measurements:

- use data gathered entirely at the edge
- reconstruct near-exact queueing dynamics in the network

They observed that queue sizes sampled at 1-ms sampling rate captures almost all
fluctuations of the queue. The noise (jitter) is small relative the the queue
sizes and hence reconstructing this (& a per-flow decomposition of it) is much
simpler & scalable. They try to first reconstruct the overall queueing delays &
then break down the queueing delay into individual flows. They also try to get a
link utilization breakdown to individual flows too.

Some use cases of the 1-ms average queues:

- understand the traffic pattern of an application & its impact on the network
- investigate network interference among multiple applications
- identify congested links & culprit applications
- congestion control (control real congestion, not jitters)

The 1 ms averaging operation is actually passing the queueing signal into a low
pass filter with a cut-off frequency of 500 Hz. If we compute the power spectral
density of the 1 us signal & the 1 ms signal, for the 1 us signal, the majority
of the power of the signal concentrates in the low frequency (< 500 Hz) part,
and the 1 ms average signal captures almost all the low-frequency part of the 1
us signal. The 1 ms signal preserves over 97.5% of the power of the 1 us signal.
For 10G networks, if we increase the averaging interval, we start to quickly
lose power & if the averaging interval is smaller than 1 ms, we don't have much
gain. For 1G & 40G networks, the sweet spot averaging intervals are 10 ms, and
250 us respectively. So the ideal averaging interval is inversely proportional
to the link speed of the network: with higher-speed links, the queues will vary
faster & we want to reconstruct the queues more frequently. This averaging
interval is called the reconstruction interval.

Support server A sends a packet to server B through the network, and the two
servers collect the tx & rx timestamps of the packet. Assuming clocks are
synchronized, these two timestamps would tell us the one-way delay of the
packet. Our goal is to breakdown the one-way delay into the individual hops in
the network. Suppose q1, q2, ..., q5 are the 5 queues passed by the packet in
the network: `RX1 - TX1 = q1 + q2 + q3 + q4 + q5 + n1`, where `n1` is a noise
term which models the variable switching delays in the switches as well as the
propagation delays on the wires.

So with this single packet, we have 1 equation for 5 variables. We can gather
many packets & write down all the equations and try to solve for the queues.

The inputs to the algorithm are:

- 5-tuples of packets, for inferring network paths
- Tx, Rx timestamps of packets

From the 5-tuples, we can know the path taken by the packet, and from the
timestamps we can know the one-way delay of the packet. We have:

one way delay = sum of queueing delay over all hops + propagation delay

If we combine all packets, we get a linear system: D = AQ + N, D is a vector of
1-way delays, A is a matrix specifying which packets pass through which
queues, Q is a vector of queueing delays. In factory networks, this linear
system is always undetermined - we don't have enough equations. Since congestion
in network is sparse, the Q vector is sparse, and so we can use the Lasso
estimator to estimate the Q.

Their first attempt was to reconstruct the queueing delays using the data
packets which are the packets generated by the apps. Sometimes the
reconstruction matches the ground truth pretty well, however other times, the
algorithm is attributing the data into the wrong queues. This is because with
only data packets there's not enough equations (paths) compared to the variables
(queues). Even though there's a large number of data packets, many of them are
passing through the same path because packets from the same flow go through the
same path. So the path coverage in the network is not enough.

They introduce a probe mesh:

- each server randomly picks 10 "probing buddies"
- in each reconstruction interval, each server sends 1 probe to each of its
	buddies
- every probe is acked
- overhead is 0.1% of the line rate

We can use a small number of packets to create a dense coverage of paths in the
network.

Their second attempt was to reconstruct with only probe timestamps. The
reconstruction matches ground truths well and the average reconstruction error
is 5.2 KB, which is 3-4 MTU-sized packets.

Lasso solver is iterative, which means it takes time to solve the problem in a
large network. They used a Neural Network to speed up the speed of the Lasso.
Initially, we use Lasso to do the reconstruction, so as the probe timestamps
come in, we feed the probe timestamps to both Lasso & the neural network, and
then we can use the output of Lasso recon result to train the NN. After we have
trained the NN, when new probe timestamps come in, we can then use the NN output
as a recon result. NN is much faster than Lasso since it can be sped up by GPUs.
NN gives us 5k-10k times the speedup without losing much accuracy.

We want to find:

- link utilizations
- whose packets are in the queues?
- whose packets are using the links?

Now they use data packet timestamps too. Now we know the queueing delays for
queues in the network. If we know the tx timestamp of a data packet, we can
simulate this data packet and know where this packet is at any point of time. If
we do this for every data packet, we have a full-on reconstruction of the
queueing dynamics in the network. This is costly because it is a per-packet
operation. In reality, we only need to use the byte counts per flow to do this
reconstruction. Reconstruction is accurate to a couple of MTU sized packets.
They also found that reconstruction of the link utilizations has RMSE within 1%.

They have deployed and tested this algorithm in Google Jupiter 40G testbed with
20 racks and 3-layer network and also much larger network with 10G & 40G links,
access to 12 out of 100s of racks & a 5-layer network. At Stanford, they used a
testbed with 1G links, 128 servers and 2-layer network. They used NetFPGAs for
verification, to get queueing delay ground truths from the network: the idea is
that we use 1 FPGA as two timestampers: a packet will first go to the FPGA, take
a timestamp of it, then the packet will go into the switch and come out of the
switch and go into the FPGA again for a second timestamp. Using the two
timestamps, we can know the ground truth queueing delay. They used 2 FPGA and
got ground truths for 4 different queues in the testbed. They show that the
Lasso recon matches the ground truth very well. In the other testbeds, they use
a cross-validation scheme to verify that their algorithm is giving the correct
results.

Strengths
---------

- Simon employed several techniques to simultaneously achieve precise
	reconstruction & scalability. The work uses probe mesh, which has a very low
	bandwidth overhead (0.1% of bandwidth with 64B probes). Using probe packets,
	they reconstruct the queue length in a network & then use data packets
	timestamps, they decompose the queues & link utilizations on a per-flow basis.
	Finally, they verified the system using NetFPGAs and cross-validation.
- Current edge-based methods obtain only a partial view of the network state and
	some may require non-trivial assistance from switches. This is the first
	application of network tomography to gata centers and for obtaining a
	near-exact reconstruction.
- The work stressed on practicability alongside accuracy & speed of Simon. They
	used a testbed with low-cost switches and 1G network. They also discuss
	pragmatic experience gained from these deployments. Simon makes minimal
	assumptions about the network.

Future Work
-----------

- In the work they implemented the Lasso version of Simon for Linux.
	Hierarchical reconstruction & neural networks are planned to be implemented
	for production environment in the future.
- One could investigate into schemes for path selection during probing (in the
	probe mesh) to efficiently cover the DCN's links more evenly or unevenly,
	depending on some objective, with an adequate number of probes passing through
	each link per unit time to enable a good reconstruction of the link.

