# Internet Computer Storage Protocol
- Autoscaling Storage
- Self Cycle Monitor
- One step store, two steps get

# RoadMap
- Q2 MVP Version Release : 0.01
- Q3 Support HTTP

# Service Interface
## ISP Canister

```motoko
    // get storage bucket from key
    get : query (key : Text) -> async Result.Result<Principal, ()>;
    // get current buckets
    getBuckets : query() -> async (LiveBucketExt, [Principal]);
    // store key & value into bucket
    store : shared(args : StoreArgs) -> async ();
```

## Bucket Canister

```motoko
    // get value from key
    get : query (key : Text) -> async Result.Result<Blob, ()>;
    // store key and value
    store : shared(args : StoreArgs) -> async ();
```

# Architecture
![avatar](ISP.jpeg)
