module createdao::gtoken {
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, TreasuryCap};
    use sui::transfer;
    use sui::balance::{Balance};
    use std::option;

    friend createdao::dao;
    
    struct GTOKEN has drop {}

    fun init(witness: GTOKEN, ctx: &mut TxContext) {
        let (treasuryCap, metadata) = coin::create_currency<GTOKEN>(witness, 2, b"GTOKEN", b"Govenance Token", b"", option::none(), ctx);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasuryCap, tx_context::sender(ctx))
    }

    public(friend) fun mint_balance(treasuryCap: &mut TreasuryCap<GTOKEN>, amount:u64): Balance<GTOKEN> {
        coin::mint_balance(treasuryCap, amount)
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(GTOKEN {}, ctx)
    }
}