# FairCloud: Sharing the Network in Cloud Computing

In cloud computing, networks are shared in a best-effort manner making it hard
for both tenants & cloud providers to reason about how network resources are
allocated. The reason networks are more difficult to share is because the
network allocation of a VM X depends not only on the VMs running on the same
machines as X, but also other VMs that X communicates with and the cross-traffic
on each link used by X.

The work identifies the desirable requirements for bandwidth allocation across
multiple tenants:

- min-guarantee: provide a minimum absolute bandwidth guarantee for each VM.
	This is key for achieving predictable app performance.
- high utilization: do not leave network resources underutilized when there is
	unsatisfied demand. Important for throughput-sensitive apps like MapReduce.
- network proportionality: share bandwidth between tenants based on their
	payments, like CPU & memory resources.

Fully utilized links are termed as congested links.

There is a hard trade-off between achieving network proportionality & providing
each VM a useful bandwidth guarantee. Given a network proportional allocation, a
tenant can arbitrarily reduce another tenant's bandwidth by increasing the
number of VMs communicating with a VM. 

Even in the absence of the min-guarantee requirement, there is a tradeoff
between network proportionality and high utilization. This is because a tenant
might be disincentivized to use an uncongested path due to decrease in the
tenant's network propotional allocation along a congested link. This hurts
overall network utilization. In other words, there are no utilization incentives
for such network proportional allocation.

- Congestion Proportionality: network proportionality restricted to congested
	paths that involve more than one tenant. But even here, a tenant can modify
	her demand to get a higher allocation & decrease system utilization - i.e. not
	strategy proof.
- Link Proportionality: network proportionality restricted to a single link. The
	only constraint is that the weight of any tenant K on a link L is the same for
	any communication pattern between K's VMs communicating over L and any
	distribution of the VMs as sources and destinations. Since allocation is
	independent across different links, this can achieve high utilization.

Traditional allocation properties don't work.

- Per-flow fairness can lead to unfair allocations at VM granularity by
	instantiating more flows.
- Per-SD (source-destination pair): each SD pair is allocated an equal share of
	a link's b/w regardless of the number of flows between them. Not
	communication-pattern independent: many-to-many gives O(n^2) b/w share,
	one-to-one gives O(n) b/w share.
- Per-source & Per-destination: fair to either sources or destinations, but not
	fair to the other. This is asymmetry. Neither provides min-guarantee - one can
	arbitrarily reduce another's.

Network sharing properties:

- Work conservation: A link is either fully allocated, or it satisfies all
	demands.
- Strategy-proofness: Tenants cannot improve their allocations by lying about
	their demands.
- Utilization incentives: Restricted form of strategy-proofness. Tenants are
	never incentivized to reduce their actual demands on uncongested paths or to
	artificially leave links underutilized.
- Communication-pattern independence: allocation of a VM depends only on the VMs
	it communicates with & not on the communication pattern.
- Symmetry: Switching the directions of all the flows in the network, then the
	reverse allocation should match the forward allocation. Different apps value
	one direction over the another.

Three allocation policies in the tradeoff space:

- PS-L, Proportional Sharing at Link-level: Each switch implements a WFQ
	(weighted fair queueing) and has one queue for each tenant. The weight of the
	queue for tenant A on link L is the sum of the weights of A's VMs that
	communicate over the link L. One can use weight for A to be total weights of
	all A's VMs or apply PS-L at a per VM granularity to remove incentives to send
	traffic between all of one's VMs. Not strategy-proof.
- PS-N, Proportional Sharing at Network-level: Communication between the VMs in
	a set has the same total weight through the network irrespective of the
	communication pattern between the VMs. PS-L can be extended to incorporate
	information regarding the global communication pattern of a tenant's VMs.
	Drawback is each VM's weight is statically divided across the flows with other
	VMs irrespective of traffic demands. Lacks utilization incentives.
- PS-P, Proportional Sharing on Proximate Links: Offers useful min b/w
	guarantees (no network proportionality forms as above two). Prioritizes VMs
	close to a given link: per-source fair sharing for traffic towards root of the
	tree (core) & per-destination fair sharing for traffic from the root (core).
	Can be implemented per tenant.

The above policies can be deployed with:

- full switch support: each switch must provide a number of queues >= the number
	of tenants communicating through it & support WFQ.
- partial switch support: Implementation using CSFQ (core stateless FQ).
- no switch support: hypervisor-only implementations, either centrallized
	controller-based  enforcing rate-limiters at hypervisors based on current
	network traffic or distributed mechanism like Seawall.

The work evaluated the proposed allocation policies using simulation & a
software switch implementation, through hand-crafted examples and traces of
MapReduce jobs from a production cluster.

## Strengths

- The work provides a rigorous formal framework and unifies several published
	works in solving the challenge of network allocation in data centers. They
	identify 3 main requirements: min-guarantee, proportionality, and high
	utilization. Also, they extract the low-level desirable properties behind the
	tradeoffs, and formally define them.
-	They propose 3 different allocation policies that navigate the tradeoff space
	giving cloud providers a variety of VM pricing models: from flat-rate per VM
	to per-byte pricing models. These policies can be fundamental building blocks
	for more complicated allocation policies such as providing guarantees and
	shares proportionally only the bandwidth unused by guarantees.

## Weaknesses

- The work utilizes hand-crafted examples, and use them both for motivation and
	evaluation of some desirable properties. For example: emphasis on tenants
	underutilizing uncongested paths is the basis of utilization incentives - but
	this might be just one of the many possible scenarios for underutilization in
	data centers. Another is apply PS-L at VM granularity to fix the problem of a
	tenant trying to increase her allocations by sending traffic between all of
	one's VMs. The desirable properties are not a complete set by any means, but a
	real-world example motivating the need to consider some of them is lacking.

## Future Work

Many possible areas of future work: 

- The refinement of allocation policies is the biggest one and evaluation of a
	real-world deployment of such a policy. Specifically, selecting suitable
	values for the parameters of PS-P to generalize it to other topologies such as
	BCube or DCell.
- Hypervisor-only deployment for the policies described.
- Improve PS-N to incorporate utilization incentives by not providing any weight
	to flows travelling uncongested paths.
- Find a work-conserving bandwidth allocation policy that is strategy-proof.
	This paper deals with utilization incentives: a restricted version of strategy
	proofness.

