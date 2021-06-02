pragma solidity 0.6.7;

import {GebLenderFirstResortRewards} from "../../GebLenderFirstResortRewards.sol";
import {RewardDripper} from "../../RewardDripper.sol";
import "../../../lib/ds-test/src/test.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
}

contract TokenMock {
    uint constant maxUint = uint(0) - 1;
    uint public totalSupply;
    mapping (address => uint256) public balanceOf;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ProtocolTokenLenderFirstResort/add-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x); //, "ProtocolTokenLenderFirstResort/sub-uint-uint-underflow");
    }
    function decimals() public pure returns (uint) { return 18; }
    function allowance(address src, address guy) public view returns (uint) {
        return maxUint;
    }
    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        balanceOf[dst] = addition(balanceOf[dst], wad);

        if (balanceOf[src] == 0) mint(src, wad);
        balanceOf[src] = subtract(balanceOf[src], wad);
        return true;
    }

    function approve(address guy, uint wad) virtual public returns (bool) {
        return true;
    }

    function mint(address dst, uint wad) public returns (bool) {
        balanceOf[dst] = addition(balanceOf[dst], wad);
        totalSupply    = addition(totalSupply, wad);
        return true;
    }

    function burn(address dst, uint wad) public returns (bool) {
        balanceOf[dst] = subtract(balanceOf[dst], wad);
        totalSupply    = subtract(totalSupply, wad);
        return true;
    }

    function setTotalSupply(uint wad) public {
        totalSupply = wad;
    }
}

contract AuctionHouseMock {
    uint public activeStakedTokenAuctions;
    TokenMock public tokenToAuction;

    constructor(address tokenToAuction_) public {
        tokenToAuction = TokenMock(tokenToAuction_);
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
    GebLenderFirstResortRewards stakingPool;

    constructor (GebLenderFirstResortRewards add) public {
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
        stakingPool.join(wad);
    }

    function doRequestExit(uint wad) public {
        stakingPool.requestExit(wad);
    }

    function doExit() public {
        stakingPool.exit();
    }
}

contract Fuzz is DSTest {
    TokenMock ancestor;
    TokenMock rewardToken;
    GebLenderFirstResortRewards stakingPool;
    AuctionHouseMock auctionHouse;
    AccountingEngineMock accountingEngine;
    SAFEEngineMock safeEngine;
    RewardDripper rewardDripper;

    address[] callerAdds;
    mapping (address => Caller) callers;

    uint maxDelay = 48 weeks;
    uint exitDelay = 1 hours;
    uint minStakedTokensToKeep = 10 ether;
    uint tokensToAuction  = 10 ether;
    uint systemCoinsToRequest = 1000 ether;

    constructor() public {
        ancestor = new TokenMock();
        rewardToken = new TokenMock();
        auctionHouse = new AuctionHouseMock(address(ancestor));
        accountingEngine = new AccountingEngineMock();
        safeEngine = new SAFEEngineMock();
        rewardDripper = new RewardDripper(
            address(this),        // requestor
            address(rewardToken),
            1 ether               // rewardPerBlock
        );

        stakingPool = new GebLenderFirstResortRewards(
            address(ancestor),
            address(rewardToken),
            address(auctionHouse),
            address(accountingEngine),
            address(safeEngine),
            address(rewardDripper),
            maxDelay,
            exitDelay,
            minStakedTokensToKeep,
            tokensToAuction,
            systemCoinsToRequest
        );

        rewardDripper.modifyParameters("requestor", address(stakingPool));
    }

    // for compatibility with dapp tools
    function setUp() public {}

    // will fuzz unqueuedUnauctionedDebt and accountingEngines coin balance in safeEngine to simulate above/below water
    function fuzz_under_above_water(uint unqueuedUnauctionedDebt, uint accountingEngineBalance) public {
        accountingEngine.modifyParameters("unqueuedUnauctionedDebt", unqueuedUnauctionedDebt % 10 ** 27);
        safeEngine.modifyBalance("coin", address(accountingEngine), accountingEngineBalance % 10 ** 27);
    }

    // if a caller does not exist for a given msg.sender it creates one
    modifier createCaller() {
        if (address(callers[msg.sender]) == address(0)) {
            callers[msg.sender] = new Caller(stakingPool);
            callerAdds.push(address(callers[msg.sender]));
        }
        _;
    }

    // Here we aid the fuzzer in interacting with the staking pool, test the actual tx
    function doJoin(uint wad) public createCaller {
        uint price = stakingPool.joinPrice(wad);
        uint previousPoolBalance   = ancestor.balanceOf(address(stakingPool.ancestorPool()));
        uint previousCallerBalance = rewardToken.balanceOf(address(callers[msg.sender]));
        callers[msg.sender].doJoin(wad);
        // assert(ancestor.balanceOf(address(stakingPool.ancestorPool())) == previousPoolBalance + wad);
        // assert(rewardToken.balanceOf(address(callers[msg.sender])) == previousCallerBalance + price);
    }

    function doRequestExit(uint wad) public createCaller {
        (, uint previouslyLocked) = stakingPool.exitRequests(address(callers[msg.sender]));
        callers[msg.sender].doRequestExit(wad);
        // will only test the assertions if succeeded
        (uint deadline, uint locked) = stakingPool.exitRequests(address(callers[msg.sender]));

        // assert(deadline == now + exitDelay);
        // assert(locked == previouslyLocked + wad);
    }

    function doExit() public createCaller {
        (, uint locked) = stakingPool.exitRequests(address(callers[msg.sender]));
        uint previousAncestorBalance = ancestor.balanceOf(address(callers[msg.sender]));
        // uint previousDescendantBalance = descendant.balanceOf(address(callers[msg.sender]));
        uint price = stakingPool.exitPrice(locked);

        callers[msg.sender].doExit();

        assert(ancestor.balanceOf(address(callers[msg.sender])) == previousAncestorBalance + price);
        // assert(descendant.balanceOf(address(callers[msg.sender])) == previousDescendantBalance - locked);
    }

    function doAuctionAncestorTokens() public {
        stakingPool.auctionAncestorTokens();
    }

    function totalCallerBalance(TokenMock token) internal view returns (uint total) {
            for (uint i = 0; i < callerAdds.length; i ++) {
                total += token.balanceOf(callerAdds[i]);
        }
    }

    // invariants
    function echidna_ancestor_supply() public returns (bool) {
        return totalCallerBalance(ancestor) == ancestor.totalSupply() - ancestor.balanceOf(address(stakingPool)) - ancestor.balanceOf(address(auctionHouse));
    }

    function echidna_auction_funds() public returns (bool) {
        return ancestor.balanceOf(address(auctionHouse)) ==
            auctionHouse.activeStakedTokenAuctions() * stakingPool.tokensToAuction();
    }

    function test_echidna() public {
        Hevm hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        doJoin(3 ether);
        doRequestExit(3 ether);
        hevm.warp(now + exitDelay + 1);
        doExit();
    }
}


