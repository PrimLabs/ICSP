import Types "Lib/Types";
import Cycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import TrieMap "mo:base/TrieMap";
import TrieSet "mo:base/TrieSet";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Hash "mo:base/Hash";
import Blob "mo:base/Blob";
import Bucket "Bucket";
import A "Lib/Account";
import U "Lib/Utils";

shared(installer) actor class isp()  = this {
    private type StoreArgs           = Types.StoreArgs;
    private type BucketInterface     = Types.BucketInterface;
    private type LiveBucket          = Types.LiveBucket;
    private type LiveBucketExt       = Types.LiveBucketExt;
    private type Management          = Types.Management;
    private type LEDGER              = Types.LEDGER;
    private let RETIRING_THRESHOLD   = 5905580032; // 5.5 G
    private let CYCLE_SHARE          = 14_000_000_000_000;  // cycle share each bucket created
    private let CYCLE_BUCKET_LEFT    = 1_000_000_000_000;
    private let CYCLE_THRESHOLD      = 16_000_000_000_000; //  658368000000 Cycle :  2G / Month
    private let CYCLE_MINTING_CANISTER = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
    private let Ledger : LEDGER = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");
    private let TOP_UP_CANISTER_MEMO = 0x50555054 : Nat64;
    private let ADMIN : Principal    = installer.caller;

    // storage buckets map :
    private stable var buckets_entries : [var (Principal, TrieSet.Set<Text>)] = [var];
    private var buckets : TrieMap.TrieMap<Principal, TrieSet.Set<Text>> = TrieMap.fromEntries<Principal, TrieSet.Set<Text>>(buckets_entries.vals(), Principal.equal, Principal.hash);

    // init live bucket and living bucket at present
    private stable var liveBucket : LiveBucket = {
        var bucket : BucketInterface = actor("aaaaa-aa");
        var used_memory = 0;
        var retiring = false;
    };

    public query({caller}) func get(key : Text) : async Result.Result<Principal, ()>{
        for((p, keys) in buckets.entries()){
            if(TrieSet.mem<Text>(keys, key, Text.hash(key), Text.equal)){
                return #ok(p)
            }
        };
        return #err(())
    };

    public query({caller}) func getBuckets() : async (LiveBucketExt, [Principal]){
        assert(caller == ADMIN);
        let res = Array.init<Principal>(buckets.size(), Principal.fromActor(this));
        var index = 0;
        for(p in buckets.keys()){
            res[index] := p;
            index += 1;
        };
        (
            {
                canister_id = Principal.fromActor(liveBucket.bucket);
                used_memory = liveBucket.used_memory;
                retiring = liveBucket.retiring;
            },
            Array.freeze<Principal>(res)
        )
    };

    public shared({caller}) func init() : async (){
        if(Principal.fromActor(liveBucket.bucket) == Principal.fromText("aaaaa-aa")){
            await createNewBucket()
        };
    };

    public shared({caller}) func store(args : StoreArgs) : async (){
        ignore await liveBucket.bucket.store(args);
        if(_changeLiveBucketState(args.key, args.value.size()) and (not liveBucket.retiring)){
            liveBucket.retiring := true;
            ignore await createNewBucket();
        };
    };

    public shared({caller}) func createNewBucket() : async (){
        if (caller != Principal.fromActor(this) or caller != ADMIN) return;
        Cycles.add(CYCLE_SHARE);
        let nb = await Bucket.Bucket();
        liveBucket.bucket := nb : BucketInterface;
        liveBucket.used_memory := 0;
        liveBucket.retiring := false;
    };

    public shared({caller}) func topUp(amount : Nat) : async Result.Result<Text, Text> {
        if (caller != Principal.fromActor(this) or not isBucket(caller)) return #err("PermissionDenied");
        let default = Blob.fromArrayMut(Array.init<Nat8>(32, 0:Nat8));
        let subaccount = Blob.fromArray(U.principalToSubAccount(Principal.fromActor(this)));
        let cycle_ai = A.accountIdentifier(CYCLE_MINTING_CANISTER, subaccount);
        switch(await Ledger.transfer({
            to = cycle_ai;
            fee = { e8s = 10_000 };
            memo = TOP_UP_CANISTER_MEMO;
            from_subaccount = ?default;
            amount = { e8s = 10_000_000 }; // 0.1 icp
            created_at_time = null;
        })){
            case(#Ok(block_height)){
                await Ledger.notify_dfx(
                    {
                            to_canister = CYCLE_MINTING_CANISTER;
                            block_height = block_height;
                            from_subaccount = ?default;
                            to_subaccount = ?subaccount;
                            max_fee = { e8s = 10_000 };
                    }
                );
                #ok("top up successfully")
            };
            case(#Err(e)){
                #err(debug_show(e))
            };
        }
    };

    // bucket call back function : top up to bucket
    public shared({caller}) func topUpBucket(amount: Nat) : async (){
        switch (buckets.get(caller)) {
            case null { return; };
            case (_) {
                if (amount > Cycles.balance()) return;
                let management: Management = actor("aaaaa-aa");
                Cycles.add(amount);
                ignore await management.deposit_cycles({ canister_id = caller });
            };
        }
    };

    public shared func wallet_receive() : async Nat{
        Cycles.accept(Cycles.available())
    };

    // true : need to create new bucket
    private func _changeLiveBucketState(key : Text, data_size : Nat) : Bool{
        let canister_id = Principal.fromActor(liveBucket.bucket);
        switch(buckets.get(canister_id)){
            case null {
                buckets.put(canister_id, TrieSet.fromArray<Text>([key], Text.hash, Text.equal))
            };
            case(?os){
                buckets.put(canister_id, TrieSet.put<Text>(os, key, Text.hash(key), Text.equal))
            };
        };
        liveBucket.used_memory += data_size;
        liveBucket.used_memory >= RETIRING_THRESHOLD
    };

    private func isBucket(p : Principal) : Bool{
        for(b in buckets.keys()){
            if(b == p) return true
        };
        (Principal.fromActor(liveBucket.bucket) == p) or false
    };

    system func preupgrade(){
        buckets_entries := Array.init<(Principal, TrieSet.Set<Text>)>(
            buckets.size(),
            (Principal.fromActor(this), TrieSet.empty<Text>())
        );
        var buckets_index = 0;
        for(b in buckets.entries()){
            buckets_entries[buckets_index] := b;
            buckets_index += 1;
        };
    };

    system func postupgrade(){
        buckets_entries := [var];
    };

    var buckets_heartbeat_interval = 0;
    var isp_heartbeat_interval = 0;

    system func heartbeat() : async (){
        if(isp_heartbeat_interval == 10){
            let ISP_DYNAMIC_THRE : Nat = buckets.size() * CYCLE_BUCKET_LEFT + CYCLE_THRESHOLD;
            if (Cycles.balance() < ISP_DYNAMIC_THRE) {
                let amount : Nat = ISP_DYNAMIC_THRE - Cycles.balance();
                ignore await topUp(amount);
            };
            isp_heartbeat_interval := 0;
        }else{
            isp_heartbeat_interval += 1;
        };
         // 60 block, check the buckets
         if(buckets_heartbeat_interval == 60){
            for(m in buckets.keys()){
                let bucket : BucketInterface = actor(Principal.toText(m));
                await bucket.monitor();
            };
            buckets_heartbeat_interval := 0;
         }else{
            buckets_heartbeat_interval += 1;
         }
    };

};