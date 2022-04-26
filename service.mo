import Result "mo:base/Result";
module {

    type LiveBucketExt = {
        canister_id : Principal;
        used_memory : Nat;
        retiring : Bool;
    };

    type StoreArgs = {
        key : Text;
        value : Blob;
    };

    type ISP = actor{
        get : query (key : Text) -> async Result.Result<Principal, ()>; // get storage bucket from key
        getBuckets : query() -> async (LiveBucketExt, [Principal]); // get current buckets
        store : shared(args : StoreArgs) -> async (); // store key & value into bucket
    };

    type Bucket = actor{
        get : query (key : Text) -> async Result.Result<Blob, ()>;
        store : shared(args : StoreArgs) -> async ();
    };

}