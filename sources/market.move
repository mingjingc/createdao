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
    use sui::event;
    use createdao::util::{Self};
    use createdao::create::{Self, GlobalConfig, Work};
    use createdao::dao::{DaoData};

    ///----------Error code-------------
    //const EDefault:u64 = 0;
    const ENotOwner:u64 = 1;
    const ENotEnoughMoney:u64 = 2;
    const EWorkNotExist:u64 = 3;
    const ECannotRemoteValidAdvertisement:u64 = 4;
    const ENotTargetWork:u64 = 5;

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
        owner: address,
        targetWorkId: ID, // What's work the advertisement want to attach
        content: String,
        pay: Balance<SUI>, // How much coin creator can get if they accept this advertisement
        duration:u64, // How long the advertisement show in the work
    }

    ///-----------Event-----------
    struct EventList has drop, copy {
        from: address,
        listingId: ID,
        workId: ID,
        price: u64,
    }
    struct EventDeleteListing has drop, copy {
        listingId: ID,
    }

    struct EventNewMatch has drop, copy {
        whoBuy: address,
        whoSell: address,
        workId: ID, 
        price: u64,
    }

    struct EventNewAdvertisement has drop, copy {
        from: address,
        advertisementId: ID,
        targetWorkId: ID,
        pay: u64,
    }
    struct EventAdvertisementDelete has drop, copy {
        advertisementId: ID,
    }
    struct EventAdvertisementAccepted has drop, copy {
        workId: ID,
        advertisementId: ID,
        price: u64,
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
        let listingId = object::id(&listing);
        dof::add(&mut listing.id, true, work);
        dof::add(&mut market.id, workId, listing);

        event::emit(EventList{
            from: sender,
            listingId: listingId,
            workId: workId,
            price: price,
        });
    }

    // creator remove their work from market
    // @param workId: object id of the work
    public entry fun delist(market:&mut Market<SUI>, workId:ID, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let Listing{id, price:_, owner} = dof::remove(&mut market.id, workId);
        assert!(owner == sender, ENotOwner);

        let item = dof::remove<bool,Work>(&mut id, true);
        transfer::public_transfer(item, sender);

        let listingId = object::uid_to_inner(&id);
        object::delete(id);
        event::emit(EventDeleteListing{
            listingId: listingId,
        });
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
        let oldOwner = create::handle_deal(createGlobalConfig, daoData, workId, sender, reallyPay, ctx);

        let item = dof::remove<bool,Work>(&mut id, true);
        transfer::public_transfer(item, sender);
        object::delete(id);

        if (coin::value(&pay) > 0) {
            // return to user extra coin
            transfer::public_transfer(pay, sender);
        } else {
            coin::destroy_zero(pay);
        };

        event::emit(EventNewMatch{
            whoBuy: sender,
            whoSell: oldOwner,
            workId: workId,
            price: price,
        });
    }

    // user list a advertisement listing.
    // @param workId: object id of work.
    // @param content: advertisement content, may picture or vedio url.
    // @param pay: how much coin user can pay for this advertisement.
    // @param duration: how much time advertisement attaching on the work.
    public entry fun list_advertisement(advertisementMarket:&mut AdvertisementMarket<Coin<SUI>>,
             createGlobalConfig:&GlobalConfig, workId: ID, content:vector<u8>, pay:Coin<SUI>, duration:u64, ctx:&mut TxContext):ID {
        // advertisement only attach to a existent work
        assert!(create::contains_work(createGlobalConfig, workId) == true, EWorkNotExist);
        let advertisement = Advertisement{
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            targetWorkId: workId,
            content: string::utf8(content),
            pay: coin::into_balance(pay),
            duration: duration,
        };
        let advertisementId = object::id(&advertisement);

        event::emit(EventNewAdvertisement{
            from: tx_context::sender(ctx),
            advertisementId: advertisementId,
            targetWorkId: workId,
            pay: balance::value(&advertisement.pay),
        });
        dof::add(&mut advertisementMarket.id, advertisementId, advertisement);
        advertisementId
    }

    // user delete advertisement listing. Only owner can do it.
    // @param advertisementId: object id of advertisement
    public entry fun delete_advertisement(advertisementMarket:&mut AdvertisementMarket<Coin<SUI>>, advertisementId:ID, ctx:&mut TxContext) {
        let advertisement = dof::remove<ID, Advertisement>(&mut advertisementMarket.id, advertisementId); 
        assert!(advertisement.owner == tx_context::sender(ctx), ENotOwner); 

        // return coin to who list this advertisement
        let b = balance::withdraw_all(&mut advertisement.pay);
        transfer::public_transfer(coin::from_balance(b, ctx), tx_context::sender(ctx));

        event::emit(EventAdvertisementDelete{
            advertisementId: object::id(&advertisement),
        });
        //destory object 
        transfer::transfer(advertisement, util::zero_address());
    }

    // owner of the work accept the advertisement.
    // @param @work: the work object
    // @param @advertisementId: object id of the advertisement
    public entry fun accept_advertisement(advertisementMarket:&mut AdvertisementMarket<Coin<SUI>>,
    createGlobalConfig:&mut GlobalConfig, daoData:&mut DaoData, 
    work:&mut Work, advertisementId:ID, clock:&Clock,ctx:&mut TxContext) {
        let workId = object::id(work);
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
        assert!(object::id(work) == advertisement.targetWorkId, ENotTargetWork);

        let pay = balance::withdraw_all(&mut advertisement.pay);
        let price = balance::value(&pay);
        let advertisementExpire = advertisement.duration + clock::timestamp_ms(clock);
        create::add_advertisement<Advertisement>(createGlobalConfig, daoData, work, 
                advertisement, advertisementExpire,
                 coin::from_balance(pay, ctx),ctx);

        event::emit(EventAdvertisementAccepted{
            advertisementId: advertisementId,
            workId: workId,
            price: price,
        });
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(MARKET{}, ctx);
    }
}