// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISolarPanelContract {
    function getEscrowTransactions() external returns (
        uint balance, 
        uint transactionCount, 
        address[] memory activeContributors
    );
}
