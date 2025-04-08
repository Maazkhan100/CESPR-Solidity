// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SolarPanel.sol";

contract UtilityContract {

    struct Summary {
        string summaryID;
        uint balance;
        uint transactionCount;
        address[] activeContributors;
        string date;
    }

    event PeriodicSummaryCreated(string summaryID, uint balance, uint transactionCount, address[] activeContributors, string date);

    address public owner;
    SolarPanel public solarPanelContract;

    mapping(string => Summary) public summaries;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    constructor(address _solarPanelContract) {
        owner = msg.sender;
        solarPanelContract = SolarPanel(_solarPanelContract);
    }

    function createPeriodicSummary(string memory summaryID, string memory date) 
        external onlyOwner returns (uint balance, uint transactionCount, 
        address[] memory activeContributors)
    {
        try solarPanelContract.getEscrowTransactions() returns (
            uint _balance, uint _transactionCount, address[] memory _activeContributors
        ) {
            balance = _balance;
            transactionCount = _transactionCount;
            activeContributors = _activeContributors;
        } catch {
            revert("Failed to fetch escrow transactions from SolarPanelContract");
        }

        // Store the summary
        summaries[summaryID] = Summary({
            summaryID: summaryID,
            balance: balance,
            transactionCount: transactionCount,
            activeContributors: activeContributors,
            date: date
        });

        emit PeriodicSummaryCreated(summaryID, balance, transactionCount, activeContributors, date);

        return (balance, transactionCount, activeContributors);
    }
}
