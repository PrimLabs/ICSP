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
import Nat64 "mo:base/Nat64";
import HttpHandler "Lib/HttpHandler";
import A "Lib/Account";
import U "Lib/Utils";

import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Prim "mo:⛔";

shared(installer) actor class isp()  = this {
    private type StoreArgs           = Types.StoreArgs;
    private type BucketInterface     = Types.BucketInterface;
    private type LiveBucket          = Types.LiveBucket;
    private type LiveBucketExt       = Types.LiveBucketExt;
    private type Management          = Types.Management;
    private type LEDGER              = Types.LEDGER;
    private type CanisterStatus      = Types.CanisterStatus;
    private type HttpRequest         = HttpHandler.HttpRequest;
    private type HttpResponse        = HttpHandler.HttpResponse;
    private let RETIRING_THRESHOLD   = 10485760; // 10 MB
    private let CYCLE_SHARE          =   300_000_000_000;  // cycle share each bucket created
    private let CYCLE_BUCKET_LEFT    =   100_000_000_000;
    private let CYCLE_THRESHOLD      = 2_000_000_000_000; //  658_368_000_000 Cycle :  2G / Month
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

    private var icsp_status_record = Buffer.Buffer<CanisterStatus>(100);

    // TODO : support http redirect get [3]
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

    public query func http_request(request : HttpRequest) : async HttpResponse{
        let path = Iter.toArray(Text.tokens(request.url, #text("/")));
        if (path.size() == 1) {
            for((p, keys) in buckets.entries()){
                if(TrieSet.mem<Text>(keys, path[0], Text.hash(path[0]), Text.equal)){
                    return build_302(Principal.toText(p), path[0]);
                }
            };
        };
        errStaticPage()
    };

    public shared({caller}) func init() : async Text{
        if(Principal.fromActor(liveBucket.bucket) == Principal.fromText("aaaaa-aa")){
            await createNewBucket();
            _wirteRecord("ICSP init");
            return "success";
        }else{
            "failed";
        };
    };

    public shared({caller}) func store(args : StoreArgs) : async (){
        ignore liveBucket.bucket.store(args);

        // inspect cycle balance [2]
        if(not _inspectCycleBalance(buckets.size() * CYCLE_BUCKET_LEFT + CYCLE_THRESHOLD)){
            // insufficient cycle
            // ignore topUpSelf : 2 T : icp -> cycle 2 T
            ignore topUp(10_000_000); // 0.1 icp
            _wirteRecord("ISCP Insufficient Cycle");
        };

        // 确定一定能创建新的 bucket : cycle balance >= isp cycle threshold + bucket creation cost [1]
        if(_changeLiveBucketState(args.key, args.value.size()) and (not liveBucket.retiring) and _inspectCycleBalance(CYCLE_THRESHOLD + CYCLE_SHARE)){
            liveBucket.retiring := true;
            ignore createNewBucket();
            _wirteRecord("Create New Bucket");
        };

        _wirteRecord("Store");
    };

    // inspect cycle balance [1]
    public shared({caller}) func createNewBucket() : async (){
        if (caller != Principal.fromActor(this) and caller != ADMIN) return;
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
                _wirteRecord("Top Up Bucket");
            };
        }
    };

    public shared func wallet_receive() : async Nat{
        Cycles.accept(Cycles.available());
    };

    public shared func get_status_record() : async Text{
        var res : Text = "";
        for (elem in icsp_status_record.vals()) {
            var time : Int = elem.time;
            res := res # " cycle_balance: " # Nat.toText(elem.cycle_balance);
            res := res # " memory_size: " # Nat.toText(elem.memory_size);
            res := res # " heap_size: " # Nat.toText(elem.heap_size);
            res := res # " total_allocation: " # Nat.toText(elem.total_allocation);
            res := res # " reclaimed: " # Nat.toText(elem.reclaimed);
            res := res # " max_live_size: " # Nat.toText(elem.max_live_size);
            res := res # " time: " # Int.toText(time);
            res := res # " note: " # elem.note;
            res := res # " xxxx ";
        };
        return res;
    };

    private func _wirteRecord(note : Text) {
        let record : CanisterStatus = {
            cycle_balance = Cycles.balance();
            memory_size = Prim.rts_memory_size();
            heap_size = Prim.rts_heap_size();
            total_allocation = Prim.rts_total_allocation();
            reclaimed = Prim.rts_reclaimed();
            max_live_size = Prim.rts_max_live_size();
            time = Time.now();
            note = note;
        };
        icsp_status_record.add(record);
    };

    private func errStaticPage(): HttpResponse {
        {
            status_code = 404;
            headers = [("Content-Type", "text/plain; version=0.0.4")];
            body = Text.encodeUtf8("Someting Wrong!");
            streaming_strategy = null;
        }
    };

    private func _inspectCycleBalance(necessary_cycle : Nat) : Bool{
        if (Cycles.balance() >= necessary_cycle) {return true;} 
        else {return false;} 
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
        Principal.fromActor(liveBucket.bucket) == p
    };

    private func build_302(bucket_id : Text, key : Text) : HttpResponse{
        {
            status_code = 302;
            headers = [
                ("Content-Type", "text/html"),
                ("Accept-Charset","utf8"),
                ("Location", bucket_id # ".raw.ic0.app/" # key),
                ("Cache-Control", "max-age=3000") // 5 min
            ];
            body = Text.encodeUtf8("<html lang="#"en"#"><head><title>ICSP</title></head><body></body></html>");
            streaming_strategy = null;
        }
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

    // var buckets_heartbeat_interval = 0;
    // var isp_heartbeat_interval = 0;

    // system func heartbeat() : async (){
    //     if(isp_heartbeat_interval == 10){
    //         let ISP_DYNAMIC_THRE : Nat = buckets.size() * CYCLE_BUCKET_LEFT + CYCLE_THRESHOLD;
    //         if (Cycles.balance() < ISP_DYNAMIC_THRE) {
    //             let amount : Nat = ISP_DYNAMIC_THRE - Cycles.balance();
    //             ignore await topUp(amount);
    //         };
    //         isp_heartbeat_interval := 0;
    //     }else{
    //         isp_heartbeat_interval += 1;
    //     };
    //      // 60 block, check the buckets
    //      if(buckets_heartbeat_interval == 60){
    //         for(m in buckets.keys()){
    //             let bucket : BucketInterface = actor(Principal.toText(m));
    //             await bucket.monitor();
    //         };
    //         buckets_heartbeat_interval := 0;
    //      }else{
    //         buckets_heartbeat_interval += 1;
    //      }
    // };
};
