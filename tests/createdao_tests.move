#[test_only]
module createdao::createdao_tests {
    use createdao::create::{Self, GlobalConfig, Work};
    use createdao::dao::{Self, DaoData};
    use createdao::market::{Self, Market, AdvertisementMarket};
    use sui::test_scenario::{Self, Scenario, next_tx, };
    use sui::object::{Self, ID};
    use sui::sui::{SUI};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::transfer::{Self};
    use sui::tx_context::{Self, TxContext};
    use std::vector;

    const Creator: address = @0x10;
    const User1: address = @0x11;
    const User2: address = @0x12;
    const User3: address = @0x13;

    const Day: u64 = 24*60*60*1000;

    #[test]
    fun register_test() {
        let scenario = prepare();
        next_tx(&mut scenario, Creator);
        register(&mut scenario, Creator);

        // clean scenario object
        test_scenario::end(scenario);
    }

    #[test]
    fun newWork_test() {
        let scenario = prepare();

        next_tx(&mut scenario, Creator);
        register(&mut scenario, Creator);

        next_tx(&mut scenario, Creator);
        let workId = newWork(&mut scenario);

        next_tx(&mut scenario, User1);
        like(workId, Creator, &mut scenario);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun like_test() {
        let scenario = prepare();

        next_tx(&mut scenario, Creator);
        register(&mut scenario, Creator);

        next_tx(&mut scenario, Creator);
        let workId = newWork(&mut scenario);

        next_tx(&mut scenario, User1);
        like(workId, Creator, &mut scenario);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun reward_test() {
        let scenario = prepare();

        next_tx(&mut scenario, Creator);
        register(&mut scenario, Creator);

        next_tx(&mut scenario, Creator);
        let workId = newWork(&mut scenario);

        next_tx(&mut scenario, User1);
        {
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);

            let sui_coin = coin::mint_for_testing<SUI>(100, test_scenario::ctx(&mut scenario));
            reward(&mut globalConfig,&mut daoData, workId, sui_coin, &mut scenario);

            //check update data
            assert!(dao::asset_value(&daoData) == 10, 0);
        
            test_scenario::return_shared(globalConfig);
            test_scenario::return_shared(daoData);
        };

        next_tx(&mut scenario, Creator);
        {
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            create::collect_bonus(&mut globalConfig, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(globalConfig);
        };
        check_balance(Creator, 90,&mut scenario);
    

        test_scenario::end(scenario);
    }

    #[test]
    fun proposal_test() {
        let scenario = prepare();
        init_for_dao_test(&mut scenario);

        //User2 create proposal
        next_tx(&mut scenario, User2);
        let proposalId:ID;
        {
            let myclock = test_scenario::take_shared<Clock>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);
            
            let task = b"develop a website for CreateDAO";
            let website = b"https://abc.com";
            let contact = b"abc@abc.com";
            let needFunds = 100u64;
            let expire = Day + timestamp(&myclock);
            proposalId = dao::newProposal(&mut daoData, task, website, contact, needFunds, expire, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(myclock);
            test_scenario::return_shared(daoData);
        };

        next_tx(&mut scenario, Creator);
        {
            let myclock = test_scenario::take_shared<Clock>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);
            
            //vote for proposal
            dao::vote(&mut daoData, proposalId, &myclock, test_scenario::ctx(&mut scenario));

            //check proposal status
            let proposal = dao::borrow_proposal(&daoData, proposalId);
            assert!(dao::proposal_status(proposal) == 1, 0);

            test_scenario::return_shared(myclock);
            test_scenario::return_shared(daoData);
        };

        next_tx(&mut scenario, User1);
        {
            let myclock = test_scenario::take_shared<Clock>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);
    
            //vote for proposal
            dao::execute_proposal(&mut daoData, proposalId, &myclock, test_scenario::ctx(&mut scenario));

            //check proposal status
            let proposal = dao::borrow_proposal(&daoData, proposalId);
            assert!(dao::proposal_status(proposal) == 2, 0);

            test_scenario::return_shared(myclock);
            test_scenario::return_shared(daoData);
        };

        next_tx(&mut scenario, User2);
        {
            //check User2 balance
            let sui_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&sui_coin) == 100, 0);
            test_scenario::return_to_sender(&scenario, sui_coin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun market_test() {
        let scenario = prepare();
        init_for_dao_test(&mut scenario);

        let workId:ID;
        next_tx(&mut scenario, Creator);
        {
            let mymarket = test_scenario::take_shared<Market<Coin<SUI>>>(&scenario);
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);
            let work = test_scenario::take_from_sender<Work>(&scenario);
            let price = 50u64;

            workId = object::id(&work);
            market::list(&mut mymarket, work, price, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(mymarket);
            test_scenario::return_shared(globalConfig);
            test_scenario::return_shared(daoData);
        };

        mint_sui_to(User1, 100, &mut scenario);
        next_tx(&mut scenario, User1);
        {
            let mymarket = test_scenario::take_shared<Market<Coin<SUI>>>(&scenario);
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);
            let sui_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);

            //TODO check contribution before and after
            market::buy(&mut mymarket, &mut globalConfig, &mut daoData, workId, sui_coin, test_scenario::ctx(&mut scenario));
            
            test_scenario::return_shared(mymarket);
            test_scenario::return_shared(globalConfig);
            test_scenario::return_shared(daoData);
        };
        check_balance(User1, 50, &mut scenario);

        test_scenario::end(scenario);
    }

    #[test]
    fun advertisement_market_test() {
        let scenario = prepare();
        init_for_dao_test(&mut scenario);

        let workId:ID;
        next_tx(&mut scenario, Creator);
        {
            let work = test_scenario::take_from_sender<Work>(&scenario);
            workId = object::id(&work);

            test_scenario::return_to_sender(&scenario, work);
        };
        
        // list a advertisement listing
        let advertisementId:ID;
        next_tx(&mut scenario, User3);
        {
            let advertisementMarket = test_scenario::take_shared<AdvertisementMarket<Coin<SUI>>>(&scenario);
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            let content = b"advertisement description, a vedio, or a picture";

            // how much can pay
            let sui_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            let pay = coin::split(&mut sui_coin, 10, test_scenario::ctx(&mut scenario));
            let duration = 1000_000u64; // 

            advertisementId = market::list_advertisement(&mut advertisementMarket, &globalConfig, workId,
                 content, pay, duration, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(advertisementMarket);
            test_scenario::return_shared(globalConfig);
            test_scenario::return_to_sender(&scenario, sui_coin);
        };
        // owner of work accept this advertisement, he will receive payment
        next_tx(&mut scenario, Creator);
        {   
            let sender = tx_context::sender(test_scenario::ctx(&mut scenario));
            let advertisementMarket = test_scenario::take_shared<AdvertisementMarket<Coin<SUI>>>(&scenario);
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            let daoData = test_scenario::take_shared<DaoData>(&scenario);
            let work = test_scenario::take_from_sender<Work>(&scenario);
            let myclock = test_scenario::take_shared<Clock>(&scenario);

            let preContribition = dao::contribution(&daoData, sender);
            market::accept_advertisement(&mut advertisementMarket, &mut globalConfig, &mut daoData,
             &mut work, advertisementId, &myclock, test_scenario::ctx(&mut scenario));
            let curContribution = dao::contribution(&daoData, sender);
            assert!(preContribition + 1 == curContribution, 0);
        
            test_scenario::return_shared(advertisementMarket);
            test_scenario::return_shared(globalConfig);
            test_scenario::return_shared(daoData);
            test_scenario::return_shared(myclock);
            test_scenario::return_to_sender(&scenario, work);
        };
        check_balance(User3, 90, &mut scenario);


        // list another new advertisement
        next_tx(&mut scenario, User3);
        {
            let advertisementMarket = test_scenario::take_shared<AdvertisementMarket<Coin<SUI>>>(&scenario);
            let globalConfig = test_scenario::take_shared<GlobalConfig>(&scenario);
            let content = b"advertisement description, a vedio, or a picture";

            // how much can pay
            let sui_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            let pay = coin::split(&mut sui_coin, 10, test_scenario::ctx(&mut scenario));
            let duration = 1000_000u64; // 

            advertisementId = market::list_advertisement(&mut advertisementMarket, &globalConfig, workId,
                 content, pay, duration, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(advertisementMarket);
            test_scenario::return_shared(globalConfig);
            test_scenario::return_to_sender(&scenario, sui_coin);
        };
        // delete advertisement
        next_tx(&mut scenario, User3);
        {
            let advertisementMarket = test_scenario::take_shared<AdvertisementMarket<Coin<SUI>>>(&scenario);
            market::delete_advertisement(&mut advertisementMarket, advertisementId, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(advertisementMarket);
        };
        //TODO: check use balance. now only get recently coin.
        check_balance(User3, 10, &mut scenario);
        
        test_scenario::end(scenario);
    }

    // prepare before each test
    fun prepare() :Scenario {
        let scenario = test_scenario::begin(Creator);
        {
            let myclock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            clock::share_for_testing(myclock);

            create::test_init(test_scenario::ctx(&mut scenario));
            dao::test_init(test_scenario::ctx(&mut scenario));
            market::test_init(test_scenario::ctx(&mut scenario));
        };
        
        return (scenario)
    }

    fun register(scenario: &mut Scenario, who:address) {
        let golbalConfig = test_scenario::take_shared<GlobalConfig>(scenario);
        create::register(
            &mut golbalConfig,
            b"Jing",
            b"abc@gmail.com",
            b"blockchain technology blog",
            test_scenario::ctx(scenario)
        );
        assert!(create::contains_creator(&golbalConfig, who) == true, 0);
        test_scenario::return_shared(golbalConfig);
    }

    fun newWork(scenario: &mut Scenario):ID {
        let golbalConfig = test_scenario::take_shared<GlobalConfig>(scenario);
        let workId = create::new(
            &mut golbalConfig,
            b"Zk Proof",
            b"what is zk proof?...",
            test_scenario::ctx(scenario)
        );

        assert!(create::contains_work(&golbalConfig, workId) == true, 0);
        
        test_scenario::return_shared(golbalConfig);
        workId
    }

    fun like(workId:ID, ownerOfWork:address,scenario: &mut Scenario) {
        let globalConfig = test_scenario::take_shared<GlobalConfig>(scenario);
        create::like(&mut globalConfig, workId, test_scenario::ctx(scenario));

        let (workId, likes, owner)  = create::get_workInfo(&globalConfig, workId);
        assert!(workId == workId && vector::length(&likes)==1 && owner==ownerOfWork, 0);

        test_scenario::return_shared(globalConfig);
    }

    fun reward(globalConfig:&mut GlobalConfig,daoData:&mut DaoData,workId:ID, amount:Coin<SUI>, scenario:&mut Scenario) {
        create::reward(globalConfig, daoData, workId, amount, test_scenario::ctx(scenario));
    }

    fun timestamp(clock: &Clock): u64 {
        clock::timestamp_ms(clock)
    }

    fun init_for_dao_test(scenario: &mut Scenario) {
        {
            init_account_balance(User3, 100, test_scenario::ctx(scenario));
        };

        next_tx(scenario, Creator);
        register(scenario, Creator);

        next_tx(scenario, Creator);
        let workId = newWork(scenario);

        next_tx(scenario, User1);
        {
            let globalConfig = test_scenario::take_shared<GlobalConfig>(scenario);
            let daoData = test_scenario::take_shared<DaoData>(scenario);

            let sui_coin = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(scenario));
            reward(&mut globalConfig,&mut daoData, workId, sui_coin, scenario);

            test_scenario::return_shared(globalConfig);
            test_scenario::return_shared(daoData);
        };

        next_tx(scenario, Creator);
        {
            let globalConfig = test_scenario::take_shared<GlobalConfig>(scenario);
            create::collect_bonus(&mut globalConfig, test_scenario::ctx(scenario));
            test_scenario::return_shared(globalConfig);
        };
    }

    fun init_account_balance(account:address, value:u64, ctx:&mut TxContext){
        let coin = coin::mint_for_testing<SUI>(value, ctx);
        transfer::public_transfer(coin, account);
    }

    fun mint_sui_to(to:address, amount:u64,scenario:&mut Scenario) {
         next_tx(scenario, to);
         {
            let sui_coin = coin::mint_for_testing<SUI>(amount, test_scenario::ctx(scenario));
            transfer::public_transfer(sui_coin, to);
         };
    }

    fun check_balance(who:address, expectedBalance:u64, scenario:&mut Scenario) {
        next_tx(scenario, who);
        {
            let sui_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
            assert!(coin::value(&sui_coin) == expectedBalance, 0);
            test_scenario::return_to_sender(scenario, sui_coin);
        };
    }
}