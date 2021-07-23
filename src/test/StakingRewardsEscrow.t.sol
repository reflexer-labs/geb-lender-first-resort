pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../GebLenderFirstResortRewardsVested.sol";
import {RewardDripper} from "../RewardDripper.sol";
import {StakingRewardsEscrow} from "../StakingRewardsEscrow.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
}

contract AuctionHouseMock {
    uint public activeStakedTokenAuctions;
    DSToken public tokenToAuction;

    constructor(address tokenToAuction_) public {
        tokenToAuction = DSToken(tokenToAuction_);
    }

    function startAuction(uint256 tokensToAuction, uint256) external returns (uint256) {
        tokenToAuction.transferFrom(msg.sender, address(this), tokensToAuction);
        return activeStakedTokenAuctions++;
    }
}
contract AccountingEngineMock {
    uint public debtAuctionBidSize = 100 ether;
    uint public unqueuedUnauctionedDebt = 0 ether;

    function modifyParameters(bytes32 param, uint val) public {
        if (param == "debtAuctionBidSize") debtAuctionBidSize = val;
        else if (param == "unqueuedUnauctionedDebt") unqueuedUnauctionedDebt = val;
        else revert("unrecognized param");
    }
}
contract SAFEEngineMock {
    mapping (address => uint256)                       public coinBalance;      // [rad]
    // Amount of debt held by an account. Coins & debt are like matter and antimatter. They nullify each other
    mapping (address => uint256)                       public debtBalance;      // [rad]

    function modifyBalance(bytes32 param, address who, uint val) public {
        if (param == "coin") coinBalance[who] = val;
        else if (param == "debt") debtBalance[who] = val;
        else revert("unrecognized param");
    }
}

contract Caller {
    GebLenderFirstResortRewardsVested stakingPool;

    constructor (GebLenderFirstResortRewardsVested add) public {
        stakingPool = add;
    }

    function doModifyParameters(bytes32 param, uint256 data) public {
        stakingPool.modifyParameters(param, data);
    }

    function doModifyParameters(bytes32 param, address data) public {
        stakingPool.modifyParameters(param, data);
    }

    function doAddAuthorization(address data) public {
        stakingPool.addAuthorization(data);
    }

    function doRemoveAuthorization(address data) public {
        stakingPool.removeAuthorization(data);
    }

    function doGetRewards() public {
        stakingPool.getRewards();
    }

    function doJoin(uint wad) public {
        stakingPool.ancestorPool().token().approve(address(stakingPool), uint(-1));
        stakingPool.join(wad);
    }

    function doRequestExit(uint wad) public {
        stakingPool.requestExit(wad);
    }

    function doExit() public {
        stakingPool.exit();
    }

    function doApprove(DSToken token, address guy) public {
        token.approve(guy);
    }
}

contract StakingRewardsEscrowTest is DSTest {
    Hevm hevm;
    DSToken rewardToken;
    DSToken ancestor;
    DSToken descendant;
    GebLenderFirstResortRewardsVested stakingPool;
    AuctionHouseMock auctionHouse;
    AccountingEngineMock accountingEngine;
    SAFEEngineMock safeEngine;
    RewardDripper rewardDripper;
    StakingRewardsEscrow escrow;
    Caller unauth;

    uint maxDelay = 48 weeks;
    uint exitDelay = 1 weeks;
    uint minStakedTokensToKeep = 10 ether;
    uint tokensToAuction  = 100 ether;
    uint systemCoinsToRequest = 1000 ether;
    uint percentageVested = 70;
    uint escrowDuration = 180 days;
    uint durationToStartEscrow = 14 days;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        hevm.roll(5000000);
        hevm.warp(1000000001);

        rewardToken      = new DSToken("PROT", "PROT");
        ancestor         = new DSToken("LP", "LP");
        descendant       = new DSToken("LP_DESC", "LP_DESC");
        auctionHouse     = new AuctionHouseMock(address(ancestor));
        accountingEngine = new AccountingEngineMock();
        safeEngine       = new SAFEEngineMock();
        rewardDripper    = new RewardDripper(
            address(this),        // requestor
            address(rewardToken),
            1 ether               // rewardPerBlock
        );

        stakingPool = new GebLenderFirstResortRewardsVested(
            address(ancestor),
            address(descendant),
            address(rewardToken),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            address(rewardDripper),
            maxDelay,
            exitDelay,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest,
            percentageVested
        );
        escrow = new StakingRewardsEscrow(address(stakingPool), address(rewardToken), escrowDuration, durationToStartEscrow);
        stakingPool.modifyParameters("escrow", address(escrow));

        rewardDripper.modifyParameters("requestor", address(stakingPool));
        rewardToken.mint(address(rewardDripper), 10000000 ether);

        ancestor.mint(address(this), 1000000000 ether);
        descendant.setOwner(address(stakingPool));

        descendant.approve(address(stakingPool));

        unauth = new Caller(stakingPool);
    }

    function test_setup() public {
        assertEq(address(stakingPool.ancestorPool().token()), address(ancestor));
        assertEq(address(stakingPool.descendant()), address(descendant));
        assertEq(address(stakingPool.auctionHouse()), address(auctionHouse));
        assertEq(address(stakingPool.rewardDripper()), address(rewardDripper));
        assertEq(address(stakingPool.escrow()), address(escrow));
        assertEq(address(stakingPool.rewardPool().token()), address(rewardToken));
        assertEq(stakingPool.MAX_DELAY(), maxDelay);
        assertEq(stakingPool.exitDelay(), exitDelay);
        assertEq(stakingPool.escrowPaused(), 0);
        assertEq(stakingPool.minStakedTokensToKeep(), minStakedTokensToKeep);
        assertEq(stakingPool.tokensToAuction(), tokensToAuction);
        assertEq(stakingPool.systemCoinsToRequest(), systemCoinsToRequest);
        assertEq(stakingPool.authorizedAccounts(address(this)), 1);
        assertEq(stakingPool.maxConcurrentAuctions(), uint(-1));
        assertEq(stakingPool.stakedSupply(), 0);
        assertTrue(stakingPool.canJoin());

        assertEq(escrow.slotsToClaim(), escrow.MAX_SLOTS_TO_CLAIM());
        assertEq(escrow.durationToStartEscrow(), durationToStartEscrow);
        assertEq(escrow.escrowDuration(), escrowDuration);
        assertEq(address(escrow.token()), address(rewardToken));
        assertEq(escrow.escrowRequestor(), address(stakingPool));
        assertEq(escrow.authorizedAccounts(address(this)), 1);
    }
    function test_add_authorization() public {
        escrow.addAuthorization(address(0xfab));
        assertEq(escrow.authorizedAccounts(address(0xfab)), 1);
    }
    function test_remove_authorization() public {
        escrow.removeAuthorization(address(this));
        assertEq(escrow.authorizedAccounts(address(this)), 0);
    }
    function test_modify_parameters() public {
        escrow.modifyParameters("escrowRequestor", address(0x1234));
        assertEq(address(escrow.escrowRequestor()), address(0x1234));

        escrow.modifyParameters("escrowDuration", 200 days);
        assertEq(escrow.escrowDuration(), 200 days);

        escrow.modifyParameters("durationToStartEscrow", 4);
        assertEq(escrow.durationToStartEscrow(), 4);

        escrow.modifyParameters("slotsToClaim", 5);
        assertEq(escrow.slotsToClaim(), 5);
    }
    function test_exit_rewards_1(uint amount, uint blockDelay) public {
        amount = amount % 10**24 + 1; // up to 1mm staked
        blockDelay = blockDelay % 100 + 1; // up to 1000 blocks
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // request exit
        hevm.roll(block.number + blockDelay);
        stakingPool.requestExit(amount);

        // exit
        hevm.warp(now + exitDelay);
        uint256 price = stakingPool.exitPrice(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        stakingPool.exit();
        assertEq(ancestor.balanceOf(address(this)), previousBalance + price);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
        assertTrue(rewardToken.balanceOf(address(this)) >= (blockDelay * 1 ether) * (100 - percentageVested) / 100 - 1);
    }
    function test_exit_rewards_2_users(uint amount) public {
        amount = amount % 10**24 + 1; // non null up to 1mm
        Caller user1 = new Caller(stakingPool);
        ancestor.transfer(address(user1), amount);
        Caller user2 = new Caller(stakingPool);
        ancestor.transfer(address(user2), amount);

        // join
        user1.doJoin(amount);
        user2.doJoin(amount);

        // request exit
        hevm.roll(block.number + 32); // 32 blocks

        user1.doApprove(descendant, address(stakingPool));
        user2.doApprove(descendant, address(stakingPool));

        user1.doRequestExit(amount);
        user2.doRequestExit(amount);

        // exit
        hevm.warp(now + exitDelay);

        user1.doExit();
        user2.doExit();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 16 ether * (100 - percentageVested) / 100 -1);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 16 ether * (100 - percentageVested) / 100 -1);
    }
    function test_get_rewards() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        hevm.roll(block.number + 10); // 10 blocks

        stakingPool.getRewards();
        assertEq(rewardToken.balanceOf(address(this)), 20 ether * (100 - percentageVested) / 100);

        hevm.warp(now + escrow.durationToStartEscrow() + 1);
        hevm.roll(block.number + 8); // 8 blocks

        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 28 ether * (100 - percentageVested) / 100 - 1);

        assertEq(escrow.getTokensBeingEscrowed(address(this)), 19600000000000000000);
    }
    function test_rewards_after_slashing() public {
        uint amount = 1000 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        uint previousDescendantBalance = stakingPool.descendantBalanceOf(address(this));

        // auction
        stakingPool.auctionAncestorTokens();

        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
        assertEq(stakingPool.descendantBalanceOf(address(this)), previousDescendantBalance);
        assertEq(ancestor.balanceOf(address(auctionHouse)), 100 ether);

        // exiting (after slash)
        hevm.roll(block.number + 32); // 32 blocks
        stakingPool.requestExit(amount);
        hevm.warp(now + exitDelay);
        uint256 price = stakingPool.exitPrice(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 90 ether); // above water

        stakingPool.exit();
        assertEq(ancestor.balanceOf(address(this)), previousBalance + price);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
        assertEq(rewardToken.balanceOf(address(this)), 32 ether * (100 - percentageVested) / 100); // 1 eth per block

        assertEq(escrow.getTokensBeingEscrowed(address(this)), 22400000000000000000);
    }
    function test_multi_escrow_slots_from_get_rewards() public {
        assertEq(address(escrow.escrowRequestor()), address(stakingPool));

        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();
          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);

          (
            uint256 total,
            uint256 startDate,
            uint256 duration,
            uint256 claimedUntil,
            uint256 amountClaimed
          ) = escrow.escrows(address(this), i);

          assertEq(total, 7 ether);
          assertEq(startDate, claimedUntil);
          assertEq(duration, escrow.escrowDuration());
          assertEq(claimedUntil, now - escrow.durationToStartEscrow() - 1);
          assertEq(amountClaimed, 0);
        }

        assertEq(escrow.getTokensBeingEscrowed(address(this)), 70 ether);
    }
    function test_escrow_same_slot_multiple_times() public {
        assertEq(address(escrow.escrowRequestor()), address(stakingPool));

        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));
        uint initialDate = now;

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();

          hevm.warp(now + escrow.durationToStartEscrow() / 20);

          (
            uint256 total,
            uint256 startDate,
            uint256 duration,
            uint256 claimedUntil,
            uint256 amountClaimed
          ) = escrow.escrows(address(this), 0);

          assertEq(total, 7 ether * (i + 1));
          assertEq(startDate, claimedUntil);
          assertEq(duration, escrow.escrowDuration());
          assertEq(claimedUntil, initialDate);
          assertEq(amountClaimed, 0);
        }

        assertEq(escrow.currentEscrowSlot(address(this)), 1);
        assertEq(escrow.getTokensBeingEscrowed(address(this)), 70 ether);
    }
    function test_get_claimableTokens_no_slot() public {
        assertEq(escrow.getClaimableTokens(address(0x123)), 0);
    }
    function test_get_claimable_token_no_time_passed() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        hevm.roll(block.number + 10); // 10 blocks
        stakingPool.getRewards();

        assertEq(escrow.getClaimableTokens(address(this)), 0);
    }
    function test_get_claimable_token_half_time_passed() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect
        (
          uint256 total,
          ,
          ,
          ,
        ) = escrow.escrows(address(this), 0);
        assertEq(total, 0);

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        hevm.roll(block.number + 10); // 10 blocks
        stakingPool.getRewards();

        (
          total,
          ,
          ,
          ,
        ) = escrow.escrows(address(this), 0);
        assertEq(total, 14 ether);

        hevm.warp(now + escrow.escrowDuration() / 2);
        assertEq(escrow.getClaimableTokens(address(this)), 6999999999993216000);
    }
    function test_get_claimable_token_all_time_passed() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect
        (
          uint256 total,
          ,
          ,
          ,
        ) = escrow.escrows(address(this), 0);
        assertEq(total, 0);

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        hevm.roll(block.number + 10); // 10 blocks
        stakingPool.getRewards();

        (
          total,
          ,
          ,
          ,
        ) = escrow.escrows(address(this), 0);
        assertEq(total, 14 ether);

        hevm.warp(now + escrow.escrowDuration() / 2);
        assertEq(escrow.getClaimableTokens(address(this)), 6999999999993216000);
        escrow.claimTokens(address(this));

        assertEq(escrow.getTokensBeingEscrowed(address(this)), 7000000000006784000);

        hevm.warp(now + escrow.escrowDuration() / 2);
        assertEq(escrow.getClaimableTokens(address(this)), 7000000000006784000);
        escrow.claimTokens(address(this));

        assertEq(rewardToken.balanceOf(address(escrow)), 0);

        (
          uint256 totalTokens,
          uint256 startDate,
          uint256 duration,
          uint256 claimedUntil,
          uint256 amountClaimed
        ) = escrow.escrows(address(this), 0);

        assertEq(totalTokens, 14 ether);
        assertEq(startDate, now - escrow.escrowDuration());
        assertEq(duration, escrow.escrowDuration());
        assertEq(claimedUntil, startDate + duration);
        assertEq(amountClaimed, totalTokens);

        assertEq(rewardToken.balanceOf(address(escrow)), 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));
        assertEq(escrow.getTokensBeingEscrowed(address(this)), 0);
    }
    function test_multi_slot_get_claimable_tokens() public {
        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();
          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);
        }

        for (uint i = 0; i < 11; i++) {
            escrow.claimTokens(address(this));
            hevm.warp(now + escrow.escrowDuration() / 10);
        }

        assertEq(rewardToken.balanceOf(address(escrow)), 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));
    }
    function test_max_slots_smaller_than_escrow_slots() public {
        escrow.modifyParameters("slotsToClaim", 3);

        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10);

          stakingPool.getRewards();
          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);
        }

        for (uint i = 0; i < 3; i++) {
            escrow.claimTokens(address(this));
            hevm.warp(now + escrow.escrowDuration() / 10);
        }

        assertEq(escrow.getTokensBeingEscrowed(address(this)), 50244440843623866736);

        // Checks
        (
          uint256 totalTokens,
          ,
          ,
          ,
          uint256 amountClaimed
        ) = escrow.escrows(address(this), 4);
        assertEq(amountClaimed, 0);
        (
          totalTokens,
          ,
          ,
          ,
          amountClaimed
        ) = escrow.escrows(address(this), 3);
        assertEq(escrow.oldestEscrowSlot(address(this)), 0);

        while (escrow.oldestEscrowSlot(address(this)) < escrow.currentEscrowSlot(address(this))) {
            escrow.claimTokens(address(this));
            hevm.warp(now + escrow.escrowDuration() / 10);

            (
              totalTokens,
              ,
              ,
              ,
              amountClaimed
            ) = escrow.escrows(address(this), escrow.currentEscrowSlot(address(this)));
        }

        (
          uint total,
          uint startDate,
          uint duration,
          uint claimedUntil,
          uint claimed
        ) = escrow.escrows(address(this), escrow.currentEscrowSlot(address(this)));
        assertEq(claimed, total);

        assertEq(rewardToken.balanceOf(address(escrow)), 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));
    }
    function test_claim_all_slots_claim_new_slot() public {
        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();
          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);
        }

        for (uint i = 0; i < 11; i++) {
            escrow.claimTokens(address(this));
            hevm.warp(now + escrow.escrowDuration() / 10);
        }

        // 11th slot
        hevm.roll(block.number + 10); // 10 blocks
        stakingPool.getRewards();
        assertEq(escrow.currentEscrowSlot(address(this)), 11);
        assertTrue(rewardToken.balanceOf(address(escrow)) > 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)) - 1);

        hevm.warp(now + escrow.escrowDuration() + 1);
        escrow.claimTokens(address(this));
        assertEq(rewardToken.balanceOf(address(escrow)), 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));
    }
    function test_claim_slots_multi_user() public {
        uint amount = 10 ether;
        ancestor.transfer(address(unauth), amount);
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);
        unauth.doJoin(amount);

        uint256 escrowedForUnauth;
        uint256 currentEscrowedRewards;

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();

          currentEscrowedRewards = rewardToken.balanceOf(address(escrow));
          unauth.doGetRewards();
          escrowedForUnauth = escrowedForUnauth + (rewardToken.balanceOf(address(escrow)) - currentEscrowedRewards);

          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);
          assertEq(escrow.currentEscrowSlot(address(unauth)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);
        }

        for (uint i = 0; i < 11; i++) {
            escrow.claimTokens(address(this));
            hevm.warp(now + escrow.escrowDuration() / 10);
        }

        assertEq(rewardToken.balanceOf(address(escrow)), escrowedForUnauth);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));

        escrow.claimTokens(address(unauth));

        assertEq(rewardToken.balanceOf(address(escrow)), 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));
        assertEq(escrow.oldestEscrowSlot(address(unauth)), escrow.currentEscrowSlot(address(unauth)));
    }
    function test_wait_until_all_escrowed_claim() public {
        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();
          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);
        }

        hevm.warp(now + escrow.escrowDuration() + 1);
        escrow.claimTokens(address(this));

        assertEq(rewardToken.balanceOf(address(escrow)), 0);
        assertEq(escrow.oldestEscrowSlot(address(this)), escrow.currentEscrowSlot(address(this)));
    }
    function test_wait_until_all_escrowed_claim_limited_by_max_slots() public {
        escrow.modifyParameters("slotsToClaim", 2);

        uint amount = 10 ether;
        ancestor.approve(address(stakingPool), uint(-1));

        // join
        stakingPool.join(amount);

        for (uint i = 0; i < 10; i++) {
          hevm.roll(block.number + 10); // 10 blocks

          stakingPool.getRewards();
          assertEq(escrow.currentEscrowSlot(address(this)), i + 1);

          hevm.warp(now + escrow.durationToStartEscrow() + 1);
        }

        // First two slots only
        uint total;
        uint claimed;

        hevm.warp(now + escrow.escrowDuration() + 1);
        escrow.claimTokens(address(this));

        for (uint i = 0; i < 2; i++) {
          (
            total,
            ,
            ,
            ,
            claimed
          ) = escrow.escrows(address(this), i);
          assertEq(claimed, total);
          assertTrue(claimed > 0);
        }

        (
          total,
          ,
          ,
          ,
          claimed
        ) = escrow.escrows(address(this), 3);
        assertEq(claimed, 0);

        // Next two slots
        escrow.claimTokens(address(this));

        for (uint i = 2; i < 4; i++) {
          (
            total,
            ,
            ,
            ,
            claimed
          ) = escrow.escrows(address(this), i);
          assertEq(claimed, total);
          assertTrue(claimed > 0);
        }

        (
          total,
          ,
          ,
          ,
          claimed
        ) = escrow.escrows(address(this), 4);
        assertEq(claimed, 0);

        // The rest of the slots
        escrow.claimTokens(address(this));
        escrow.claimTokens(address(this));
        escrow.claimTokens(address(this));

        for (uint i = 4; i < 10; i++) {
          (
            total,
            ,
            ,
            ,
            claimed
          ) = escrow.escrows(address(this), i);
          assertEq(claimed, total);
          assertTrue(claimed > 0);
        }
    }
}
