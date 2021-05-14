pragma solidity >=0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "../auction/StakedTokenAuctionHouse.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
    function roll(uint256) virtual public;
}

contract Caller {
    StakedTokenAuctionHouse target;

    constructor (StakedTokenAuctionHouse target_) public {
        target = target_;
    }

    function doModifyParameters(bytes32 param, uint256 data) public {
        target.modifyParameters(param, data);
    }

    function doModifyParameters(bytes32 param, address data) public {
        target.modifyParameters(param, data);
    }

    function doAddAuthorization(address data) public {
        target.addAuthorization(data);
    }

    function doRemoveAuthorization(address data) public {
        target.removeAuthorization(data);
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

contract AccountingEngineMock {

}

contract StakedTokenAuctionHouseTest is DSTest {
    Hevm hevm;

    StakedTokenAuctionHouse auctionHouse;
    DSToken prot;
    Caller unauth;
    SAFEEngineMock safeEngine;
    AccountingEngineMock accountingEngine;

    // uint256 initTokenAmount = 100 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // Create token
        prot = new DSToken("FLX", "FLX");

        safeEngine = new SAFEEngineMock();

        auctionHouse = new StakedTokenAuctionHouse(
            address(safeEngine),
            address(prot)
        );

        accountingEngine = new AccountingEngineMock();

        auctionHouse.modifyParameters("accountingEngine", address(accountingEngine));

        unauth = new Caller(auctionHouse);

        prot.approve(address(auctionHouse), uint(-1));
        prot.mint(address(this), 1000 ether);
    }

    // --- Tests ---
    function test_correct_setup() public {
        assertEq(address(auctionHouse.safeEngine()), address(safeEngine));
        assertEq(address(auctionHouse.stakedToken()), address(prot));
        assertEq(auctionHouse.contractEnabled(), 1);
        assertEq(auctionHouse.authorizedAccounts(address(this)), 1);
    }

    function testFail_setup_null_safeEngine() public {
        auctionHouse = new StakedTokenAuctionHouse(
            address(0),
            address(prot)
        );
    }

    function testFail_setup_null_token() public {
        auctionHouse = new StakedTokenAuctionHouse(
            address(safeEngine),
            address(0)
        );
    }

    function test_add_authorization() public {
        auctionHouse.addAuthorization(address(0xfab));
        assertEq(auctionHouse.authorizedAccounts(address(0xfab)), 1);
    }

    function test_remove_authorization() public {
        auctionHouse.removeAuthorization(address(this));
        assertEq(auctionHouse.authorizedAccounts(address(this)), 0);
    }

    function testFail_add_authorization_unauthorized() public {
        unauth.doAddAuthorization(address(0xfab));
    }

    function testFail_remove_authorization_unauthorized() public {
        unauth.doRemoveAuthorization(address(this));
    }

    function test_modify_parameters() public {
        auctionHouse.modifyParameters("bidIncrease", 2 ether);
        assertEq(auctionHouse.bidIncrease(), 2 ether);

        auctionHouse.modifyParameters("bidDuration", 1 weeks);
        assertEq(uint(auctionHouse.bidDuration()), 1 weeks);

        auctionHouse.modifyParameters("totalAuctionLength", 4 hours);
        assertEq(uint(auctionHouse.totalAuctionLength()), 4 hours);

        auctionHouse.modifyParameters("minBidDecrease", 1000);
        assertEq(auctionHouse.minBidDecrease(), 1000);

        auctionHouse.modifyParameters("minBid", 3 ether);
        assertEq(auctionHouse.minBid(), 3 ether);



        auctionHouse.modifyParameters("accountingEngine", address(0xbeef));
        assertEq(address(auctionHouse.accountingEngine()), address(0xbeef));

        auctionHouse.modifyParameters("tokenBurner", address(0xbeef));
        assertEq(address(auctionHouse.tokenBurner()), address(0xbeef));
    }

    function testFail_modify_parameters_invalid_uint() public {
        auctionHouse.modifyParameters("bidIncrease", 0);
    }

    function testFail_modify_parameters_invalid_bid_increase() public {
        auctionHouse.modifyParameters("bidIncrease", 1 ether);
    }

    function testFail_modify_parameters_invalid_Min_bid_increase() public {
        auctionHouse.modifyParameters("minBidDecrease", 1 ether);
    }

    function testFail_modify_parameters_invalid_param_address() public {
        auctionHouse.modifyParameters("invalid", address(1));
    }

    function testFail_modify_parameters_invalid_param_uint() public {
        auctionHouse.modifyParameters("invalid", 1);
    }

    function testFail_modify_parameters_unauthorized_address() public {
        unauth.doModifyParameters("tokenBurner", address(1));
    }

    function testFail_modify_parameters_unauthorized_uint() public {
        unauth.doModifyParameters("rewardPerBlock", 5 ether);
    }

    function test_start_auction() public {
        uint id = auctionHouse.startAuction(
            10 ether,
            100 ether
        );

        assertEq(auctionHouse.auctionsStarted(), 1);
        (uint256 bidAmount, uint256 amountToSell, address highBidder, uint48  bidExpiry, uint48  auctionDeadline) =
                auctionHouse.bids(id);

        assertEq(amountToSell, 10 ether);
        assertEq(bidAmount, 100 ether);
        assertEq(highBidder, address(accountingEngine));
        assertEq(auctionDeadline, now + auctionHouse.totalAuctionLength());
        assertEq(auctionHouse.activeStakedTokenAuctions(), 1);
    }

    function testFail_start_auction_disabled() public {
        auctionHouse.disableContract();
        auctionHouse.startAuction(
            10 ether,
            100 ether
        );
    }

    function testFail_start_auction_null_accounting_engine() public {
        auctionHouse.modifyParameters("accountingEngine", address(0));
        auctionHouse.startAuction(
            10 ether,
            100 ether
        );
    }

    function testFail_start_auction_null_amount_to_sell() public {
        auctionHouse.startAuction(
            0,
            100 ether
        );
    }

    function testFail_start_auction_null_coins_requested() public {
        auctionHouse.startAuction(
            10 ether,
            0
        );
    }

    function testFail_start_auction_invalid_coins_requested() public {
        auctionHouse.startAuction(
            10 ether,
            (uint256(-1) / 1 ether) + 1
        );
    }

    function test_restart_auction() public {
        uint id = auctionHouse.startAuction(
            10 ether,
            100 ether
        );

        hevm.warp(now + auctionHouse.totalAuctionLength() + 1);

        auctionHouse.restartAuction(id);

        (uint256 bidAmount, uint256 amountToSell, address highBidder, uint48  bidExpiry, uint48  auctionDeadline) =
                auctionHouse.bids(id);

        assertEq(bidAmount, 95 ether);
        assertEq(auctionDeadline, now + auctionHouse.totalAuctionLength());
    }

    function testFail_restart_auction_before_finish() public {
        uint id = auctionHouse.startAuction(
            10 ether,
            100 ether
        );

        hevm.warp(now + auctionHouse.totalAuctionLength());

        auctionHouse.restartAuction(id);
    }

    function testFail_restart_auction_invalid() public {
        uint id = auctionHouse.startAuction(
            10 ether,
            100 ether
        );

        auctionHouse.restartAuction(66);
    }
}
