module createdao::market {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::sui::{SUI};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use createdao::create::{Self, GlobalConfig, Work};
    use createdao::dao::{DaoData};

    ///----------Error code-------------
    const EDefault:u64 = 0;
    const ENotOwner:u64 = 1;
    const ENotEnoughMoney:u64 = 2;

    ///------------Object----------------
    // Coin is for that user can use multiple types of coin to buy 
    // market is a platform of economic activity
    struct Market<phantom COIN> has key {
        id: UID,
    }

    /// A single listing which contains the listed item and its
    /// price in [`Coin<COIN>`].
    struct Listing has key, store {
        id: UID,
        price: u64,
        owner: address,
    }

    ///-------------Witness------------------
    struct MARKET has drop {}

    ///-------------Constructor----------------
    fun init(_witness: MARKET, ctx:&mut TxContext){
        let market = Market<Coin<SUI>>{
            id: object::new(ctx),
        };

        transfer::share_object(market);
    }
    
    ///---------------Function---------------------
    // creator list his work in market for saling
    // @param createGlobalConfig: gobalConfig object of create module
    // @param item: currently it is the work created by creator
    // @param price: how much f
    public entry fun list(market:&mut Market<Coin<SUI>>, work:Work, price: u64, ctx:&mut TxContext) {
        let workId = object::id(&work);
        //assert!(create::contains_work(createGlobalConfig, workId) == true, EDefault);

        let sender = tx_context::sender(ctx);
        let listing = Listing {
            id: object::new(ctx),
            price: price,
            owner: sender,
        };
        dof::add(&mut listing.id, true, work);
        dof::add(&mut market.id, workId, listing);
    }

    // creator remove their work from market
    // @param workId: object id of the work
    public entry fun delist(market:&mut Market<SUI>, workId:ID, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let Listing{id, price:_, owner} = dof::remove(&mut market.id, workId);
        assert!(owner == sender, ENotOwner);

        let item = dof::remove<bool,Work>(&mut id, true);
        transfer::public_transfer(item, sender);

        object::delete(id);
    }

    // user buy a work
    // @param createGlobalConfig: gobalConfig object of create module
    // @param daoData: gobal data of DAO module
    // @param workId: object id of the work
    // @param paid: how much coin user pay for this work. The extra coin will be refunded
    public entry fun buy(market:&mut Market<Coin<SUI>>,createGlobalConfig:&mut GlobalConfig, daoData:&mut DaoData, workId:ID, paid:Coin<SUI>, ctx:&mut TxContext)  {
        let sender = tx_context::sender(ctx);
        let Listing{id, price, owner:_} = dof::remove(&mut market.id, workId);
        assert!(coin::value(&paid) >=  price, ENotEnoughMoney);
        
        let reallyPaid = coin::split(&mut paid, price, ctx);
        create::handle_deal(createGlobalConfig, daoData, workId, sender, reallyPaid, ctx);

        let item = dof::remove<bool,Work>(&mut id, true);
        transfer::public_transfer(item, sender);
        object::delete(id);

        if (coin::value(&paid) > 0) {
            // return to user extra coin
            transfer::public_transfer(paid, sender);
        } else {
            coin::destroy_zero(paid);
        }
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(MARKET{}, ctx);
    }
}