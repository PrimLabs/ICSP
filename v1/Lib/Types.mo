import Result "mo:base/Result";
import HttpHandler "HttpHandler";

module {
    type HttpRequest    = HttpHandler.HttpRequest;
    type HttpResponse   = HttpHandler.HttpResponse;

    // file type : jpeg , jpg : Text
    public type StoreArgs = {
        key : Text;
        value : Blob;
        file_type : Text;
    };

    public type Status = {
        key : Text;
        rts_memory_size: Text;
        rts_heap_size: Text;
        rts_total_allocation: Text;
        rts_reclaimed: Text;
        rts_max_live_size: Text;
        rts_callback_table_count: Text;
        rts_callback_table_size: Text;
        stable_memory_size: Text
    };

    public type BucketInterface = actor{
        get : query (key : Text) -> async Result.Result<(Blob, Text), ()>;
        get_status : query (index : Nat) -> async Status;
        http_request : query (request : HttpRequest) -> async HttpResponse;
        wallet_receive : () -> async Nat;
        store : (args : StoreArgs) -> async ();
        get_log_last_index :  query () -> async Nat;
    };

    public type IspInterface = actor{
        topUpBucket : (amount: Nat) -> async ();
    };

    public type LiveBucket = {
        var bucket : BucketInterface;
        var used_memory : Nat; // used stable memory
        var retiring : Bool; // true : creating new bucket; false : bucket is using at present
    };

    public type LiveBucketExt = {
        canister_id : Principal;
        used_memory : Nat;
        retiring : Bool;
    };

    public type canister_id = Principal;

    public type canister_settings = {
        freezing_threshold : ?Nat;
        controllers : ?[Principal];
        memory_allocation : ?Nat;
        compute_allocation : ?Nat;
    };

    public type definite_canister_settings = {
        freezing_threshold : Nat;
        controllers : [Principal];
        memory_allocation : Nat;
        compute_allocation : Nat;
    };

    public type wasm_module = [Nat8];

    public type Management = actor {
        canister_status : shared { canister_id : canister_id } -> async {
            status : { #stopped; #stopping; #running };
            memory_size : Nat;
            cycles : Nat;
            settings : definite_canister_settings;
            module_hash : ?[Nat8];
        };

        create_canister : shared { settings : ?canister_settings } -> async {
            canister_id : canister_id;
        };
        
        delete_canister : shared { canister_id : canister_id } -> async ();
        
        deposit_cycles : shared { canister_id : canister_id } -> async ();
        
        install_code : shared {
            arg : [Nat8];
            wasm_module : wasm_module;
            mode : { #reinstall; #upgrade; #install };
            canister_id : canister_id;
            } -> async ();
        
        provisional_create_canister_with_cycles : shared {
            settings : ?canister_settings;
            amount : ?Nat;
            } -> async { canister_id : canister_id };
        
        provisional_top_up_canister : shared {
            canister_id : canister_id;
            amount : Nat;
            } -> async ();
        
        raw_rand : shared () -> async [Nat8];
        start_canister : shared { canister_id : canister_id } -> async ();
        stop_canister : shared { canister_id : canister_id } -> async ();
        uninstall_code : shared { canister_id : canister_id } -> async ();
        
        update_settings : shared {
            canister_id : Principal;
            settings : canister_settings;
            } -> async ();
    };

    // Ledger top-up
    public type Memo = Nat64;

    public type Token = {
        e8s : Nat64;
    };

    public type TimeStamp = {
        timestamp_nanos: Nat64;
    };

    public type AccountIdentifier = Blob;

    public type SubAccount = Blob;

    public type BlockIndex = Nat64;

    public type TransferError = {
        #BadFee: {
            expected_fee: Token;
        };
        #InsufficientFunds: {
            balance: Token;
        };
        #TxTooOld: {
            allowed_window_nanos: Nat64;
        };
        #TxCreatedInFuture;
        #TxDuplicate : {
            duplicate_of: BlockIndex;
        };
    };

    public type TransferArgs = {
        memo: Memo;
        amount: Token;
        fee: Token;
        from_subaccount: ?SubAccount;
        to: AccountIdentifier;
        created_at_time: ?TimeStamp;
    };

    public type TransferResult = {
        #Ok: BlockIndex;
        #Err: TransferError;
    };

    public type Address = Blob;

    public type AccountBalanceArgs = {
        account : Address
    };

    public type BackResult = {
        #Ok : Blob;
        #Err : Text
    };

    public type NotifyCanisterArgs = {
        // The of the block to send a notification about.
        block_height: BlockIndex;
        // Max fee, should be 10000 e8s.
        max_fee: Token;
        // Subaccount the payment came from.
        from_subaccount: ?SubAccount;
        // Canister that received the payment.
        to_canister: Principal;
        // Subaccount that received the payment.
        to_subaccount:  ?SubAccount;
    };

    public type LEDGER = actor{
        transfer : TransferArgs -> async TransferResult;
        account_balance : query AccountBalanceArgs -> async Token;
        notify_dfx : NotifyCanisterArgs -> async ();
    };

    public type Time = Int;

    public type CanisterStatus = {
        cycle_balance : Nat;
        memory_size : Nat;
        heap_size : Nat;
        total_allocation : Nat;
        reclaimed : Nat;
        max_live_size : Nat;
        time : Time;
        note : Text;
    };
};