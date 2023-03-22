pragma solidity >=0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "../ExternallyControlledDripper.sol";

abstract contract Hevm {
    function warp(uint256) public virtual;

    function roll(uint256) public virtual;

    function prank(address) public virtual;
}

contract MockFundsHolder {
    DSToken token;
    address dripper;
    uint256 transferAmount;

    constructor(
        address token_,
        address dripper_,
        uint256 transferAmount_
    ) public {
        token = DSToken(token_);
        dripper = dripper_;
        transferAmount = transferAmount_;
    }

    function setTransferAmount(uint256 amount) external {
        transferAmount = amount;
    }

    function releaseFunds() external {
        require(msg.sender == dripper);
        token.transfer(msg.sender, transferAmount);
    }
}

contract ExternallyControlledDripperTest is DSTest {
    Hevm hevm;

    ExternallyControlledDripper dripper;
    MockFundsHolder emitter;
    DSToken coin;

    address alice = address(0xa11ce);
    address bob = address(0xb0b);
    address rateSetter = address(0xc4a311e);
    uint256 initTokenAmount = 100000000 ether;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.roll(5000000000);

        coin = new DSToken("RATE", "RATE");

        dripper = new ExternallyControlledDripper(
            [alice, bob],
            address(coin),
            address(0x1),
            rateSetter,
            7 days
        );

        emitter = new MockFundsHolder(address(coin), address(dripper), 1 ether);

        dripper.modifyParameters("fundsHolder", address(emitter));

        coin.mint(address(emitter), initTokenAmount);
    }

    // --- Tests ---
    function test_correct_setup() public {
        assertEq(dripper.rewardPerBlock(alice), 0);
        assertEq(dripper.rewardPerBlock(bob), 0);
        assertEq(dripper.lastRewardBlock(alice), block.number);
        assertEq(dripper.lastRewardBlock(bob), block.number);
        assertEq(dripper.requestors(0), address(alice));
        assertEq(dripper.requestors(1), address(bob));
        assertEq(address(dripper.rewardToken()), address(coin));
        assertEq(address(dripper.fundsHolder()), address(emitter));
        assertEq(address(dripper.rateSetter()), rateSetter);
        assertEq(dripper.updateDelay(), 7 days);
        assertEq(dripper.lastUpdateTime(), 0);
    }

    function testFail_setup_null_requestor_0() public {
        dripper = new ExternallyControlledDripper(
            [address(0), bob],
            address(coin),
            address(0x1),
            rateSetter,
            7 days
        );
    }

    function testFail_setup_null_requestor_1() public {
        dripper = new ExternallyControlledDripper(
            [alice, address(0)],
            address(coin),
            address(0x1),
            rateSetter,
            7 days
        );
    }

    function testFail_setup_null_token() public {
        dripper = new ExternallyControlledDripper(
            [alice, bob],
            address(0),
            address(0x1),
            rateSetter,
            7 days
        );
    }

    function testFail_setup_null_emitter() public {
        dripper = new ExternallyControlledDripper(
            [alice, bob],
            address(coin),
            address(0),
            rateSetter,
            7 days
        );
    }

    function testFail_setup_null_rate_setter() public {
        dripper = new ExternallyControlledDripper(
            [alice, bob],
            address(coin),
            address(0x1),
            address(0),
            7 days
        );
    }

    function testFail_setup_null_update_delay() public {
        dripper = new ExternallyControlledDripper(
            [alice, bob],
            address(coin),
            address(0x1),
            rateSetter,
            0
        );
    }

    function test_add_authorization() public {
        dripper.addAuthorization(address(0x1));
        assertEq(dripper.authorizedAccounts(address(0x1)), 1);
    }

    function test_remove_authorization() public {
        dripper.removeAuthorization(address(this));
        assertEq(dripper.authorizedAccounts(address(this)), 0);
    }

    function testFail_add_authorization_unauthorized() public {
        hevm.prank(alice);
        dripper.addAuthorization(address(0x1));
    }

    function testFail_remove_authorization_unauthorized() public {
        hevm.prank(alice);
        dripper.removeAuthorization(address(this));
    }

    function test_modify_parametersa() public {
        dripper.modifyParameters("updateDelay", 1 weeks);
        assertEq(dripper.updateDelay(), 1 weeks);

        hevm.warp(block.number + 3 days);

        dripper.modifyParameters("requestor0", address(0xbeef));
        assertEq(dripper.requestors(0), address(0xbeef));
        assertEq(dripper.lastRewardBlock(address(0xbeef)), block.number);

        dripper.modifyParameters("requestor1", address(0xbeef1));
        assertEq(dripper.requestors(1), address(0xbeef1));
        assertEq(dripper.lastRewardBlock(address(0xbeef1)), block.number);

        dripper.modifyParameters("fundsHolder", address(0xbeef2));
        assertEq(address(dripper.fundsHolder()), address(0xbeef2));
    }

    function testFail_modify_parameters_invalid_update_delay() public {
        dripper.modifyParameters("updateDelay", 0);
    }

    function testFail_modify_parameters_invalid_param_address() public {
        dripper.modifyParameters("invalid", address(1));
    }

    function testFail_modify_parameters_invalid_param_uint() public {
        dripper.modifyParameters("invalid", 1);
    }

    function testFail_modify_parameters_unauthorized_address() public {
        hevm.prank(bob);
        dripper.modifyParameters("fundsHolder", address(0xbeef2));
    }

    function testFail_modify_parameters_unauthorized_uint() public {
        hevm.prank(bob);
        dripper.modifyParameters("updateDelay", 1 weeks);
    }

    function test_transfer_token_out() public {
        coin.mint(address(dripper), 50 ether);
        dripper.transferTokenOut(address(0x1), 25 ether);
        assertEq(coin.balanceOf(address(0x1)), 25 ether);
    }

    function testFail_transfer_token_null_dst() public {
        dripper.transferTokenOut(address(0), 25 ether);
    }

    function testFail_transfer_token_null_amount() public {
        dripper.transferTokenOut(address(0x1), 0);
    }

    function testFail_transfer_token_unauthorized() public {
        coin.mint(address(dripper), 50 ether);
        hevm.prank(bob);
        dripper.transferTokenOut(address(0x1), 50 ether);
    }

    function update_rates_to_1_eth_per_block() internal {
        emitter.setTransferAmount(2 ether * (7 days / 12));
        hevm.warp(dripper.lastUpdateTime() + 7 days);
        hevm.prank(address(rateSetter));
        dripper.updateRate(10 ** 18 / 2); // 50% to alice, rest for bob

        assertEq(dripper.rewardPerBlock(alice), 1 ether);
        assertEq(dripper.rewardPerBlock(bob), 1 ether);
    }

    function test_drip_rewards() public {
        update_rates_to_1_eth_per_block();

        hevm.roll(block.number + 1);
        dripper.dripReward(bob);
        assertEq(coin.balanceOf(bob), 1 ether);
        assertEq(coin.balanceOf(alice), 0);

        hevm.roll(block.number + 1);
        dripper.dripReward(alice);
        assertEq(coin.balanceOf(bob), 1 ether);
        assertEq(coin.balanceOf(alice), 2 ether);

        hevm.roll(block.number + 10);
        dripper.dripReward(bob);
        assertEq(coin.balanceOf(bob), 12 ether);
        assertEq(coin.balanceOf(alice), 2 ether);
        dripper.dripReward(alice);
        assertEq(coin.balanceOf(bob), 12 ether);
        assertEq(coin.balanceOf(alice), 12 ether);
    }

    function test_drip_rewards_same_block() public {
        update_rates_to_1_eth_per_block();
        hevm.roll(block.number + 1);
        dripper.dripReward(bob);
        assertEq(coin.balanceOf(bob), 1 ether);

        dripper.dripReward(bob);
        assertEq(coin.balanceOf(bob), 1 ether);

        dripper.dripReward(bob);
        assertEq(coin.balanceOf(bob), 1 ether);        
    }    

    function testFail_drip_rewards_invalid_caller() public {
        update_rates_to_1_eth_per_block();
        hevm.roll(block.number + 1);
        dripper.dripReward(address(0x0dd));      
    }      

    function test_update_rate() public {
        hevm.warp(dripper.lastUpdateTime() + 7 days);
        hevm.prank(address(rateSetter));

        dripper.updateRate(10 ** 17); // 10% to alice, rest for bob

        uint dripperBalance = coin.balanceOf(address(dripper));
        assertEq(dripperBalance, 1 ether);
        assertEq(dripper.rewardPerBlock(alice), uint(.1 ether) / (7 days / 12));
        assertEq(dripper.rewardPerBlock(bob), uint(.9 ether) / (7 days / 12));
        assertEq(dripper.lastRewardBlock(address(alice)), block.number);
        assertEq(dripper.lastRewardBlock(address(bob)), block.number);

        hevm.warp(dripper.lastUpdateTime() + 7 days);
        hevm.prank(address(rateSetter));

        dripper.updateRate(10 ** 18 / 2); // 50% to alice, rest for bob

        dripperBalance = coin.balanceOf(address(dripper));
        assertEq(dripperBalance, 2 ether);
        assertEq(dripper.rewardPerBlock(alice), uint(.5 ether) / (7 days / 12));
        assertEq(dripper.rewardPerBlock(bob), uint(.5 ether) / (7 days / 12));
        assertEq(dripper.lastRewardBlock(address(alice)), block.number);
        assertEq(dripper.lastRewardBlock(address(bob)), block.number);
    }

    function testFail_update_rate_unauthed() public {
        hevm.warp(dripper.lastUpdateTime() + 7 days);

        dripper.updateRate(10 ** 17);
    }    

    function testFail_update_rate_too_soon() public {
        hevm.warp(dripper.lastUpdateTime() + 7 days - 1);
        hevm.prank(address(rateSetter));

        dripper.updateRate(10 ** 17);
    }        

    function testFail_update_rate_invalid_proportion() public {
        hevm.warp(dripper.lastUpdateTime() + 7 days);
        hevm.prank(address(rateSetter));

        dripper.updateRate(10 ** 18 + 1);
    }        

    function test_update_rate_fuzz(uint proportion) public {
        proportion = proportion % 10 ** 18; // up to 1 WAD or 100% requestor 0

        hevm.warp(dripper.lastUpdateTime() + 7 days);
        hevm.prank(address(rateSetter));

        dripper.updateRate(proportion);

        uint dripperBalance = coin.balanceOf(address(dripper));
        assertEq(dripperBalance, 1 ether);
        assertEq(
            dripper.rewardPerBlock(alice),
            (1 ether * proportion) / 10 ** 18 / (7 days / 12)
        );
        assertEq(
            dripper.rewardPerBlock(bob),
            (1 ether * (10 ** 18 - proportion)) / 10 ** 18 / (7 days / 12)
        );
        assertEq(dripper.lastRewardBlock(address(alice)), block.number);
        assertEq(dripper.lastRewardBlock(address(bob)), block.number);
    }
}
