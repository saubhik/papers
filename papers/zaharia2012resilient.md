# Resilient Distributed Datasets: A Fault-Tolerant Abstraction for In-Memory Cluster Computing

*Paper:* [Matei Zaharia, Mosharaf Chowdhury, Tathagata Das, Ankur Dave, Justin Ma, Murphy McCauley, Michael J. Franklin, Scott Shenker, and Ion Stoica. 2012. Resilient distributed datasets: a fault-tolerant abstraction for in-memory cluster computing. In Proceedings of the 9th USENIX conference on Networked Systems Design and Implementation (NSDI'12). USENIX Association, USA, 2.](https://dl.acm.org/doi/10.5555/2228298.2228301)

<!---
Contents:
- [x] Introduction
- [x] RDDs
    - [x] RDD Abstraction
    - [x] Spark Programming Interface
        - [x] Example: Console Log Mining
    - [x] Advantages of the RDD Model
    - [x] Applications not suitable for RDDs
- [x] Spark Programming Interface
    - [x] RDD Operations in Spark
    - [x] Example Applications
        - [x] Logistic Regression
        - [x] Page Rank
- [ ] Representing RDDs
- [x] Implementation
    - [x] Job Scheduling
    - [x] Interpreter Integration
    - [x] Memory Management
    - [x] Support for Checkpointing
- [x] Evaluation
    - [x] Iterative ML Apps
    - [x] Page Rank
    - [x] Fault Recovery
    - [x] Behavior with Insufficient Memory
    - [x] User apps built with Spark
    - [x] Interactive Data Mining
- [x] Discussion
    - [x] Expressing Existing Programming models
    - [x] Leveraging RDDs for debugging
- [x] Related Work
- [x] Conclusion
-->

RDDs are a distributed memory abstraction that lets programmers perform in-memory computations on large clusters in a fault tolerant manner.

#### Issues motivating Spark
* For reusing data between computations, frameworks such as MapReduce, write the data to an external stable storage system, incurring data replication cost, low disk I/O, serialization costs. This is bad for apps requiring data reuse, e.g. iterative machine learning algorithms (such as Logistic Regression, Page Rank) & interactive data mining tools. Cluster computing frameworks at the time provided abstractions for accessing a cluster's computational resources but lack abstractions for leveraging distributed memory.
* Define a programming interface that can provide fault tolerance efficiently. Interfaces based on fine-grained updates to mutable state require data replication or logging updates across machines for fault tolerance. This requires copying large amounts of data over the network. Instead, RDDs log coarse-grained transformations like map, filter, join to provide fault tolerance rather than actual data.

#### Definitions
*RDDs* are read-only, in-memory, parallel, partitioned data structures that can only be created through deterministic transformations on data in stable storage or other RDDs. RDD stores metadata about its lineage to be able to compute its partitions from data in stable storage. A *transformation* is a lazy operation that defines a new RDD. *Actions* are operations that return a value to the application or materialize data to stable storage, e.g. count, collect, save. RDDs are computed lazily only when used in an action. Spark provides language-integrated API where each RDD is an object, and transformations are object methods.

#### Why not use a DSM (Distributed Shared Memory) system instead?
RDDs provide advantages compared with DSM.

* Applications in DSM systems read & write to arbitrary locations in the global address space. RDDs allow only bulk writes, and hence suited for batch analytics. This makes fault tolerance efficient by not having to checkpoint & rollback the entire application in-memory state, and instead recover by recomputing the lost partition of the RDD using the lineage metadata.
* Can run backup tasks as RDDs are immutable. Backup tasks are hard to implement in DSMs as updates to the same memory location by different copies could lead to incorrect state.
* Spark runtime can schedule tasks based on data locality in RDDs for performance, not possible in DSM.
* Graceful Degradation: When out of memory, RDDs can be stored on disk & provide similar performance as data-parallel systems.

#### Representing RDDs
RDDs are represented in a graph-based manner to support a rich set of transformations. RDDs expose five pieces of information.

* set of partitions
* set of dependencies on parent RDDs
* function for computing the dataset based on its parents
* metadata about its partitioning scheme (hash/range partitioned)
* metadata about data placement (fast access due to data locality)

In a job with many iterations, it may be necessary to reliably replicate some of the versions of the RDDs to reduce fault recovery times. RDDs allow users to control the persistence and the partitioning of the RDDs. Specifying persistence leads to efficient fault recovery. Spark provides three options for storage of persistent RDDs: in-memory storage as deserialized Java objects, in-memory storage as serialized data, and on-disk storage. Specifying consistent partitioning across iterations can optimize the communication across nodes, and improve run-time.

*Challenge:* How to represent dependencies between RDDs in this graph-based interface?
We can classify dependencies into two types.

* narrow dependencies: each partition of parent RDD used by at most one partition of child RDD
* wide dependencies: each partition of parent RDD used by multiple partitions of child RDD

Two reasons for this classification.

* narrow dependencies allow for pipelined execution on one node which can compute all parent partitions, but wide dependencies require data from all parent partitions to be available & communicated across nodes in a MapReduce fashion.
* fault recovery is faster with a narrow dependency because only the lost parent partitions need to be recomputed, whereas for wide dependencies, a single failed node might cause loss of some partition from all ancestors of an RDD, requiring a complete re-execution. Checkpointing to stable storage is useful for fault recovery of RDDs with long lineage chains and wide dependencies. This can avoid full recomputations. For RDDs with short lineage chains, checkpointing may not be worthwhile. The decision of checkpointing is left to the user.

This graph-based interface makes it easy to implement new transformations without interfering with the scheduler. Spark is implemented in about 14,000 lines of Scala, and runs over the Mesos cluster manager. The scheduler assigns tasks to machines based on data locality. For wide dependencies, the intermediate records are materialized on the nodes holding parent partitions to simplify fault recovery, like MapReduce materializes map outputs.

#### Benefits of the RDD abstraction
* Spark supports interactive data mining due to low-latency in-memory design. Two changes were made to the Spark interpreter: class shipping & modified code generation. Class shipping is letting the worker nodes fetch the bytecode for the classes created on each line, served by the interpreter over HTTP. Also, the code generation logic is modified to trace the object graph to ship the classes wrapping a variable defined on a previous line. Due to the low-latency of in-memory data operations, Spark lets users query big datasets interactively.
* Many parallel programs naturally apply the same operation to multiple records making them easy to express. RDDs can express many cluster programming models: MapReduce, DryadLINQ, SQL, Pregel, HaLoop, interactive data mining. This allows users to compose these models in one program & share data between them, e.g. run a MapReduce operation to build a graph, then run Pregel on it. For example, MapReduce can be expressed using the flatMap and groupByKey operations in Spark.
* Logging the lineage of RDDs created during a job can be useful for a debugger, as it has virtually zero recording overhead compared to traditional replay debuggers for general distributed systems which captures order of events across multiple nodes.

#### Evaluation
* The paper evaluates Spark and RDDs on Amazon EC2 (4 cores with 15 GB of RAM), and show that Spark outperforms Hadoop by upto 20x in iterative machine learning and graph applications, due to speedup from avoiding low disk I/O and deserialization costs by storing data in memory as Java objects. Spark can query a 1 TB dataset interactively with latencies of 5-7 seconds, whereas querying from disk took 170s.
* They compare the performance of Hadoop, HadoopBinMem, and Spark with logistic regression and k-means. HadoopBinMem is a Hadoop deployment that converts the input data into a low-overhead binary format in the first iteration to eliminate text parsing in later iterations, and stores it in an in-memory HDFS instance. The results show that sharing data via RDDs speeds up future iterations. This is due to:
    * minimum overhead of the Hadoop stack
    * overhead of HDFS while serving data
    * deserialization cost to convert binary records to usable in-memory Java objects
* They also compared the performance of Spark with Hadoop for PageRank using a 54 GB Wikipedia dump & achieved 7.4x speedup over Hadoop on 30 nodes.

## Strengths & Weaknesses
#### Strengths
* The paper provides a useful data sharing abstraction through RDDs that wasn't provided by cluster computing frameworks at the time. This enables more broader classes of applications such as iterative machine learning algorithms and interactive data mining. Frameworks such as MapReduce provided abstractions for accessing computational resources in a cluster, but not distributed memory. For reusing data between computations, these frameworks relied on writing to external stable storage incurring overheads due to replication, disk I/O and serialization costs. Making RDDs immutable, they solve the consistency issue by design.
* The Spark system allows a general-purpose programming language, Scala, to be used at interactive speeds for in-memory data mining on clusters. Indeed, the authors let users run Spark interactively from the interpreter to query big datasets.
* A key advantage of RDDs is efficient fault recovery mechanisms by avoiding checkpointing of entire in-memory state in contrast Distributed Shared Memory (DSM) systems. Users can specify the persistence of RDDs, and only the lineage graphs for the RDDs is logged, which are many order of magnitude smaller than entire application state. Another advantage is leveraging data locality to send computations to the nodes with the data.
* The transformations and actions supported are rich enough to express a wide range of batch analytics applications, even though it might seem counter-intuitive as only coarse-grained transformations are supported on RDDs. This required recognizing the common computations employed in batch analytics applications and abstracting them out to support them on RDDs. This expressivity of the RDD abstraction is a big part of the reason of Spark's popularity. Indeed, they show in the paper that RDDs can easily express a wide range of parallel applications in a few lines of code.

#### Weaknesses
* Spark is best suited for batch analytics, but not for asynchronous application requiring fine-grained modifications to distributed state. For example, storage system for a web application or an incremental web crawler. These applications require systems with traditional update logging and data checkpointing mechanisms, e.g. databases, RAMCloud, Percolator, Piccolo.
* Spark relies on the user for specifying the persistence and optimize data placement. This makes it less accessible to a broader audience. Indeed, the authors mention that they are investigating automatic checkpointing mechanisms. This is because the Spark scheduler knows best the size of each dataset as well as the computation time of the dataset, and so it should be able to select an optimal set of RDDs to checkpoint to minimize system recovery time. Leveraging data locality can also be done by the scheduler by scheduling tasks on the right nodes.

## Follow-Up
* Some immediate follow-up ideas to extend Spark would be:
  * tolerating scheduler failures by replicating the RDD lineage graph
  * automatic checkpointing (mentioned above), determined by the scheduler
  * automatic data placement mechanisms, determined by the scheduler
* Another extension of RDDs could be to let the users control the granularity of the data partitions in an RDD, to support even broader class of applications beyond batch analytics. Then it would be possible to combine asynchronous applications that make fine grained updates to shared state with batch analytics applications. This would make RDD a more general Distributed Shared Memory (DSM) systems by allowing read/write to each memory location instead of allowing just bulk writes. But this could mean employing more expensive fault tolerant mechanisms, but there could be applications which could make the tradeoff worthwhile. This brings the advantages of using RDDs (straggler mitigation through backup tasks, work placement leveraging data locality, and graceful degradation when out of memory) to DSM systems.

---
