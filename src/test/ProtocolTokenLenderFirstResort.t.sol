pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../ProtocolTokenLenderFirstResort.sol";

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
contract RewardDripperMock {
    uint public drips;

    function dripReward() external {
        drips++;
    }
}

contract Caller {
    ProtocolTokenLenderFirstResort stakingPool;

    constructor (ProtocolTokenLenderFirstResort add) public {
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

contract ProtocolTokenLenderFirstResortTest is DSTest {
    Hevm hevm;
    DSToken ancestor;
    DSToken descendant;
    ProtocolTokenLenderFirstResort stakingPool;
    AuctionHouseMock auctionHouse;
    AccountingEngineMock accountingEngine;
    SAFEEngineMock safeEngine;
    RewardDripperMock rewardDripper;
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

        hevm.roll(5000000);
        hevm.warp(100000001);

        ancestor = new DSToken("PROT", "PROT");
        descendant = new DSToken("POOL", "POOL");
        auctionHouse = new AuctionHouseMock(address(ancestor));
        accountingEngine = new AccountingEngineMock();
        safeEngine = new SAFEEngineMock();
        rewardDripper = new RewardDripperMock();

        stakingPool = new ProtocolTokenLenderFirstResort(
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

        ancestor.mint(address(this), 10000000 ether);
        descendant.setOwner(address(stakingPool));

        unauth = new Caller(stakingPool);
    }

    function test_setup() public {
        assertEq(address(stakingPool.ancestor()), address(ancestor));
        assertEq(address(stakingPool.descendant()), address(descendant));
        assertEq(address(stakingPool.auctionHouse()), address(auctionHouse));
        assertEq(address(stakingPool.rewardDripper()), address(rewardDripper));
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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

    function testFail_setup_invalid_maxExitWindow() public {
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        stakingPool = new ProtocolTokenLenderFirstResort(
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
        assertEq(rewardDripper.drips(), 1);
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
        uint previousBalance = ancestor.balanceOf(address(this));
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        // auction
        stakingPool.auctionAncestorTokens();

        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
        assertEq(ancestor.balanceOf(address(auctionHouse)), 100 ether);
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

    function test_slashing() public {
        uint amount = 1000 ether;
        // join
        uint previousBalance = ancestor.balanceOf(address(this));
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        // auction
        stakingPool.auctionAncestorTokens();

        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
        assertEq(ancestor.balanceOf(address(auctionHouse)), 100 ether);

        // exiting (after slash)
        stakingPool.requestExit();
        hevm.warp(now + exitDelay);
        descendant.approve(address(stakingPool), uint(-1));

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 90 ether); // above water

        stakingPool.exit(amount);
        assertEq(ancestor.balanceOf(address(this)), previousBalance - 100 ether);
        assertEq(descendant.balanceOf(address(this)), 0);
    }

    function assertAlmostEqual(uint a, uint b, uint p) public {
        uint v = a - (a / 10**p);
        assertTrue(b >= a - v && b <= a + v);
    }

    function test_slashing_2_users() public {
        uint amount = 513 ether;
        Caller user1 = new Caller(stakingPool);
        ancestor.transfer(address(user1), amount);
        Caller user2 = new Caller(stakingPool);
        ancestor.transfer(address(user2), amount);

        uint previousBalance1 = ancestor.balanceOf(address(user1));
        uint previousBalance2 = ancestor.balanceOf(address(user2));

        // join
        user1.doJoin(amount);
        user2.doJoin(amount);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 1000 ether);

        // auction
        stakingPool.auctionAncestorTokens();

        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
        assertEq(ancestor.balanceOf(address(auctionHouse)), 100 ether);

        // exiting (after slash)
        user1.doRequestExit();
        user2.doRequestExit();
        hevm.warp(now + exitDelay);

        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", 90 ether); // above water

        user1.doExit(amount);
        user2.doExit(amount);

        assertAlmostEqual(ancestor.balanceOf(address(user1)), previousBalance1 - 50 ether, 1);
        assertEq(descendant.balanceOf(address(user1)), 0);
        assertAlmostEqual(ancestor.balanceOf(address(user2)), previousBalance2 - 50 ether, 1);
        assertEq(descendant.balanceOf(address(user2)), 0);
    }

    function test_rewards() public {
        uint amount = 2 ether;
        // join
        uint previousBalance = ancestor.balanceOf(address(this));
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // request exit
        stakingPool.requestExit();

        // exit
        hevm.warp(now + exitDelay);
        ancestor.mint(address(stakingPool), 33 ether);
        descendant.approve(address(stakingPool), uint(-1)); // necessary, should be handled by proxyActions

        stakingPool.exit(amount);
        assertEq(ancestor.balanceOf(address(this)), previousBalance + 33 ether);
        assertEq(descendant.balanceOf(address(this)), 0);
    }

    function test_rewards_2_users() public {
        uint amount = 34 ether;
        Caller user1 = new Caller(stakingPool);
        ancestor.transfer(address(user1), amount);
        Caller user2 = new Caller(stakingPool);
        ancestor.transfer(address(user2), amount * 3);

        uint previousBalance1 = ancestor.balanceOf(address(user1));
        uint previousBalance2 = ancestor.balanceOf(address(user2));

        // join
        user1.doJoin(amount);
        user2.doJoin(amount);

        // exiting
        user1.doRequestExit();
        user2.doRequestExit();
        hevm.warp(now + exitDelay);
        ancestor.mint(address(stakingPool), 24 ether);

        user1.doExit(amount);
        user2.doExit(amount);

        assertAlmostEqual(ancestor.balanceOf(address(user1)), previousBalance1 + 6 ether, 1);
        assertEq(descendant.balanceOf(address(user1)), 0);
        assertAlmostEqual(ancestor.balanceOf(address(user2)), previousBalance2 + 18 ether, 1);
        assertEq(descendant.balanceOf(address(user2)), 0);
    }
}