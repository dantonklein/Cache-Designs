# Cache-Designs
8-way set-associative cache with a pseudo-lru replacement policy and pipelined cache hits. It has a ram interface with burst reading/writing. 

First I made a parameterized direct-mapped implementation to teach myself the general behavior of a cache. I was able to figure out the state machine and the ram-cache interface in this first version. I also figured out the pipelined cache hits.

I followed that up with a 8 entry fully-associative design that allowed me to learn the LRU replacement policy. I went with a tree-based pseudo LRU policy as that seems to be pretty commonly used in practice.

The ultimate goal was to make an 8-way set-associative cache, which was pretty easily achieved after finishing the fully-associative cache. Fusing both concepts from the first two cache designs into one, pretty awesome.