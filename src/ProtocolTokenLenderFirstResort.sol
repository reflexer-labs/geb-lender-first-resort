pragma solidity 0.6.7;

abstract contract TokenLike {
    function approve(address, uint256) virtual external returns (bool);
    function transferFrom(address,address,uint256) virtual external returns (bool);
}
abstract contract AuctionHouseLike {
    function startAuction(uint256) external returns (uint256 id);
}
abstract contract AccountingEngineLike {

}

contract ProtocolTokenLenderFirstResort {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) virtual external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) virtual external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "ProtocolTokenLenderFirstResort/account-not-authorized");
        _;
    }

    // --- Structs ---
    struct ExitWindow {
        // Start time when the exit can happen
        uint256 start;
        // Exit window deadline
        uint256 end;
    }

    // --- Variables ---
    // Flag that allows/blocks joining
    bool      public canJoin;
    // The current delay enforced on an exit
    uint256   public exitDelay;
    // Time during which an address can exit without requesting a new window
    uint256   public exitWindow;
    // Total amount staked
    uint256   public totalStaked;
    // Min maount of staked tokens that must remain in the contract and not be auctioned
    uint256   public minStakedTokensToKeep;

    // Amounts staked by each address
    mapping(address => uint256)    public staked;

    // Exit data
    mapping(address => ExitWindow) public exitWindows;

    // Token being staked
    TokenLike            public stakedToken;
    // Auction house for staked tokens
    AuctionHouseLike     public auctionHouse;
    // Accounting engine contract
    AccountingEngineLike public accountingEngine;

    // Max delay that can be enforced for an exit
    uint256 public immutable MAX_DELAY;
    // Minimum exit window during which an address can exit without waiting again for another window
    uint256 public immutable MIN_EXIT_WINDOW;
    // Max exit window during which an address can exit without waiting again for another window
    uint256 public immutable MAX_EXIT_WINDOW;


}
