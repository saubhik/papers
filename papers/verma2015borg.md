# Large-scale cluster management at Google with Borg

Abhishek Verma, Luis Pedrosa, Madhukar Korupolu, David Oppenheimer, Eric Tune,
and John Wilkes. 2015. Large-scale cluster management at Google with Borg. In
Proceedings of the Tenth European Conference on Computer Systems (EuroSys '15).
Association for Computing Machinery, New York, NY, USA, Article 18, 1–17.
DOI:https://doi.org/10.1145/2741948.2741964

Google's Borg system is a cluster manager that:

- runs 100s of 1000s of jobs
- from many 1000s of apps
- across a number of clusters
- each cluster having 10s of 1000s of machines

Achieves high utilization by combining admission control, efficient task
packing, over-commitment & machine sharing with process-level performance
isolation.

- Users submit their work to Borg in the form of jobs. A job consists of one or
	more tasks that all run the same program (binary). Each job runs in one Borg
	cell. A Borg cell is a set of machines belonging to a single cluster. A
	cluster lives in a single DC building, and a collection of buildings makes up
	a site.
- Workload: heterogenous with two parts:
	- long-running, highly available, latency-sensitive, end-user facing services
		(e.g. Gmail, Google Docs, web search, BigTable), few us to few 100s of ms,
		diurnal usage patterns. Classified as "prod".
	- batch jobs taking a few secs to a few days to complete, much less sensitive
		to short-term performance fluctuations. Classified as "non-prod".
- Heterogeneous machines in a cell, in many dimensions: CPU, RAM, disk and
	network sizes, processor type, performance, capabilities such as external IP
	address or flash storage. 
- Job's properties include name, owner & number of tasks it has, constraints to
	force tasks to run on machines with particular attributes such as processor
	architecture, OS version, external IP address. A task maps to set of Linux
	processes  A task maps to set of Linux processes.
- Users operate on jobs by issuing RPCs to Borg from a cmdline tool, other
	jobs, or monitoring system. Job descriptions are written in a declarative
	configuration lang, BCL. Jobs can be `submit`ted and `accept`ed to `Pending`
	state, and get `schedule`d to `Running` state, and then `finish` to `Dead`
	state. `fail, kill, lost` leads to `Dead`. `evict` from `Running` leads to
	`Pending` (pre-emption).
- A Borg `alloc` is a reserved set of resources on a machine in which one or
	more tasks can be run. Analogous concept is `pod` in Kubernetes. An alloc set
	is a group of allocs that reserve resources on multiple machines.
	- To set resources aside for future tasks 
	- To retain resources b/w stopping a task & starting it again
	- Gather tasks from different jobs onto same machine - webserver & logsaver
		task (copy server's URL logs from local disk to distributed FS)
- When more work shows up than can be accommodated, they use priorities &
	quota.
	- Every job has a `priority`, a small positive integer, expressing relative
		importance of the job that are running or waiting to run in a cell. A
		high-priority task can obtain resources at the expense of a lower-priority
		one, even if that involves preempting the latter. To prevent preemption
		cascades, they disallow tasks in production priority band to preempt one
		another.
	- Quota decides which jobs to admit for scheduling. It is a vector of
		resource quantities (CPU, RAM, disk, etc.) at a given priority for a period
		of time.  Quota-checking is part of admission control. Over-selling quota
		at lower-priority levels to avoid over-buying quota. Quota allocation is
		outside Borg, and tied to Google's physical capacity planning. User jobs
		are only admitted if they have sufficient quota at the required priority.
- A service's clients use the BNS (Borg Name Service) name to find a task.
	Forms the basis for the task's DNS name:
	`taskID.jobName.userName.cellName.borg.google.com	`. Every task contains a
	built-in HTTP server to publish information about task health & performance
	metrics (e.g. RPC latencies). A UI service (Sigma) provides a dashboard.
- Borg architecture: Logically centralized controller, Borgmaster, and agent
	process called Borglet running on each machine in the cell.
	- Borgmaster: main process + separate scheduler.
		- main process handles client RPCs that mutate state or provide RO access
			to data. Manages state machines for all objects (machines, tasks,
			allocs).  Communicates with Borglets. Offers a backup web UI to Sigma.
			Replicated 5 times for fault tolerance. Paxos leader is the state
			mutator. Periodic checkpointing + change logs for fault tolerance &
			debugging & capacity planning.
		- Job's tasks added to pending queue on submission by Borgmaster. Pending
			queue is scanned from high to low priority, round-robin scheme within a
			priority to ensure fairness across users & avoid HoL blocking, by
			scheduler. Two parts: feasibility checking & scoring.
			- feasibility checking: find machines that meet the task's constraints &
				have enough "available" resources - including resources assigned to
				lower-priority tasks that can be evicted
			- scoring: score each feasible machine based on user-specified
				preferences, & built-in criteria (minimize the no. & priority of
				preempted tasks, pick machines having a copy of the task's packages to
				reduce task startup time, spreading tasks across power & failure
				domains, packing quality). The scoring model tries to reduce amount of
				stranded resources that cannot be used because another resource on the
				machine is fully allocated.
	- Borglet starts & stops tasks, restarts them if they fail, manage local
		resources by manipulating OS kernel settings, rolls over debug logs,
		reports the state of the machine to the Borgmaster & other monitoring
		systems. The Borgmaster polls each Borglet every few secs to retrieve the
		current state & send any outstanding requests.
- To scale, they split the scheduler into a separate process so it could
	operate in parallel with other replicated Borgmaster functions. Separate
	threads to talk to the Borglets & respond to read-only RPCs improve response
	times. More scalability optimizations:
	- score caching: ignore small changes in resource quantities reduces cache
		invalidations.
	- equivalence classes: feasibility checking & scoring for one task per
		equivalence class (identical requirements & constraints).
	- relaxed randomization: examine machines in a random order until enough
		feasible machines to score & select the best.
- A key-design feature for availability is that already-running tasks continue
	to run even if the Borgmaster or a task's Borglet goes down.
- Increasing utilization by a few percentage points can save millions of
	dollars. "Cell compaction" is chosen as utilization metric: given a workload,
	how small a cell it could be fitted into? Better scheduling policies require
	fewer machines to run on the same workload.
	- Cell sharing: segregating prod & non-prod work would need more machines
		because prod jobs usually reserve resources to handle rare workload spikes
		but don't use these resources most of the time. Borg's resource reclamation
		run non-prod work using reclaimed resources. The CPU slowdown (increase in
		CPI) by packing unrelated users & job types onto the same machine is
		outweighed by decrease in machines required.
	- Large cells: Allows large computations, & decrease resource fragmentation.
	- Fine-grained resource requests: Request CPU in milli-cores, and memory &
		disk-space in bytes (core = processor hyperthread). Offering fized-size CPU
		& memory would require more machines.
	- Resource reclamation: A job specifies a resource limit - to determine if
		user has enough quota for admission. Borgmaster estimates how much
		resources a task will use (reservation) every few seconds based on usage
		information captured by Borglet & reclaim the rest for batch work. This
		reduces the number of machines used.  Reservation - Usage = Safety Margin.
		Too less safety margin leads to OOMs.
- They use a Linux chroot jail as the primary security isolation mechanism
	between multiple tasks on the same machine & VMs & security sandboxing
	techniques are used to run external software by Google's AppEngine & Google
	Compute Engine. 
- Borg tasks run inside a Linux cgroup-based resource contained & Borglet
	manipulates the container settings, giving improved control.
	- Borg tasks have an `appclass`: latency-sensitive (LS) & batch.
		High-priority LS tasks receive best treatment.
	- Compressible (CPU cycles, disk I/O bandwidth) & non-compressible resources
		(memory, disk): if a machine runs out of non-compressible resources,
		Borglet immediately terminates tasks from lowest to highest priority; if a
		machine runs out of compressible resources, the Borglet throttles usage
		(favoring LS tasks) so that short load spikes can be handled without
		killing any tasks.
	- To reduce scheduling delays, their version of CFS uses extended per-cgroup
		load history, allows preemption of batch tasks by LS tasks, reduces
		scheduling quantum when multiple LS tasks are runnable.


## Strengths

- Throughout the design they gave importance to debugging (instrospection) by
	surfacing debugging information to all users rather than hiding it. To handle
	the enormous volume of data, they provide several levels of UI & debugging
	tools so users can quickly identify anomalous events related to their jobs &
	then drill down to detailed event & errors logs from their applications &
	infrastructure itself.
- Another important part of managing large scale clusters is automation &
	operator scaleout: Borg's design allows them to support 10s of 1000s of
	machines per operator (SRE).
- The qualitative lessons they learned from operating Borg in production for
	more than a decade were incorporated in Kubernetes which has become extremely
	popular now:
	- allocs are useful: allows helper services to be developed by separate teams
		& this abstraction spawned the widely-used logsaver pattern &
		data-loader+webserver pattern.
	- cluster management is more than task management: apps on Borg benefit from
		other cluster services such as naming & load balancing, apart from
		lifecycle management of tasks & machines.
	- master is the kernel of a distributed system: although originally built as
		a monolithic system, Borgmaster became a kernel sitting at the heart of an
		ecosystem of services that cooperate to manage user jobs: scheduler, UI
		(Sigma), admission control, vertical & horizontal auto-scaling, re-packing
		tasks, periodic job submission, workflow management, archiving system
		actions for offline querying.  Affording this scaling of workload & feature
		set without sacrificing performance, scalability & maintainability is
		hallmark of a good design.

## Weaknesses

- The only form of data locality supported by the Borg scheduler is sharing &
	caching immutable packages used by different tasks. The scheduler doesn't
	take into account low-level resource interference: such as memory bandwidth
	contention or L3 cache pollution. Maybe the scheduler can be further
	improved.
- As discussed in the paper:
	- Jobs are restrictive as the only grouping mechanism for tasks: no way to
		manage multi-job service as a single entity or related instances of a
		service (canary & production tracks). K8s solves this by using `labels` -
		arbitrary key-value paris that user can attach to any object in the system.
	- One IP address per machine complicates things: Borg needed to schedule
		ports as a resource, assign ports to tasks, enforce port isolation & RPC
		systems needed to handle ports as well as IP addresses. K8s uses Linux
		namespaces, VMs, IPv6 & SDN to give an IP address to every pod & service.
	- Optimizing for power users at the expense of casual ones: the BCL
		specification lists about 230 parameters & makes it harder for the casual
		user to use Borg.
- Borg, as described in this paper, is only suitable for Google's workloads and
	Google's machines. The design choices that affected their system are
	extremely Google-specific. To cite an instance: the vast majority of the Borg
	worklaod does not run inside VMs - a reason being the system was designed at
	a time when Google had made a considerable investment in processors with no
	virtualization support in hardware. But of course, the paper presents many
	ideas to build such a cluster management system.
- Not enough motivation (quantitatively) provided for choosing "cell
	compaction" as the utilization metric for Borg's design. They just say that
	they picked this metric after much experimentation and the details are
	avoided. They mention cell compaction gives a fair, consistent way to compare
	scheduling policies.

## Future Work

- As discussed above, work continues in improving the scheduler. Adding thread
	placement & CPU management that is NUMA-, hyperthreading-, and power-aware &
	improving the control fidelity of the Borglet.
- Even though K8s is being actively developed, maybe rewriting the BCL to
	support a simpler API for casual users might be a potential future work.

