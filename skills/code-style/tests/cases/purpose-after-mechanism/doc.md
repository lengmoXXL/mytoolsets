etcd replicates every write through Raft and streams changes over a watch
API, which is what makes it a cluster's shared configuration store.
