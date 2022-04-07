# Scaling Distributed Machine Learning with In-Network Aggregation

Distributed ML training is increasingly a network-bound workload. The work
considers data-parallel training, where the input data is partitioned across
workers, focussing exclusively on widely-used distributed synchronous SGD. The
challenge is that data-parallel SGD requires computing the sum of model updates
across all workers after every iteration. Each model update has as many
parameters as the model itself, and models are growing exponentially. Today,
they exceed 32 GB. Performance bottleneck in distributed training is shifting
from compute to communication due to:

- Advancements in GPUs and other compute accelerators. The pace of performance
  improvements in GPUs far exceeds the improvement in Ethernet speeds (network
  bandwidth).
- Ratio of communication to computation in the workloads has shifted. DNNs are
  becoming larger. This is application-dependent.

Today's ML toolkits implement this communication phase in one of two ways:

- The parameter server approach: workers compute model updates and send them to
  PSs. PSs are dedicated machines which aggregate updates to compute &
  distributed the new model parameters. The model is sharded over multiple PS
  nodes.
- The all-reduce approach: workers communicate over an overlay network. RAR,
  ring all-reduce, where each worker communicates to the next neighboring worker
  on the ring, is common because it is bandwidth-optimal.

Even at 100 Gbps, DeepLight, LSTM, NCF, and BERT spend 17% of their batch time
in communication. When GPUs become faster, network performance will be a serious
issue event at 100 Gbps.

The work proposes an alternative approach to model update exchange for ML
workloads using in-network aggregation (INA). Workers send their model updates over
the network where an aggregation primitive sums the updates and distributes only
the resulting value.

The fundamental advantage of INA over PS & all-reduce is that:

- it achieves minimum possible latency and the minimum possible communication
  cost (data bytes each worker sends and receives).
- avoids eng-host processing required for aggregation & hence provides sub-RTT
  latency

Even though techniques like gradient compression can reduce the data volume of
model updates, it is not necessarily superior to INA.

- The computational cost of compression and decompression is non-negligible & in
  some cases, it outweighs the communication-reduction benefits.
- Higher levels of compression either requires more training iterations to
  converge, or hurts the accuracy of the resulting models.

The proposed system, SwitchML, implements the aggregation primitive in a
programmable dataplane switch. They solve the challenges of limited computation
& storage capabilities in switches. The system must also tolerate packet loss,
since the DNN training jobs are long-running.

SwitchML uses the following techniques:

- Combined switch-host architecture: Switch performs integer aggregation, while
  end-hosts manage reliability & perform more complex computations.
  
  - A switch provides a pool of `s` integer aggregators, addressable by index.
    Each slot in the pool aggregates a vector of `k` integers, which are
    delivered all at the same time in one update packet. The division op is done
    the end-host. A packet `p` carries a pool index (to identify the
    aggregator), and a vector of `k` integers to be aggregated. Upon rx, the
    switch aggregates `p.vector` into the slot `p.idx`. Once the slot has
    aggregated vectors from each worker, the switch then multicasts the result
    to each worker. The pool-based design:
    - addresses limited switch memory, by not storing entire model update in
      switch, instead aggregates in streaming fashion
    - to maintain high forwarding rate, programmable switches parse only upto
      a certain amount of bytes. The model-update vector & all other packet
      headers must fit in parsed portion.
  
  - Worker controls which vector they send to which pool `idx` and since pool
    size `s` is limited, how they reuse slots. Every worker uses the same slot
    for the same piece of model update, and no slot can be simultaneously used
    for two different pieces. Every worker must work on the same slot at roughly
    the same time to avoid long synchronization delays. Each worker initially
    sends `s` packets, each with `k` from model update U, and then waits for the
    result from the switch. After consuming the aggregated result, the worker
    sends a new packet with the next piece of `k` parameters for the same pool
    slot.
    - Doesn't require explicit coordination among workers because the mapping
      between model updates, slots and packets is deterministic.
    - The communication scheme is self-clocked after the initial `s` packets.
      When a slot is completed, the packets from the switch to the workers
      serve as flow-control acknowledgements that the switch is ready to reuse
      the slot, and the workers are free to send another packet.

- Pool-based streaming aggregation: SwitchML streams aggregation through the
  switch: it processes the aggregation function on a limited number of vector
  elements at once. For this, they use a pool of integer aggregators. The
  end-hosts manage these aggregators in the switch.

- Fault-tolerant protocols: To recover from packet loss.

  - Tolerate packet loss by retransmitting lost packets. Packet loss detection
    is done by workers if they do not receive response before a timeout. Two
    additional pieces of switch state for correctness:
    - maintain information as to which workers have already contributed updates
      to a given slot (`seen[2][s][n]` for `n` workers). This is to ignore
      duplicate retransmissions.
    - maintain a shadow copy of the previous result for each slot
      (`pool[2][s]`). Allows switch to retransmit a dropped result packet for a
      slot even when switch has started reusing the slot for next chunk. Workers
      alternate the single-bit pool version (`p.ver`) in each update packet.
  - Keeping shadow copy doubles the memory requirement, and tracking the `seen`
    bitmask adds additional cost But the total number of slots needed is <10% of
    switch's memory capacity (tuned based on network bandwidth-delay product).

- Quantized integer-based aggregation: SwitchML converts floating-point values
  to 32-bit integers using a block floating-point like approach.

  - They combine 32-bit fixed-point addition in the switch with adaptive scaling
    on the workers. The scaling factor is set so that the max aggregated
    floating point value within a block of `k` gradients is still representable
    as a 32-bit fixed point value. The workers need to agree on a global value
    of `m`, a scaling parameter - they devise a simple lookahead strategy.
  - Also explored the implementation of a restricted form of 16-bit floating
    point. Switch convertes each 16-bit float value into fixed-point value to
    aggregate & then converts back to float before sending results.

- They support larger packets through recirculation: sending packets through the
  switch pipelines multiple times. This leads to better bandwidth efficiency due
  to more integer elements in each packet to offset the network framing
  overhead.

- They support RDMA since using even DPDK & multiple cores cannot lead to
  100Gbps throughput due to packet processing overhead. They use RoCE v2 in UC
  mode & rely on SwitchML's reliability but retransmissions use multi-packet
  messages. To balance packet processing offload & retransmission cost they use
  small, multi-packet message (16 packets).

They benchmark SwitchML against state-of-the-art all-reduce communication
libraries Gloo & NCCL. SwitchML outperforms NCCL in aggregated tensor elements
per unit of time (ATE/s). Also, they found SwitchML provides significant
speedups in training batch-processing speedup compared to NCCL backend of
PyTorch & TensorFlow. The four network-bottlenecked DNNs at 100Gbps (DeepLight,
LSTM, NCF, and BERT) provide speedups of upto 2.27x over NCCL-RDMA and 5.55x
over NCCL-TCP.

## Strengths

- SwitchML speeds up DNN training by minimizing communication overheads at
  single-rack scale. Even though the paper described SwitchML in the context of
  a rack, the design can scale to multiple racks by hierarchically composing
  several instances of the switch logic. Easy extensibility is the hallmark of a
  good design. Another extension is to use the design to create a dedicated
  "parameter aggregator" on a standard server with an advanced network
  attachment.
- SwitchML builds on programmable network hardware which gives two benefits:
  - operators can deploy a single switch model either for SwitchML or
    traditional networking: the ALUs can be repurposed for other tasks.
  - SwitchML allows the system design to evolve to support new ML training
    approaches, e.g. new floating-point representations.

## Future Work

- Experimenting with new floating-point representations and protocols for sparse
  vector aggregations.
- SwitchML slows down past the 150ms mark with 1% loss applied on every link
  because some slots are unevenly affected by random losses and SwitchML does
  not apply any form of work-stealing to rebalance the load among aggregators.
  This is a future opportunity for optimization.
