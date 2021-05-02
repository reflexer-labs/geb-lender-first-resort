pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebLenderFirstResort.sol";

contract GebLenderFirstResortTest is DSTest {
    GebLenderFirstResort resort;

    function setUp() public {
        resort = new GebLenderFirstResort();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
