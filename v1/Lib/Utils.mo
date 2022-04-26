import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

module Utils{

    public type Token = { e8s : Nat64 };

    // Convert principal id to subaccount id.
    // sub account = [sun_account_id_size, principal_blob, 0,0,···]
    public func principalToSubAccount(id: Principal) : [Nat8] {
        let p = Blob.toArray(Principal.toBlob(id));
        Array.tabulate(32, func(i : Nat) : Nat8 {
            if (i >= p.size() + 1) 0
            else if (i == 0) (Nat8.fromNat(p.size()))
            else (p[i - 1])
        })
    };


};