module createdao::market {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::sui::{SUI};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use std::string::{Self, String};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use createdao::util::{Self};
    use createdao::create::{Self, GlobalConfig, Work};
    use createdao::dao::{DaoData};

    ///----------Error code-------------
    //const EDefault:u64 = 0;
    const ENotOwner:u64 = 1;
    const ENotEnoughMoney:u64 = 2;
    const EWorkNotExist:u64 = 3;
    const ECannotRemoteValidAdvertisement:u64 = 4;

    ///------------Object----------------
    // Coin is for that user can use multiple types of coin to buy 
    // market is a platform of economic activity
    struct Market<phantom COIN> has key {
        id: UID,
    }

    struct AdvertisementMarket<phantom COIN> has key {
        id: UID,
    }

    /// A single listing which contains the listed item and its
    /// price in [`Coin<COIN>`].
    struct Listing has key, store {
        id: UID,
        price: u64, // price of work
        owner: address, // owner of the worker, may be the creator
    }

    struct Advertisement has key, store {
        id: UID,
        targetWorkId: ID, // What's work the advertisement want to attach
        content: String,
        pay: Balance<SUI>, // How much coin creator can get if they accept this advertisement
        duration:u64, // How long the advertisement show in the work
    }

    ///-------------Witness------------------
    struct MARKET has drop {}

    ///-------------Constructor----------------
    fun init(_witness: MARKET, ctx:&mut TxContext){
        transfer::share_object(Market<Coin<SUI>>{
            id: object::new(ctx),
        });

        transfer::share_object(AdvertisementMarket<Coin<SUI>>{
            id:object::new(ctx),
        });
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
    // @param pay: how much coin user pay for this work. The extra coin will be refunded
    public entry fun buy(market:&mut Market<Coin<SUI>>,createGlobalConfig:&mut GlobalConfig, daoData:&mut DaoData, workId:ID, pay:Coin<SUI>, ctx:&mut TxContext)  {
        let sender = tx_context::sender(ctx);
        let Listing{id, price, owner:_} = dof::remove(&mut market.id, workId);
        assert!(coin::value(&pay) >=  price, ENotEnoughMoney);
        
        let reallyPay = coin::split(&mut pay, price, ctx);
        create::handle_deal(createGlobalConfig, daoData, workId, sender, reallyPay, ctx);

        let item = dof::remove<bool,Work>(&mut id, true);
        transfer::public_transfer(item, sender);
        object::delete(id);

        if (coin::value(&pay) > 0) {
            // return to user extra coin
            transfer::public_transfer(pay, sender);
        } else {
            coin::destroy_zero(pay);
        }
    }

    public entry fun list_advertisement(advertisementMarket:&mut AdvertisementMarket<Coin<SUI>>,
             createGlobalConfig:&GlobalConfig, workId: ID, content:vector<u8>, pay:Coin<SUI>, duration:u64, ctx:&mut TxContext) {
        // advertisement only attach to a existent work
        assert!(create::contains_work(createGlobalConfig, workId) == true, EWorkNotExist);
        let advertisement = Advertisement{
            id: object::new(ctx),
            targetWorkId: workId,
            content: string::utf8(content),
            pay: coin::into_balance(pay),
            duration: duration,
        };
        let advertisementId = object::id(&advertisement);
        dof::add(&mut advertisementMarket.id, advertisementId, advertisement);
    }

    public entry fun delete_advertisement(advertisementMarket:&mut AdvertisementMarket<Coin<SUI>>, advertisementId:ID, ctx:&mut TxContext) {
        let advertisement = dof::remove<ID, Advertisement>(&mut advertisementMarket.id, advertisementId);  

        // return coin to who list this advertisement
        let b = balance::withdraw_all(&mut advertisement.pay);
        transfer::public_transfer(coin::from_balance(b, ctx), tx_context::sender(ctx));

        //destory object 
        transfer::transfer(advertisement, util::zero_address());
    }

    public entry fun accept_advertisement(advertisementMarket:&mut AdvertisementMarket<Coin<SUI>>,work:&mut Work,
        createGlobalConfig:&mut GlobalConfig, daoData:&mut DaoData, advertisementId:ID, clock:&Clock,ctx:&mut TxContext) {
        if (create::contains_advertisement(work) == true) {
            let preAdvertisement =  create::remove_current_advertisement<Advertisement>(work);
            if (create::advertisement_expire_time(work) > clock::timestamp_ms(clock)) {
                //advertisement is not expired, cannot delete it
                assert!(false, ECannotRemoteValidAdvertisement);
            };

            //destory object 
            transfer::transfer(preAdvertisement, util::zero_address());
        };

        
        let advertisement = dof::remove<ID, Advertisement>(&mut advertisementMarket.id, advertisementId);    
        let pay = balance::withdraw_all(&mut advertisement.pay);
        let advertisementExpire = advertisement.duration + clock::timestamp_ms(clock);
        create::add_advertisement<Advertisement>(createGlobalConfig, daoData, work, 
                advertisement, advertisementExpire,
                 coin::from_balance(pay, ctx),ctx);
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(MARKET{}, ctx);
    }
}