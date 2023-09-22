module createdao::create {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use std::vector;
    use std::string::{Self, String};
    use sui::balance::{Self, Balance};
    use sui::dynamic_object_field as dof;
    use createdao::dao::{Self, DaoData};
    use createdao::util::{Self};

    //--------Friend module------------
    friend createdao::market;
    
    //-------Error code---------------
    const EDefault:u64 = 0;
    const EAlreadyRegistered:u64 = 1;
    const EWorkNotExist:u64 = 2;
    const ENeedRegister:u64 = 3;

    //-------Object-------------
    struct UserProfile has key {
        id: UID,
        name: String,
        email: String,
        dec: String,
    }
    struct GlobalConfig has key, store {
        id: UID,
        users: Table<address, ID>,
        works: Table<ID, WorkGlobalInfo>,
        user_assets: Table<address, Balance<SUI>>,
    }

    struct Work has key, store {
        id: UID,
        title: String, 
        content:String,

        advertisementId: ID,
        advertisementExpire:u64,
    }
    
    struct WorkGlobalInfo has store,copy {
        workId: ID,
        likes: vector<address>,
        owner: address,
    }

    //--------Witness----------
    struct CREATE has drop {
        
    }

    //-------Constructor------------
    fun init(_witness: CREATE, ctx: &mut TxContext) {
        let globalConfig = GlobalConfig{
            id: object::new(ctx),
            users: table::new(ctx),
            works: table::new(ctx),
            user_assets: table::new(ctx),
        };

        transfer::share_object(globalConfig);
    }

    ///--------------------Function--------------------
    // creator regisiter 
    // @param globalConfig: global data of create module
    // @param name: user name
    // @param email: user email
    // @param dec: user self-introduction
    public entry fun register(globalConfig:&mut GlobalConfig,name: vector<u8>, email: vector<u8>,dec: vector<u8>,ctx: &mut TxContext) {
        let sender =  tx_context::sender(ctx);
        assert!(contains_creator(globalConfig, sender) == false, EAlreadyRegistered);

        let user = UserProfile {
            id: object::new(ctx),
            name: string::utf8(name),
            email: string::utf8(email),
            dec: string::utf8(dec),
        };
        let userId = object::id(&user);

        transfer::transfer(user, sender);
        table::add(&mut globalConfig.users, sender, userId);
    }

    // creator new a work
    // @param title: work title
    // @param content: work content or a url poiting to really content
    public entry fun new(globalConfig:&mut GlobalConfig, title: vector<u8>, content:vector<u8>, ctx:&mut TxContext):ID {
        let sender = tx_context::sender(ctx);
        assert!(contains_creator(globalConfig, sender) == true, ENeedRegister);

        let work = Work{
            id: object::new(ctx),
            title: string::utf8(title),
            content: string::utf8(content),
            advertisementId: util::empty_ID(),
            advertisementExpire:0,
        };
        let workId = object::id(&work);
        transfer::transfer(work, sender);

        let workGlobalInfo = WorkGlobalInfo{
            workId: workId,
            likes:  vector::empty(),
            owner: sender,
        };
        table::add(&mut globalConfig.works, workId, workGlobalInfo);

        workId
    }   

    // user like a work when he think it's great
    // @param workId: object id of a work
    public entry fun like(globalConfig:&mut GlobalConfig, workId:ID, ctx:&mut TxContext) {
        assert!(table::contains(&globalConfig.works, workId) == true, EWorkNotExist);
        let workGlobalInfo = table::borrow_mut(&mut globalConfig.works, workId);

        let sender = tx_context::sender(ctx);
        let (ok, _) = vector::index_of(&workGlobalInfo.likes, &sender);
        if (ok) { return };
        vector::insert(&mut workGlobalInfo.likes, sender, 0);
    }
    
    // user reward coin to a work when he think it's great
    // @param daoData: gobal DAO data
    // @param workId: object id of a work
    // @amount amount: how munch coin user want to reward
    public entry fun reward(globalConfig:&mut GlobalConfig, daoData:&mut DaoData, workId:ID, amount:Coin<SUI>,ctx:&mut TxContext) {
        let amountValue = coin::value(&amount);
        assert!(amountValue > 0, EDefault);
        
        let workGlobalInfo = table::borrow(&globalConfig.works, workId);
        let depositAmount = coin::split(&mut amount, amountValue/10, ctx);
        if (table::contains(&globalConfig.user_assets, workGlobalInfo.owner) == false) {
            table::add(&mut globalConfig.user_assets, workGlobalInfo.owner, balance::zero());
        };
        let user_asset = table::borrow_mut(&mut globalConfig.user_assets, workGlobalInfo.owner);
        balance::join(user_asset, coin::into_balance(amount));

        dao::deposit(workGlobalInfo.owner, daoData, depositAmount);
    }

    // User withdraws revenue
    public entry fun collect_bonus(globalConfig:&mut GlobalConfig, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let user_asset = table::borrow_mut(&mut globalConfig.user_assets, sender);
        let amount = balance::withdraw_all(user_asset);

        assert!(balance::value(&amount)>0 , EDefault);
        transfer::public_transfer(coin::from_balance(amount, ctx), sender);
    }

    ///--------------Friend function, only call by friendly modules-----------------
    public(friend) fun handle_deal(globalConfig:&mut GlobalConfig, daoData:&mut DaoData, workId:ID, newOwner:address,amount:Coin<SUI>,ctx:&mut TxContext) {
        let amountValue = coin::value(&amount);
        assert!(amountValue > 0, EDefault);
        
        let workGlobalInfo = table::borrow_mut(&mut globalConfig.works, workId);
        let depositAmount = coin::split(&mut amount, amountValue/10, ctx);
        if (table::contains(&globalConfig.user_assets, workGlobalInfo.owner) == false) {
            table::add(&mut globalConfig.user_assets, workGlobalInfo.owner, balance::zero());
        };
        let user_asset = table::borrow_mut(&mut globalConfig.user_assets, workGlobalInfo.owner);
        balance::join(user_asset, coin::into_balance(amount));

        //update owner of work
        workGlobalInfo.owner = newOwner;
        
        dao::deposit(workGlobalInfo.owner, daoData, depositAmount);
    }

    public(friend) fun add_advertisement<AD: key+store>(globalConfig:&mut GlobalConfig,  daoData:&mut DaoData, work:&mut Work, advertisement:AD, expireTime:u64,amount:Coin<SUI>, ctx:&mut TxContext) {
        let amountValue = coin::value(&amount);
        assert!(amountValue > 0, EDefault);
        
        let advertisementId = object::id(&advertisement);
        work.advertisementId = advertisementId;
        work.advertisementExpire = expireTime;
        
        // 10% deposit to DAO
        let depositAmount = coin::split(&mut amount, amountValue/10, ctx);
        dao::deposit(tx_context::sender(ctx), daoData, depositAmount);

        // 90% is personal
        let user_asset = table::borrow_mut(&mut globalConfig.user_assets, tx_context::sender(ctx));
        balance::join(user_asset, coin::into_balance(amount));

        dof::add(&mut work.id, advertisementId, advertisement); 
    }

    public(friend) fun remove_current_advertisement<AD:key+store>(work:&mut Work) :AD {
        dof::remove<ID, AD>(&mut work.id, work.advertisementId)
    }

    ///-----------------Getter-----------------------------
    public fun contains_work(globalConfig:&GlobalConfig, wordId: ID): bool {
        table::contains(&globalConfig.works, wordId)
    }

    public fun contains_creator(globalConfig:&GlobalConfig, creator:address): bool {
        table::contains(&globalConfig.users, creator)
    }

    public fun get_workInfo(globalConfig:&GlobalConfig, wordId: ID):(ID, vector<address>, address) {
       let WorkGlobalInfo{workId, likes, owner} = table::borrow(&globalConfig.works, wordId);

       (*workId, *likes, *owner)
    }

    public fun contains_advertisement(work:&Work):bool {
        work.advertisementId != util::empty_ID()
    }

    public fun advertisement_expire_time(work:&Work):u64 {
        work.advertisementExpire
    }
    
    public fun work_likes_count(globalConfig:&GlobalConfig, workId:ID):u64 {
        let workGlobalInfo = table::borrow(&globalConfig.works, workId);
        vector::length(&workGlobalInfo.likes)
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(CREATE{}, ctx);
    }
}