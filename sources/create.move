
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
    use createdao::dao::{Self, DaoData};

    friend createdao::market;
    
    const EDefault:u64 = 0;
    const EAlreadyRegistered:u64 = 1;
    const EWorkNotExist:u64 = 2;
    const ENeedRegister:u64 = 3;

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
    }
    
    struct WorkGlobalInfo has store,copy {
        workId: ID,
        likes: vector<address>,
        owner: address,
    }

    struct CREATE has drop {

    }

    fun init(_witness: CREATE, ctx: &mut TxContext) {
        let globalConfig = GlobalConfig{
            id: object::new(ctx),
            users: table::new(ctx),
            works: table::new(ctx),
            user_assets: table::new(ctx),
        };

        transfer::share_object(globalConfig);
    }

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

    public entry fun new(globalConfig:&mut GlobalConfig, title: vector<u8>, content:vector<u8>, ctx:&mut TxContext):ID {
        let sender = tx_context::sender(ctx);
        assert!(contains_creator(globalConfig, sender) == true, ENeedRegister);

        let work = Work{
            id: object::new(ctx),
            title: string::utf8(title),
            content: string::utf8(content),
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

    public entry fun like(globalConfig:&mut GlobalConfig, workId:ID, ctx:&mut TxContext) {
        assert!(table::contains(&globalConfig.works, workId) == true, EWorkNotExist);
        let workGlobalInfo = table::borrow_mut(&mut globalConfig.works, workId);

        let sender = tx_context::sender(ctx);
        let (ok, _) = vector::index_of(&workGlobalInfo.likes, &sender);
        if (ok) { return };
        vector::insert(&mut workGlobalInfo.likes, sender, 0);
    }
    
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

    public entry fun collect_bonus(globalConfig:&mut GlobalConfig, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let user_asset = table::borrow_mut(&mut globalConfig.user_assets, sender);
        let amount = balance::withdraw_all(user_asset);

        assert!(balance::value(&amount)>0 , EDefault);
        transfer::public_transfer(coin::from_balance(amount, ctx), sender);
    }

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

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(CREATE{}, ctx);
    }
}