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
   
    friend createdao::create;

    const Proposal_Ready:u8 = 0;
    const Proposal_Success:u8 = 1;
    const Proposal_Executed:u8 = 2;

    const EDefault:u64 = 0;
    const EAlreadyVoted:u64 = 1;
    const EProposalExpired:u64 = 2;
    const EProposalVoteEnd:u64 = 3;
    const EProposalNotSuccess:u64 = 4;
    const EFoundShortage: u64 = 5;

    struct DaoData has key,store {
        id: UID,
        asset: Balance<SUI>,

        contributions:Table<address, u64>,
        totalContribution:u64,
    }

    struct Proposal has key,store {
        id: UID,
        task: String,

        // who get the founds after successful application
        website: Url,
        contact: String,
        receiver: address,
        needFounds:u64,

        supporters:Table<address, u64>,
        totalSupport:u64,
        
        status: u8,
        expire:u64,
    }

    struct EventProposalSuccess has drop, copy {
        proposalId: ID,
        receiver: address,
        needFounds: u64,
    }

    struct DAO has drop {}

    fun init(_witness: DAO, ctx:&mut TxContext) {
        let daoData = DaoData {
            id: object::new(ctx),
            asset: balance::zero(),

            contributions: table::new(ctx),
            totalContribution: 0,
        };
        
        transfer::share_object(daoData);
    }

    public entry fun newProposal(task:vector<u8>, website:vector<u8>,contact:vector<u8>, needFounds:u64, expire:u64, ctx: &mut TxContext): ID {
        let proposal = Proposal {
            id: object::new(ctx),
            task: string::utf8(task),

            website: url::new_unsafe_from_bytes(website),
            contact: string::utf8(contact),
            receiver: tx_context::sender(ctx),
            needFounds: needFounds,

            supporters:table::new(ctx),
            totalSupport: 0,
            
            expire:expire,
            status:Proposal_Ready,
        };

        let proposalId = object::id(&proposal);
        transfer::share_object(proposal);

        proposalId
    }

    public entry fun vote(daoData:&DaoData, proposal:&mut Proposal, clock: &Clock,ctx:&mut TxContext) {
        check_proposal(proposal, clock);

        let sender = tx_context::sender(ctx); 
        let weight = table::borrow(&daoData.contributions, sender);

        assert!(table::contains(&proposal.supporters, sender) == false, EAlreadyVoted);
        table::add(&mut proposal.supporters, sender, *weight);
        proposal.totalSupport = proposal.totalSupport + *weight;

        if (daoData.totalContribution/2 <  proposal.totalSupport) {
            proposal.status = Proposal_Success;

            event::emit(EventProposalSuccess{
                proposalId: object::id(proposal),
                receiver: proposal.receiver,
                needFounds: proposal.needFounds,
            });
        };
    }

    public entry fun execute_proposal(daoData:&mut DaoData, proposal:&mut Proposal, clock: &Clock, ctx:&mut TxContext) {
        assert!(proposal.status == Proposal_Success, EProposalNotSuccess);
        assert!(proposal.expire > timestamp(clock), EProposalExpired);
        assert!(proposal.needFounds < asset_value(daoData), EFoundShortage);

        let b = balance::split(&mut daoData.asset, proposal.needFounds);
        transfer::public_transfer(coin::from_balance(b, ctx), proposal.receiver);
        // update proposal status
        proposal.status = Proposal_Executed;
    }

    public(friend) fun deposit(who: address, daoData:&mut DaoData, amount:Coin<SUI>) {
       let value = coin::value(&amount);
       let b =  coin::into_balance(amount);
       balance::join(&mut daoData.asset, b);

        // update user contribution
       let contribution = value/10;
       if (table::contains(&daoData.contributions, who) == false) {
            table::add(&mut daoData.contributions, who, contribution)
       } else {
            let user_contribition = table::borrow_mut(&mut daoData.contributions, who);
            *user_contribition = *user_contribition + contribution;
       };
       daoData.totalContribution = daoData.totalContribution + contribution;
    }

    fun check_proposal(proposal:&Proposal, clock:&Clock) {
        assert!(proposal.expire > timestamp(clock), EProposalExpired);
        assert!(proposal.status == Proposal_Ready, EProposalVoteEnd);
    }

    public entry fun asset_value(daoData:&DaoData): u64 {
        balance::value(&daoData.asset)
    }

    public entry fun contribution(who:address, daoData:&DaoData): u64 {
        if (table::contains(&daoData.contributions, who) == true) {
            return *table::borrow(&daoData.contributions, who)
        };

        0
    }

    public entry fun proposal_status(proposal:&Proposal):u8{
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