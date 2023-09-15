module createdao::market {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::sui::{SUI};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use createdao::create::{Self, GlobalConfig};
    use createdao::dao::{DaoData};

    const EDefault:u64 = 0;
    const ENotOwner:u64 = 1;
    const ENotEnoughMoney:u64 = 2;

    
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

    struct MARKET has drop {}

    fun init(_witness: MARKET, ctx:&mut TxContext){
        let market = Market<Coin<SUI>>{
            id: object::new(ctx),
        };

        transfer::share_object(market);
    }
    
    public entry fun list<T: key + store>(market:&mut Market<Coin<SUI>>, createGlobalConfig:&GlobalConfig,item:T, price: u64, ctx:&mut TxContext) {
        let itemId = object::id(&item);
        assert!(create::contains_work(createGlobalConfig, itemId) == true, EDefault);

        let sender = tx_context::sender(ctx);
        let listing = Listing {
            id: object::new(ctx),
            price: price,
            owner: sender,
        };
        dof::add(&mut listing.id, true, item);
        dof::add(&mut market.id, itemId, listing);
    }

    public entry fun delist<T: key + store>(market:&mut Market<SUI>, itemId:ID, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let Listing{id, price:_, owner} = dof::remove(&mut market.id, itemId);
        assert!(owner == sender, ENotOwner);

        let item = dof::remove<bool,T>(&mut id, true);
        transfer::public_transfer(item, sender);

        object::delete(id);
    }

    public entry fun buy<T: key + store>(market:&mut Market<Coin<SUI>>,createGlobalConfig:&mut GlobalConfig, daoData:&mut DaoData, itemId:ID, paid:Coin<SUI>, ctx:&mut TxContext)  {
        let sender = tx_context::sender(ctx);
        let Listing{id, price, owner:_} = dof::remove(&mut market.id, itemId);
        assert!(coin::value(&paid) >=  price, ENotEnoughMoney);
        
        let reallyPaid = coin::split(&mut paid, price, ctx);
        create::handle_deal(createGlobalConfig, daoData, itemId, sender, reallyPaid, ctx);

        let item = dof::remove<bool,T>(&mut id, true);
        transfer::public_transfer(item, sender);
        object::delete(id);

        if (coin::value(&paid) > 0) {
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