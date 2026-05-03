# MetalLB

## Mode

Layer 2

## IP Pool (Example)


192.168.X.240-192.168.X.250


## Files

- ip-pool.yaml
- l2-advertisement.yaml

## Requirements

All nodes must allow asymmetric routing:


rp_filter = 0


## Common Issues

- IP reachable from only one node → speaker not running on all nodes
- curl works but ping fails → expected behavior
