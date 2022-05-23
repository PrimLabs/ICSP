import Types "Lib/Types";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import TrieMap "mo:base/TrieMap";
import Cycles "mo:base/ExperimentalCycles";
import SM "mo:base/ExperimentalStableMemory";

shared(installer) actor class Bucket() = this{
    private type StoreArgs              = Types.StoreArgs;
    private type IspInterface           = Types.IspInterface;
    private let CYCLE_THRESHOLD         = 3_000_000_000_000;
    private let ISP : IspInterface      = actor (Principal.toText(installer.caller));
    private stable var offset           = 0;
    private stable var assets_entries : [var (Text, (Nat64, Nat))] = [var];
    private var assets : TrieMap.TrieMap<Text, (Nat64, Nat)> = TrieMap.fromEntries<Text, (Nat64, Nat)>(assets_entries.vals(), Text.equal, Text.hash);
    
    public query({caller}) func get(key : Text) : async Result.Result<Blob, ()> {
        switch(assets.get(key)) {
            case(null) { 
                #err(())
            };
            case(?field) {
                #ok(_loadFromSM(field.0, field.1))
            };
        }
    };

    // build 200
    // public query func http_request(req : HttpRequest) : async HttpResponse{};

    public shared({caller}) func store(args : StoreArgs) : async (){
        assert(caller == Principal.fromActor(ISP));
        let _field = _getField(args.value.size());
        assets.put(args.key, _field);
        _storageData(_field.0, args.value);
    };

    // call back to isp canister
    public shared({caller}) func monitor() : async (){
        if (caller != Principal.fromActor(ISP)) return;
        if (Cycles.balance() < CYCLE_THRESHOLD) {
            let need : Nat = CYCLE_THRESHOLD - Cycles.balance() + 1_000_000_000_000; // threshold + 1 T
            ignore await ISP.topUpBucket(need);
        };
    };

    private func _loadFromSM(_offset : Nat64, length : Nat) : Blob {
        SM.loadBlob(_offset, length)
    };

    private func _storageData(_offset : Nat64, data : Blob) {
        SM.storeBlob(_offset, data)
    };

    private func _getField(total_size : Nat) : (Nat64, Nat) {
        let field = (Nat64.fromNat(offset), total_size);
        _growStableMemoryPage(total_size);
        offset += total_size;
        field
    };

    private func _growStableMemoryPage(size : Nat) {
        if(offset == 0){ ignore SM.grow(1 : Nat64) };
        let available : Nat = Nat64.toNat(SM.size() << 16 + 1 - Nat64.fromNat(offset));
        if (available < size) {
            let new : Nat64 = Nat64.fromNat(size - available);
            let growPage = new >> 16 + 1;
            ignore SM.grow(growPage);
        }
    };

    public shared func wallet_receive() : async Nat{
        Cycles.accept(Cycles.available())
    };

    system func preupgrade() {
        assets_entries := Array.init<(Text, (Nat64, Nat))>(assets.size(), ("", (0, 0)));
        var assets_index = 0;
        for (a in assets.entries()) {
            assets_entries[assets_index] := a;
            assets_index += 1;
        };
    };

    system func postupgrade() {
        assets_entries := [var];
    };
};