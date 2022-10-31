pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../GebRewards.sol";
import {RewardDripper} from "../RewardDripper.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
    function roll(uint) virtual public;
}

contract Caller {
    GebRewards stakingPool;

    constructor (GebRewards add) public {
        stakingPool = add;
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

    function doExit(uint wad) public {
        stakingPool.exit(wad);
    }

    function doApprove(DSToken token, address guy) public {
        token.approve(guy);
    }
}

contract GebRewardsTest is DSTest {
    Hevm hevm;
    DSToken rewardToken;
    DSToken ancestor;
    GebRewards stakingPool;
    RewardDripper rewardDripper;
    Caller unauth;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        hevm.roll(5000000);
        hevm.warp(100000001);

        rewardToken = new DSToken("PROT", "PROT");
        ancestor = new DSToken("LP", "LP");
        rewardDripper = new RewardDripper(
            address(this),        // requestor
            address(rewardToken),
            1 ether               // rewardPerBlock
        );

        stakingPool = new GebRewards(
            address(ancestor),
            address(rewardToken),
            address(rewardDripper)
        );

        rewardDripper.modifyParameters("requestor", address(stakingPool));
        rewardToken.mint(address(rewardDripper), 10000000 ether);

        ancestor.mint(address(this), 1000000000 ether);

        unauth = new Caller(stakingPool);
    }

    function test_setup() public {
        assertEq(address(stakingPool.ancestorPool().token()), address(ancestor));
        assertEq(address(stakingPool.rewardDripper()), address(rewardDripper));
        assertEq(address(stakingPool.rewardPool().token()), address(rewardToken));
        assertEq(stakingPool.authorizedAccounts(address(this)), 1);
        assertEq(stakingPool.stakedSupply(), 0);
        assertTrue(stakingPool.canJoin());
    }

    function testFail_setup_invalid_rewardsDripper() public {
        stakingPool = new GebRewards(
            address(ancestor),
            address(rewardToken),
            address(0)
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
        stakingPool.modifyParameters("rewardDripper", address(5));
        assertEq(address(stakingPool.rewardDripper()), address(5));
    }

    function testFail_modify_parameters_null_address() public {
        stakingPool.modifyParameters("rewardDripper", address(0));
    }

    function testFail_modify_parameters_invalid_param_address() public {
        stakingPool.modifyParameters("invalid", address(1));
    }

    function testFail_modify_parameters_unauthorized_address() public {
        unauth.doModifyParameters("rewardDripper", address(1));
    }

    function test_pending_rewards() public {
        uint amount = 1 ether;

        ancestor.approve(address(stakingPool), amount);

        stakingPool.join(amount);

        assertEq(ancestor.balanceOf(address(stakingPool.ancestorPool())), amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), amount);

        assertEq(stakingPool.pendingRewards(address(this)), 0);
        stakingPool.getRewards();

        hevm.roll(block.number + 10);
        assertEq(stakingPool.pendingRewards(address(this)), 10 ether);
        stakingPool.getRewards();
        assertEq(stakingPool.pendingRewards(address(this)), 0);

        hevm.roll(block.number + 5);
        assertEq(stakingPool.pendingRewards(address(this)), 5 ether);
    }

    function test_join() public {
        uint amount = 1 ether;

        ancestor.approve(address(stakingPool), amount);

        stakingPool.join(amount);

        assertEq(ancestor.balanceOf(address(stakingPool.ancestorPool())), amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), amount);
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

    function test_exit() public {
        uint amount = 2 ether;
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        // exit
        stakingPool.exit(amount);

        assertEq(ancestor.balanceOf(address(this)), previousBalance + amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
    }

    function testFail_exit_null_amount() public {
        uint amount = 12 ether;
        // join
        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        // request exit
        stakingPool.exit(0);
    }

    function test_exit_rewards_1(uint amount, uint blockDelay) public {
        amount = amount % 10**24 + 1; // up to 1mm staked
        blockDelay = blockDelay % 100 + 1; // up to 1000 blocks
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // exit
        hevm.roll(block.number + blockDelay);
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.exit(amount);

        assertEq(ancestor.balanceOf(address(this)), previousBalance + amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
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

        // exit
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

    function test_rewards_dripper_depleated() public {
        uint amount = 7 ether;
        // leave rewards only for 20 blocks
        rewardDripper.transferTokenOut(address(0xfab), rewardToken.balanceOf(address(rewardDripper)) - 20 ether);

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        stakingPool.exit(amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
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

    function test_rewards_over_long_intervals() public {
        uint amount = 3.14 ether;
        Caller user1 = new Caller(stakingPool);
        ancestor.transfer(address(user1), amount);
        Caller user2 = new Caller(stakingPool);
        ancestor.transfer(address(user2), amount);

        // users 1 & 2 join, same amount
        user1.doJoin(amount);
        hevm.roll(block.number + 1000000); // 1mm blocks

        user2.doJoin(amount);
        hevm.roll(block.number + 1); // 1 block

        user1.doGetRewards();
        user2.doGetRewards();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 1000000.5 ether - 1);
        assertTrue(rewardToken.balanceOf(address(user1)) <= 1000000.5 ether);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 0.5 ether - 1);
        assertTrue(rewardToken.balanceOf(address(user2)) <= 0.5 ether);

        hevm.roll(block.number + 1); // 1 block

        user1.doGetRewards();
        user2.doGetRewards();
        assertTrue(rewardToken.balanceOf(address(user1)) >= 1000001 ether - 1);
        assertTrue(rewardToken.balanceOf(address(user1)) <= 1000001 ether);
        assertTrue(rewardToken.balanceOf(address(user2)) >= 1 ether - 1);
        assertTrue(rewardToken.balanceOf(address(user2)) <= 1 ether);
    }

    function test_get_rewards_externally_funded() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        hevm.roll(block.number + 10); // 10 blocks

        rewardToken.mint(address(stakingPool.rewardPool()), 10 ether); // manually filling up contract

        stakingPool.getRewards();
        assertEq(rewardToken.balanceOf(address(this)), 30 ether); // 1 eth per block + externally funded

        hevm.roll(block.number + 4);
        stakingPool.pullFunds(); // pulling rewards to conrtact without updating

        hevm.roll(block.number + 4);
        rewardToken.mint(address(stakingPool.rewardPool()), 2 ether); // manually filling up contract

        stakingPool.getRewards();
        assertTrue(rewardToken.balanceOf(address(this)) >= 40 ether - 1); // 1 eth per block, division rounding causes a slight loss of precision
    }
}

contract GebLenderFirstResortRewardsSameTokenTest is DSTest {
    Hevm hevm;
    DSToken ancestor;
    GebRewards stakingPool;
    RewardDripper rewardDripper;
    Caller unauth;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        hevm.roll(5000000);
        hevm.warp(100000001);

        ancestor = new DSToken("PROT", "PROT");
        rewardDripper = new RewardDripper(
            address(this),        // requestor
            address(ancestor),
            1 ether               // rewardPerBlock
        );

        stakingPool = new GebRewards(
            address(ancestor),
            address(ancestor),
            address(rewardDripper)
        );

        rewardDripper.modifyParameters("requestor", address(stakingPool));
        ancestor.mint(address(rewardDripper), 10000000 ether);

        ancestor.mint(address(this), 1000000000 ether);

        unauth = new Caller(stakingPool);
    }

    function test_setup() public {
        assertEq(address(stakingPool.ancestorPool().token()), address(ancestor));
        assertEq(address(stakingPool.rewardDripper()), address(rewardDripper));
        assertEq(address(stakingPool.rewardPool().token()), address(ancestor));
        assertEq(stakingPool.authorizedAccounts(address(this)), 1);
        assertEq(stakingPool.stakedSupply(), 0);
        assertTrue(stakingPool.canJoin());
    }

    function test_join() public {
        uint amount = 1 ether;

        ancestor.approve(address(stakingPool), amount);

        stakingPool.join(amount);

        assertEq(ancestor.balanceOf(address(stakingPool.ancestorPool())), amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)),amount);
    }

    function test_exit() public {
        uint amount = 2 ether;
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // exit
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.exit(amount);

        assertEq(ancestor.balanceOf(address(this)), previousBalance + amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
    }

    function test_exit_rewards_1(uint amount, uint blockDelay) public {
        amount = amount % 10**24 + 1; // up to 1mm staked
        blockDelay = blockDelay % 100 + 1; // up to 1000 blocks
        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        // exit
        hevm.roll(block.number + blockDelay);
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.exit(amount);

        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + amount + (blockDelay * 1 ether) - 1);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
    }

    function test_exit_rewards_2_users2(uint amount) public {
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
        uint previousBalance1 = ancestor.balanceOf(address(user1));
        uint previousBalance2 = ancestor.balanceOf(address(user2));

        user1.doExit(amount);
        user2.doExit(amount);

        assertTrue(ancestor.balanceOf(address(user1)) >= previousBalance1 + 16 ether -1); // .5 eth per block
        assertTrue(ancestor.balanceOf(address(user2)) >= previousBalance2 + 16 ether -1); // .5 eth per block
    }

    function test_get_rewards() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        uint previousBalance = ancestor.balanceOf(address(this));

        hevm.roll(block.number + 10); // 10 blocks

        stakingPool.getRewards();
        assertEq(ancestor.balanceOf(address(this)), previousBalance + 20 ether); // 1 eth per block

        hevm.roll(block.number + 8); // 8 blocks

        stakingPool.getRewards();
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 28 ether - 1); // 1 eth per block, division rounding causes a slight loss of precision
    }

    function test_rewards_dripper_depleated() public {
        uint amount = 7 ether;
        // leave rewards only for 20 blocks
        rewardDripper.transferTokenOut(address(0xfab), ancestor.balanceOf(address(rewardDripper)) - 20 ether);

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.exit(amount);
        assertEq(stakingPool.descendantBalanceOf(address(this)), 0);
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + amount + 20 ether - 1); // full amount
    }

    function test_rewards_dripper_depleated_recharged() public {
        uint amount = 7 ether;
        // leave rewards only for 20 blocks
        rewardDripper.transferTokenOut(address(0xfab), ancestor.balanceOf(address(rewardDripper)) - 20 ether);

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.getRewards();
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 20 ether - 1); // full amount

        hevm.roll(block.number + 32); // 32 blocks

        ancestor.mint(address(rewardDripper), 5 ether);
        stakingPool.getRewards();
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 25 ether - 1);
    }

    function test_rewards_change_dripper_emission() public {
        uint amount = 23 ether;

        ancestor.approve(address(stakingPool), amount);
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.getRewards();
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 32 ether - 1); // full amount

        rewardDripper.modifyParameters("rewardPerBlock", 0.5 ether);
        hevm.roll(block.number + 32); // 32 blocks

        stakingPool.getRewards();
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 48 ether - 1);
    }

    function test_deposit_rewards() public {
        uint amount = 23 ether;

        ancestor.approve(address(stakingPool), amount * 3);
        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.join(amount);

        hevm.roll(block.number + 32); // 32 blocks
        stakingPool.join(amount);
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 32 ether - 1 - (amount * 2)); // full amount

        hevm.roll(block.number + 32); // 32 blocks

        stakingPool.join(amount);
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 64 ether - 1 - (amount * 3));
    }

    function test_rewards_over_long_intervals() public {
        uint amount = 3.14 ether;
        Caller user1 = new Caller(stakingPool);
        ancestor.transfer(address(user1), amount);
        Caller user2 = new Caller(stakingPool);
        ancestor.transfer(address(user2), amount);

        // users 1 & 2 join, same amount
        user1.doJoin(amount);
        hevm.roll(block.number + 1000000); // 1mm blocks

        user2.doJoin(amount);
        hevm.roll(block.number + 1); // 1 block

        uint previousBalance1 = ancestor.balanceOf(address(user1));
        uint previousBalance2 = ancestor.balanceOf(address(user2));
        user1.doGetRewards();
        user2.doGetRewards();

        assertTrue(ancestor.balanceOf(address(user1)) >= previousBalance1 + 1000000.5 ether - 1);
        assertTrue(ancestor.balanceOf(address(user1)) <= previousBalance1 + 1000000.5 ether);
        assertTrue(ancestor.balanceOf(address(user2)) >= previousBalance2 + 0.5 ether - 1);
        assertTrue(ancestor.balanceOf(address(user2)) <= previousBalance2 + 0.5 ether);

        hevm.roll(block.number + 1); // 1 block

        user1.doGetRewards();
        user2.doGetRewards();
        assertTrue(ancestor.balanceOf(address(user1)) >= previousBalance1 + 1000001 ether - 1);
        assertTrue(ancestor.balanceOf(address(user1)) <= previousBalance1 + 1000001 ether);
        assertTrue(ancestor.balanceOf(address(user2)) >= previousBalance2 + 1 ether - 1);
        assertTrue(ancestor.balanceOf(address(user2)) <= previousBalance2 + 1 ether);
    }

    function test_get_rewards_externally_funded() public {
        uint amount = 10 ether;

        hevm.roll(block.number + 10);

        stakingPool.updatePool(); // no effect

        // join
        ancestor.approve(address(stakingPool), uint(-1));
        stakingPool.join(amount);

        hevm.roll(block.number + 10); // 10 blocks

        ancestor.mint(address(stakingPool.rewardPool()), 10 ether); // manually filling up contract

        uint previousBalance = ancestor.balanceOf(address(this));
        stakingPool.getRewards();
        assertEq(ancestor.balanceOf(address(this)), previousBalance + 30 ether); // 1 eth per block + externally funded

        hevm.roll(block.number + 4);
        stakingPool.pullFunds(); // pulling rewards to conrtact without updating

        hevm.roll(block.number + 4);
        ancestor.mint(address(stakingPool.rewardPool()), 2 ether); // manually filling up contract

        stakingPool.getRewards();
        assertTrue(ancestor.balanceOf(address(this)) >= previousBalance + 40 ether - 1); // 1 eth per block, division rounding causes a slight loss of precision
    }
}
