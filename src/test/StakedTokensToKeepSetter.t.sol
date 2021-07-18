pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../GebLenderFirstResortRewardsVested.sol";
import {RewardDripper} from "../RewardDripper.sol";
import {StakedTokensToKeepSetter} from "../StakedTokensToKeepSetter.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
}

contract EscrowMock {
    function escrowRewards(address, uint256) external {}
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

contract StakedTokensToKeepSetterTest is DSTest {
    Hevm hevm;
    DSToken rewardToken;
    DSToken ancestor;
    DSToken descendant;
    GebLenderFirstResortRewardsVested stakingPool;
    AuctionHouseMock auctionHouse;
    StakedTokensToKeepSetter setter;

    AccountingEngineMock accountingEngine;
    SAFEEngineMock safeEngine;
    RewardDripper rewardDripper;

    EscrowMock escrow;
    Caller unauth;

    uint maxDelay = 48 weeks;
    uint exitDelay = 1 weeks;
    uint minStakedTokensToKeep = 1;
    uint tokensToAuction  = 100 ether;
    uint systemCoinsToRequest = 1000 ether;
    uint percentageVested = 60;
    uint tokenPercentageToKeep = 65;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        hevm.roll(5000000);
        hevm.warp(100000001);

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
        escrow           = new EscrowMock();

        stakingPool = new GebLenderFirstResortRewardsVested(
            address(ancestor),
            address(descendant),
            address(rewardToken),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            address(escrow),
            maxDelay,
            exitDelay,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest,
            percentageVested
        );
        stakingPool.modifyParameters("escrowPaused", 1);

        rewardDripper.modifyParameters("requestor", address(stakingPool));
        rewardToken.mint(address(rewardDripper), 10000000 ether);

        ancestor.mint(address(this), 1000000000 ether);
        descendant.setOwner(address(stakingPool));

        descendant.approve(address(stakingPool));

        setter = new StakedTokensToKeepSetter(address(safeEngine), address(accountingEngine), address(stakingPool), tokenPercentageToKeep);
        stakingPool.addAuthorization(address(setter));

        unauth = new Caller(stakingPool);
    }

    function test_setup() public {
        assertEq(setter.authorizedAccounts(address(this)), 1);
        assertEq(address(setter.accountingEngine()), address(accountingEngine));
        assertEq(address(setter.lenderFirstResort()), address(stakingPool));
        assertEq(address(setter.safeEngine()), address(safeEngine));
        assertEq(address(setter.tokenPercentageToKeep()), address(tokenPercentageToKeep));
    }
    function test_set_when_nothing_staked() public {
        setter.recomputeTokensToKeep();
        assertEq(stakingPool.minStakedTokensToKeep(), 1 ether);
    }
    function test_set_when_tiny_staked() public {
        uint amount = 10;

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        setter.recomputeTokensToKeep();
        assertEq(stakingPool.minStakedTokensToKeep(), 6);
    }
    function test_set_when_large_stake() public {
        uint amount = 10 ether;

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        setter.recomputeTokensToKeep();
        assertEq(stakingPool.minStakedTokensToKeep(), 6.5 ether);

        // request exit
        stakingPool.requestExit(amount / 2);

        // exit
        hevm.warp(now + exitDelay);
        stakingPool.exit();

        setter.recomputeTokensToKeep();
        assertEq(stakingPool.minStakedTokensToKeep(), 3.25 ether);
    }
}
