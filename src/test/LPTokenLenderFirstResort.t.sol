pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../LPTokenLenderFirstResort.sol";
import {RewardDripper} from "../RewardDripper.sol";

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
    LPTokenLenderFirstResort stakingPool;

    constructor (LPTokenLenderFirstResort add) public {
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
        stakingPool.ancestor().approve(address(stakingPool), uint(-1));
        stakingPool.join(wad);
    }

    function doRequestExit() public {
        stakingPool.requestExit();
    }

    function doExit(uint wad) public {
        stakingPool.descendant().approve(address(stakingPool), uint(-1));
        stakingPool.exit(wad);
    }
}

contract LPTokenLenderFirstResortTest is DSTest {
    Hevm hevm;
    DSToken rewardToken;
    DSToken ancestor;
    DSToken descendant;
    LPTokenLenderFirstResort stakingPool;
    AuctionHouseMock auctionHouse;
    AccountingEngineMock accountingEngine;
    SAFEEngineMock safeEngine;
    RewardDripper rewardDripper;
    Caller unauth;

    uint maxDelay = 48 weeks;
    uint minExitWindow = 12 hours;
    uint maxExitWindow = 30 days;
    uint exitDelay = 1 weeks;
    uint exitWindow = 1 days;
    uint minStakedTokensToKeep = 10 ether;
    uint tokensToAuction  = 100 ether;
    uint systemCoinsToRequest = 1000 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        hevm.roll(1);
        hevm.warp(100000001);

        rewardToken = new DSToken("PROT", "PROT");
        ancestor = new DSToken("LP", "LP");
        descendant = new DSToken("POOL", "POOL");
        auctionHouse = new AuctionHouseMock(address(ancestor));
        accountingEngine = new AccountingEngineMock();
        safeEngine = new SAFEEngineMock();
        rewardDripper = new RewardDripper(
            address(this),        // requestor
            address(rewardToken),
            1 ether               // rewardPerBlock
        );

        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );

        rewardDripper.modifyParameters("requestor", address(stakingPool));
        rewardToken.mint(address(rewardDripper), 10000000 ether);

        ancestor.mint(address(this), 1000000000 ether);
        descendant.setOwner(address(stakingPool));
        unauth = new Caller(stakingPool);
    }

    function test_setup() public {
        assertEq(address(stakingPool.ancestor()), address(ancestor));
        assertEq(address(stakingPool.descendant()), address(descendant));
        assertEq(address(stakingPool.auctionHouse()), address(auctionHouse));
        assertEq(address(stakingPool.rewardDripper()), address(rewardDripper));
        assertEq(address(stakingPool.rewardToken()), address(rewardToken));
        assertEq(stakingPool.MAX_DELAY(), maxDelay);
        assertEq(stakingPool.MIN_EXIT_WINDOW(), minExitWindow);
        assertEq(stakingPool.MAX_EXIT_WINDOW(), maxExitWindow);
        assertEq(stakingPool.exitDelay(), exitDelay);
        assertEq(stakingPool.exitWindow(), exitWindow);
        assertEq(stakingPool.minStakedTokensToKeep(), minStakedTokensToKeep);
        assertEq(stakingPool.tokensToAuction(), tokensToAuction);
        assertEq(stakingPool.systemCoinsToRequest(), systemCoinsToRequest);
        assertEq(stakingPool.authorizedAccounts(address(this)), 1);
        assertEq(stakingPool.maxConcurrentAuctions(), uint(-1));
        assertTrue(stakingPool.canJoin());
    }

    function testFail_setup_invalid_maxDelay() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            0,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_same_ancestor_rewards_tokens() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(rewardToken),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            0,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_maxExitWindow() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            0,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_maxExitWindow2() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            minExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_minExitWindow() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            0,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_exitWindow() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            minExitWindow - 1,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_exitWindow2() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            maxExitWindow + 1,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_minStakedTokensToKeep() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            0,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_tokensToAuction() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            0,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_systemCoinsToRequest() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            0
        );
    }

    function testFail_setup_invalid_auctionHouse() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(0),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_accountingEngine() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(0),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_safeEngine() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(0),
            address(rewardDripper),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function testFail_setup_invalid_rewardsDripper() public {
        stakingPool = new LPTokenLenderFirstResort(
            address(ancestor),
            address(descendant),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(0),
            maxDelay,
            minExitWindow,
            maxExitWindow,
            exitDelay,
            exitWindow,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );
    }

    function test_add_authorization() public {
        stakingPool.addAuthorization(address(0xfab));
        assertEq(stakingPool.authorizedAccounts(address(0xfab)), 1);
    }

    function test_remove_authorization() public {
        stakingPool.removeAuthorization(address(this));
        assertEq(stakingPool.authorizedAccounts(address(this)), 0);
    }

    function testFail_add_authorization_unauthorized() public {
        unauth.doAddAuthorization(address(0xfab));
    }

    function testFail_remove_authorization_unauthorized() public {
        unauth.doRemoveAuthorization(address(this));
    }

    function test_modify_parameters() public {
        stakingPool.modifyParameters("exitDelay", maxDelay - 10);
        assertEq(stakingPool.exitDelay(), maxDelay - 10);

        stakingPool.modifyParameters("exitWindow", maxExitWindow - 10);
        assertEq(stakingPool.exitWindow(), maxExitWindow - 10);

        stakingPool.modifyParameters("minStakedTokensToKeep", 3);
        assertEq(stakingPool.minStakedTokensToKeep(), 3);

        stakingPool.modifyParameters("tokensToAuction", 4);
        assertEq(stakingPool.tokensToAuction(), 4);

        stakingPool.modifyParameters("systemCoinsToRequest", 5);
        assertEq(stakingPool.systemCoinsToRequest(), 5);

        stakingPool.modifyParameters("maxConcurrentAuctions", 6);
        assertEq(stakingPool.maxConcurrentAuctions(), 6);

        stakingPool.modifyParameters("auctionHouse", address(3));
        assertEq(address(stakingPool.auctionHouse()), address(3));

        stakingPool.modifyParameters("accountingEngine", address(4));
        assertEq(address(stakingPool.accountingEngine()), address(4));

        stakingPool.modifyParameters("rewardDripper", address(5));
        assertEq(address(stakingPool.rewardDripper()), address(5));
    }

    function testFail_modify_parameters_null_address() public {
        stakingPool.modifyParameters("rewardDripper", address(0));
    }

    function testFail_modify_parameters_invalid_param_address() public {
        stakingPool.modifyParameters("invalid", address(1));
    }

    function testFail_modify_parameters_invalid_param_uint() public {
        stakingPool.modifyParameters("invalid", 1);
    }

    function testFail_modify_parameters_invalid_exit_delay() public {
        stakingPool.modifyParameters("exitDelay", maxDelay + 1);
    }

    function testFail_modify_parameters_invalid_exit_window() public {
        stakingPool.modifyParameters("exitWindow", maxExitWindow + 1);
    }

    function testFail_modify_parameters_invalid_exit_window2() public {
        stakingPool.modifyParameters("exitWindow", minExitWindow - 1);
    }

    function testFail_modify_parameters_invalid_min_tokens_to_keep() public {
        stakingPool.modifyParameters("minTokensToKeep", 0);
    }

    function testFail_modify_parameters_invalid_tokens_to_auction() public {
        stakingPool.modifyParameters("tokensToAuction", 0);
    }

    function testFail_modify_parameters_invalid_system_coins_to_request() public {
        stakingPool.modifyParameters("systemCoinsToRequest", 0);
    }

    function testFail_modify_parameters_invalid_max_concurrent_auctions() public {
        stakingPool.modifyParameters("maxConcurrentAuctions", 1);
    }

    function testFail_modify_parameters_unauthorized_address() public {
        unauth.doModifyParameters("rewardDripper", address(1));
    }

    function testFail_modify_parameters_unauthorized_uint() public {
        unauth.doModifyParameters("systemCoinsToRequest", 5 ether);
    }

    function test_join() public {
        uint amount = 1 ether;

        ancestor.approve(address(stakingPool), amount);
        uint price = stakingPool.joinPrice(amount);

        stakingPool.join(amount);

        assertEq(ancestor.balanceOf(address(stakingPool)), amount);
        assertEq(descendant.balanceOf(address(this)),price);
    }

    function testFail_join_invalid_ammount() public {
        uint amount = 0;

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);
    }

    function testFail_join_unnaproved() public {
        uint amount = 1 ether;
        stakingPool.join(amount);
    }

    function testFail_join_cant_join() public {
        uint amount = 1 ether;
        ancestor.approve(address(stakingPool), amount);
        stakingPool.toggleJoin();
        stakingPool.join(amount);
    }

    function testFail_join_underwater() public {
        uint amount = 1 ether;
        ancestor.approve(address(stakingPool), amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        stakingPool.join(amount);
    }

    function test_join_2() public {
        uint amount = 1 ether;
        ancestor.approve(address(stakingPool), amount);
        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);
        safeEngine.modifyBalance("coin", address(accountingEngine), 1000 ether);

        stakingPool.join(amount);
    }

    function test_request_exit() public {
        ancestor.approve(address(stakingPool), 1 ether);
        stakingPool.join(1 ether);

        stakingPool.requestExit();
        (uint start, uint end) = stakingPool.exitWindows(address(this));

        assertEq(start, now + exitDelay);
        assertEq(end, now + exitDelay + exitWindow);
    }

    function testFail_request_exit_before_window_ends() public {
        ancestor.approve(address(stakingPool), 1 ether);
        stakingPool.join(1 ether);

        stakingPool.requestExit();
        hevm.warp(now + exitDelay + exitWindow); // one sec to go
        stakingPool.requestExit();
    }

    function test_exit() public {
        uint amount = 2 ether;
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions
        uint256 price = stakingPool.exitPrice(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        stakingPool.exit(amount);
        assertEq(ancestor.balanceOf(address(this)), previousBalance + price);
        assertEq(descendant.balanceOf(address(this)), 0);
    }

    function testFail_exit_null_amount() public {
        uint amount = 0;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions
        stakingPool.exit(amount);
    }

    function testFail_exit_after_window() public {
        uint amount = 1 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        (, uint end) = stakingPool.exitWindows(address(this));

        hevm.warp(end + 1);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions
        stakingPool.exit(amount);
    }

    function testFail_exit_before_window() public {
        uint amount = 1 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        (uint start,) = stakingPool.exitWindows(address(this));

        hevm.warp(start - 1);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions
        stakingPool.exit(amount);
    }

    function testFail_exit_no_request() public {
        uint amount = 2 ether;
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // does not request exit
        // stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions

        stakingPool.exit(amount);
    }

    function testFail_exit_underwater() public {
        uint amount = 5 ether;
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        stakingPool.exit(amount);
    }

    function test_exit_forced_underwater() public {
        uint amount = 5 ether;
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        stakingPool.toggleForcedExit();

        stakingPool.exit(amount);
    }

    function test_auction_ancestor_tokens() public {
        uint amount = 1000 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        uint previousDescendantBalance = descendant.balanceOf(address(this));

        // auction
        stakingPool.auctionAncestorTokens();

        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
        assertEq(descendant.balanceOf(address(this)), previousDescendantBalance);
        assertEq(ancestor.balanceOf(address(auctionHouse)), 100 ether);

        // exiting (after slash)
        stakingPool.requestExit();
        hevm.warp(now + exitDelay);
        hevm.roll(block.number + 32); // 32 blocks
        descendant.approve(address(stakingPool), uint(-1));
        uint256 price = stakingPool.exitPrice(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 90 ether); // above water

        stakingPool.exit(amount);
        assertEq(ancestor.balanceOf(address(this)), previousBalance + price);
        assertEq(descendant.balanceOf(address(this)), 0);
        assertEq(rewardToken.balanceOf(address(this)), 32 ether); // 1 eth per block
    }

    function testFail_auction_ancestor_tokens_abovewater() public {
        uint amount = 10000 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        // auction
        stakingPool.auctionAncestorTokens();
    }

    function testFail_auction_ancestor_tokens_abovewater_2() public {
        uint amount = 10000 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);
        safeEngine.modifyBalance("coin", address(accountingEngine), 1000 ether);

        // auction
        stakingPool.auctionAncestorTokens();
    }

    ////////////////// Rewards (WIP) //////////////////
    function test_exit_rewards_1(uint amount, uint blockDelay) public {
        amount = amount % 10**24 + 1; // up to 1mm staked
        blockDelay = blockDelay % 100 + 1; // up to 1000 blocks
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        hevm.roll(block.number + blockDelay); // will drip 10 eth
        descendant.approve(address(stakingPool), uint(-1));
        uint256 price = stakingPool.exitPrice(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        stakingPool.exit(amount);
        assertEq(ancestor.balanceOf(address(this)), previousBalance + price);
        assertEq(descendant.balanceOf(address(this)), 0);
        assertTrue(rewardToken.balanceOf(address(this)) >= blockDelay * 1 ether - 1); // 1 eth per block
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
        user1.doRequestExit();
        user2.doRequestExit();

        // exit
        hevm.warp(now + exitDelay);
        hevm.roll(block.number + 32); // 32 blocks

        user1.doExit(amount);
        user2.doExit(amount);
        assertTrue(rewardToken.balanceOf(address(user1)) >= 16 ether -1); // .5 eth per block
        assertTrue(rewardToken.balanceOf(address(user2)) >= 16 ether -1); // .5 eth per block
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
        assertEq(rewardToken.balanceOf(address(this)), 20 ether); // 1 eth per block

        hevm.roll(block.number + 8); // 8 blocks

        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 28 ether - 1); // 1 eth per block, division rounding causes a slight loss of precision
    }

    function test_rewards_after_slashing() public {
        uint amount = 1000 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        uint previousDescendantBalance = descendant.balanceOf(address(this));

        // auction
        stakingPool.auctionAncestorTokens();

        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
        assertEq(descendant.balanceOf(address(this)), previousDescendantBalance);
        assertEq(ancestor.balanceOf(address(auctionHouse)), 100 ether);

        // exiting (after slash)
        stakingPool.requestExit();
        hevm.warp(now + exitDelay);
        hevm.roll(block.number + 32); // 32 blocks
        descendant.approve(address(stakingPool), uint(-1));
        uint256 price = stakingPool.exitPrice(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 90 ether); // above water

        stakingPool.exit(amount);
        assertEq(ancestor.balanceOf(address(this)), previousBalance + price);
        assertEq(descendant.balanceOf(address(this)), 0);
        assertEq(rewardToken.balanceOf(address(this)), 32 ether); // 1 eth per block
    }

    function test_rewards_dripper_depleated() public {
        uint amount = 7 ether;
        // leave rewards only for 20 blocks
        rewardDripper.transferTokenOut(address(0xfab), rewardToken.balanceOf(address(rewardDripper)) - 20 ether);

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        stakingPool.requestExit();
        hevm.warp(now + exitDelay);
        hevm.roll(block.number + 32); // 32 blocks
        descendant.approve(address(stakingPool), uint(-1));

        stakingPool.exit(amount);
        assertEq(descendant.balanceOf(address(this)), 0);
        assertTrue(rewardToken.balanceOf(address(this)) >= 20 ether - 1); // full amount
    }

    function test_rewards_dripper_depleated_recharged() public {
        uint amount = 7 ether;
        // leave rewards only for 20 blocks
        rewardDripper.transferTokenOut(address(0xfab), rewardToken.balanceOf(address(rewardDripper)) - 20 ether);

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 20 ether - 1); // full amount

        hevm.roll(block.number + 32); // 32 blocks

        rewardToken.mint(address(rewardDripper), 5 ether);
        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 25 ether - 1);
    }

    function test_rewards_change_dripper_emission() public {
        uint amount = 23 ether;

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 32 ether - 1); // full amount

        rewardDripper.modifyParameters("rewardPerBlock", 0.5 ether);
        hevm.roll(block.number + 32); // 32 blocks

        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 48 ether - 1);
    }

    function test_deposit_rewards() public {
        uint amount = 23 ether;

        ancestor.approve(address(stakingPool), amount * 3);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        stakingPool.join(amount);
        assertTrue(rewardToken.balanceOf(address(this)) >= 32 ether - 1); // full amount

        hevm.roll(block.number + 32); // 32 blocks

        stakingPool.join(amount);
        assertTrue(rewardToken.balanceOf(address(this)) >= 64 ether - 1);
    }

    function test_multi_user_diff_proportions() public {
        uint amount = 3.14 ether;
        Caller user1 = new Caller(stakingPool);
        ancestor.transfer(address(user1), amount);
        Caller user2 = new Caller(stakingPool);
        ancestor.transfer(address(user2), amount);
        Caller user3 = new Caller(stakingPool);
        ancestor.transfer(address(user3), amount * 2);

        // users 1 & 2 join, same amount
        user1.doJoin(amount);
        user2.doJoin(amount);

        hevm.roll(block.number + 12); // 12 blocks

        // users 3 joins, with double amount
        user3.doJoin(amount * 2);
        user1.doGetRewards();
        user2.doGetRewards();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 6 ether -1);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 6 ether -1);
        assertTrue(rewardToken.balanceOf(address(user3)) == 0);          // no rewards yet

        // users 1 exits the pool
        user1.doRequestExit();
        hevm.warp(now + exitDelay);
        hevm.roll(block.number + 12); // 12 blocks

        user1.doExit(amount);
        user2.doGetRewards();
        user3.doGetRewards();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 9 ether -1);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 9 ether -1);
        assertTrue(rewardToken.balanceOf(address(user3)) >= 6 ether -1);

        // user 1 rejoins
        hevm.roll(block.number + 12); // 12 blocks
        user1.doJoin(amount);
        user2.doGetRewards();
        user3.doGetRewards();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 9 ether -1);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 13 ether -1);
        assertTrue(rewardToken.balanceOf(address(user3)) >= 14 ether -1);

        // all onboard
        hevm.roll(block.number + 12); // 12 blocks
        user1.doGetRewards();
        user2.doGetRewards();
        user3.doGetRewards();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 12 ether -1);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 16 ether -1);
        assertTrue(rewardToken.balanceOf(address(user3)) >= 20 ether -1);
    }
}
