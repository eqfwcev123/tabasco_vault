// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TabascoVault {
    // Mappings
    //// @notice User deposit amount
    mapping(address => uint256) public depositAmount;
    //// @notice Vault total deposit amount
    mapping(uint256 => uint256) public vaultTotalDepositAmount;
    //// @notice Vault 
    mapping(uint256 => Vault) public vaultInfo;
    //// @notice Vault created information
    mapping(uint256 => bool) public vaultCreated;

    // Arrays
    uint256[] public vaultIds;

    // Struct
    struct Vault {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 strikePrice;
        bool withdrawan;
        bool deposited;
    }


    // Events
    event Deposit(address indexed user, uint256 vaultId, uint256 amount);
    event Withdrawal(uint256 vaultId);
    event CancelDeposit(uint256 vaultId);
    event CancelWithdrawal(uint256 vaultId);

    function getVaultById(uint256 _vaultId) private view returns(uint256){
        return vaultIds[_vaultId];
    }

    // Deposit to vault
    function deposit(uint256 _vaultId, uint256 _amount) external {
        uint256 vaultId = getVaultById(_vaultId);

        require(_amount > 0, "Deposit amount should be greater than 0");
        require(vaultCreated[_vaultId], "Vault not created");

        depositAmount[msg.sender] += _amount;
        vaultTotalDepositAmount[vaultId] += _amount;

        emit Deposit(msg.sender, _vaultId, _amount);
    }

    // Withdraw from vault
    function withdraw(uint256 _vaultId) external {
        require(vaultCreated[_vaultId], "Vault not created");
        require(depositAmount[msg.sender] > 0, "Fund not deposited");
    }
}