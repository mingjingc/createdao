module createdao::dao {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::url::{Self, Url};
    use sui::clock::{Self, Clock};
    use sui::event;
    use std::string::{Self, String};
    use sui::dynamic_object_field as dof;
    
    //--------Friend module--------
    friend createdao::create;

    //-------Constant-------------
    const Proposal_Ready:u8 = 0;
    const Proposal_Success:u8 = 1;
    const Proposal_Executed:u8 = 2;
   
    //-------Error code-------------
    //const EDefault:u64 = 0;
    const EAlreadyVoted:u64 = 1;
    const EProposalExpired:u64 = 2;
    const EProposalVoteEnd:u64 = 3;
    const EProposalNotSuccess:u64 = 4;
    const EFundShortage: u64 = 5;

    //--------Object------------
    // DAO global data
    struct DaoData has key,store {
        id: UID,
        asset: Balance<SUI>, // DAO total asset

        contributions:Table<address, u64>, // record everyone contribition 
        totalContribution:u64,
    }

    struct Proposal has key,store {
        id: UID,
        task: String, // what do you want to do
        // below three params is applicant information
        website: Url,  // applicant website
        contact: String, // applicant contact information
        receiver: address, // the wallet address which can receive fund
        needFunds:u64, // how money does applicant need

        supporters:Table<address, u64>, // supporter --> number of votes
        totalSupport:u64, // total votes
        
        status: u8, // proposal status:ready/success/executed
        expire:u64, // proposal expiration time
    }

    //--------Event----------
    struct EventNewProposal has drop, copy {
        from: address,
        proposalId: ID,
    }

    struct EventProposalSuccess has drop, copy {
        proposalId: ID, // proposal object id
        receiver: address,
        needFunds: u64,
    }

    ///-----Witness----------------
    struct DAO has drop {}

    ///-----Constructor------------
    fun init(_witness: DAO, ctx:&mut TxContext) {
        let daoData = DaoData {
            id: object::new(ctx),
            asset: balance::zero(),

            contributions: table::new(ctx),
            totalContribution: 0,
        };
        
        transfer::share_object(daoData);
    }

    ///---------------Function----------------
    // new a proposal(everyone can do)
    // @param task: task descprition
    // @param website: applicant website
    // @param contact: applicant contact information
    // @param needFunds: how money does the applicant want to finish this task
    public entry fun newProposal(daoData:&mut DaoData, task:vector<u8>, website:vector<u8>,contact:vector<u8>, needFunds:u64, expire:u64, ctx: &mut TxContext): ID {
        let proposal = Proposal {
            id: object::new(ctx),
            task: string::utf8(task),

            website: url::new_unsafe_from_bytes(website),
            contact: string::utf8(contact),
            receiver: tx_context::sender(ctx),
            needFunds: needFunds,

            supporters:table::new(ctx),
            totalSupport: 0,
            
            expire:expire,
            status:Proposal_Ready,
        };

        let proposalId = object::id(&proposal);
        // add proposal as a child object of daoData
        dof::add(&mut daoData.id, proposalId, proposal);

        event::emit(EventNewProposal{
            from: tx_context::sender(ctx),
            proposalId: proposalId,
        });
        proposalId
    }

    // vote to the proposal. who has contribution to the DAO can do it.
    // @param daoData: gobal DAO data, only one object for whole package
    // @param proposalId: proposal object ID
    public entry fun vote(daoData:&mut DaoData, proposalId:ID, clock: &Clock, ctx:&mut TxContext) {
        let proposal = dof::borrow_mut<ID, Proposal>(&mut daoData.id, proposalId);
        // validate proposal
        assert!(proposal.expire > timestamp(clock), EProposalExpired);
        assert!(proposal.status == Proposal_Ready, EProposalVoteEnd);

        let sender = tx_context::sender(ctx); 
        let weight = table::borrow(&daoData.contributions, sender);
        if (*weight == 0) {
            return
        };

        assert!(table::contains(&proposal.supporters, sender) == false, EAlreadyVoted);
        table::add(&mut proposal.supporters, sender, *weight);
        proposal.totalSupport = proposal.totalSupport + *weight;

        if (daoData.totalContribution/2 <  proposal.totalSupport) {
            proposal.status = Proposal_Success;

            event::emit(EventProposalSuccess{
                proposalId: proposalId,
                receiver: proposal.receiver,
                needFunds: proposal.needFunds,
            });
        };
    }
    
    // execute the proposal if it success.
    // @param daoData: gobal DAO data, only one object for whole package
    // @param proposalId: proposal object ID
    public entry fun execute_proposal(daoData:&mut DaoData, proposalId:ID, clock: &Clock, ctx:&mut TxContext) {
        let proposal = dof::borrow_mut<ID, Proposal>(&mut daoData.id, proposalId);
        assert!(proposal.status == Proposal_Success, EProposalNotSuccess);
        assert!(proposal.expire > timestamp(clock), EProposalExpired);
        assert!(proposal.needFunds <  balance::value(&daoData.asset), EFundShortage);

        let b = balance::split(&mut daoData.asset, proposal.needFunds);
        transfer::public_transfer(coin::from_balance(b, ctx), proposal.receiver);
        // update proposal status
        proposal.status = Proposal_Executed;
    }

    ///--------------Friend function, only call by friendly modules-----------------
    public(friend) fun deposit(who: address, daoData:&mut DaoData, amount:Coin<SUI>) {
       let value = coin::value(&amount);
       let b =  coin::into_balance(amount);
       balance::join(&mut daoData.asset, b);

        // update user contribution
       let contribution = value;
       if (table::contains(&daoData.contributions, who) == false) {
            table::add(&mut daoData.contributions, who, contribution)
       } else {
            let user_contribition = table::borrow_mut(&mut daoData.contributions, who);
            *user_contribition = *user_contribition + contribution;
       };
       daoData.totalContribution = daoData.totalContribution + contribution;
    }

    ///-------------Getter-------------------
    public fun asset_value(daoData:&DaoData): u64 {
        balance::value(&daoData.asset)
    }

    public fun contribution(daoData:&DaoData, who:address): u64 {
        if (table::contains(&daoData.contributions, who) == true) {
            return *table::borrow(&daoData.contributions, who)
        };

        0
    }

    public fun borrow_proposal(daoData:&DaoData, proposalId:ID):&Proposal {
        dof::borrow<ID, Proposal>(&daoData.id, proposalId)
    }

    public fun proposal_status(proposal:&Proposal):u8{
        proposal.status
    }

    fun timestamp(clock: &Clock): u64 {
        clock::timestamp_ms(clock)
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        init(DAO{}, ctx);
    }
}