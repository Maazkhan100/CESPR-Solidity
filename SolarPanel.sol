// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISolarPanelContract.sol";

contract SolarPanel is ISolarPanelContract {
    
    struct SolarPanelData {
        string id;
        address manufacturer;
        address prosumer;
        address recyclingCompany;
        uint recyclingCost;
        uint totalContributions;
        uint256 remainingContributors;
        PanelMetadata metadata;
        bool acknowledgeTransportFee;
        bool acknowledgeRecyclerFee;
    }

    struct PanelMetadata {
        string warrantyClaim;
        string status;
        string purchaseDate;
        string eolDate;
    }

    struct Agreement {
        string id;
        address manufacturer;
        address prosumer;
        address recycler;
        uint recyclingCost;
        string warrantyClaim;
        string purchaseDate;
        string eolDate;
        string solarPanelId;
    }

    struct EscrowAccount {
        uint balance;
        mapping(string => Transaction) transactions;
        string[] transactionIds;
    }

    struct Transaction {
        string transactionID;
        string transactionType;
        uint amount;
        string description;
        string transactionDate;
        address contributor;
        uint passingCount;
        uint verifiedCount;
        string status;
        mapping(address => bool) verifiedBy;
        bool isVerified;
    }

    struct AcknowledgeTransaction {
        string transactionId;
        string panelId;
        string description;
        address prosumer;
        uint amount;
        string date;
    }

    struct AcknowledgeReceipt {
        string transactionId;
        string panelId;
        string description;
        address recycler;
        string date;
    }

    struct PanelTransactionBeforeWarranty {
        string transactionID;
        string panelID;
        string failureDate;
        string cause;
        uint256 remainingRecyclingCost;
        string warrantyClaim;
        address manufacturer;
        address prosumer; 
    }

    event RecyclingContribution (string panelId, address indexed prosumer, uint amount, string transactionDate);
    event PanelTransferredToRecycler(string);
    event SolarPanelDetails(
        string id,
        address manufacturer,
        address prosumer,
        address recyclingCompany,
        uint recyclingCost,
        string warrantyClaim,
        string status,
        string purchaseDate,
        string eolDate,
        uint totalContributions,
        uint256 remainingContributors
    );
    event TransactionVerified(string transactionID, bool isVerified, string status);

    mapping(string => SolarPanelData) public solarPanels;
    mapping(string => Agreement) public agreements;
    mapping(string => EscrowAccount) public escrowAccounts;
    mapping(string => AcknowledgeTransaction) public acknowledgmentTransactions;
    mapping(string => AcknowledgeReceipt) public acknowledgmentReceipts;
    mapping(string => PanelTransactionBeforeWarranty) public panelFailureTransactions;

    address public utility = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
    bytes32 public merkleRoot;
    uint256 public merkleRootCounter;

    // Solar Panel Registration
    function registerPanel(
        string memory id,
        address prosumer,
        address recycler,
        uint recyclingCost,
        string memory warrantyClaim,
        string memory purchaseDate,
        string memory eolDate
    ) public {
        require(bytes(solarPanels[id].id).length == 0, "Solar panel already exists");

        SolarPanelData storage panel = solarPanels[id];

        // Initialize struct fields separately
        panel.id = id;
        panel.manufacturer = msg.sender;
        panel.prosumer = prosumer;
        panel.recyclingCompany = recycler;
        panel.recyclingCost = recyclingCost;
        panel.metadata.warrantyClaim = warrantyClaim;
        panel.metadata.status = "active";
        panel.metadata.purchaseDate = purchaseDate;
        panel.metadata.eolDate = eolDate;
        panel.totalContributions = 0;
        panel.remainingContributors = 0;
        panel.acknowledgeTransportFee = false;
        panel.acknowledgeRecyclerFee = false;
    }

    // Agreement Creation
    function createAgreement(
        string memory agreementId,
        string memory panelId,
        address prosumer,
        address recycler,
        uint recyclingCost,
        string memory warrantyClaim,
        string memory purchaseDate,
        string memory eolDate
    ) public {
        require(bytes(agreementId).length > 0, "Agreement ID required");
        require(bytes(panelId).length > 0, "Solar panel ID required");
        require(bytes(agreements[agreementId].id).length == 0, "Agreement already exists");
        require(recyclingCost > 0, "Recycling cost must be positive");
        require(prosumer != address(0) && recycler != address(0), "Invalid addresses");
        agreements[agreementId] = Agreement({
            id: agreementId,
            manufacturer: msg.sender,
            prosumer: prosumer,
            recycler: recycler,
            recyclingCost: recyclingCost,
            warrantyClaim: warrantyClaim,
            purchaseDate: purchaseDate,
            eolDate: eolDate,
            solarPanelId: panelId
        });

        // Automatically register the associated solar panel
        registerPanel(panelId, prosumer, recycler, recyclingCost, warrantyClaim, purchaseDate, eolDate);
    }

    // Contribute Recycling Cost
    function contributeRecyclingCost (
        string memory panelId,
        string memory transactionID,
        uint amount,
        uint energyUnits,
        string memory transactionDate
    ) public {
        SolarPanelData storage panel = solarPanels[panelId];

        require(bytes(panel.id).length > 0, "Panel does not exist");

        require(
            keccak256(abi.encodePacked(panel.metadata.status)) == keccak256(abi.encodePacked("active")),
            "Cannot contribute, panel must be in active state"
        );

        require(panel.prosumer == msg.sender, "Caller is not the prosumer of this panel");

        require(amount > 0, "Contribution amount must be greater than zero");

        string memory description = string(abi.encodePacked("Recycling contribution for panel ", panelId, "units generated", energyUnits));

        // Log contribution to escrow account with date
        addTransaction(transactionID, "credit", amount, description, transactionDate, msg.sender);

        emit RecyclingContribution(panelId, msg.sender, amount, transactionDate);
    }

    function markPanelAsFailed(string memory panelID) public {
        // Ensure the panel exists
        require(bytes(solarPanels[panelID].id).length > 0, "Panel does not exist");

        // Ensure the panel is not already failed
        require(keccak256(abi.encodePacked(solarPanels[panelID].metadata.status)) != keccak256(abi.encodePacked("failed")), "Panel is already marked as failed");

        // Mark the panel as failed
        solarPanels[panelID].metadata.status = "failed";
    }

    function acknowledgeTransportFee(string memory panelId, string memory transactionId, uint amount, string memory date) public {
        SolarPanelData storage panel = solarPanels[panelId];
        
        // Ensure the panel exists
        require(bytes(panel.id).length > 0, "Solar panel does not exist");

        require(
            keccak256(abi.encodePacked(panel.metadata.status)) == keccak256(abi.encodePacked("failed")),
            "Cannot acknowledge fee, panel is not failed"
        );

        // Ensure the sender is the correct prosumer
        require(panel.prosumer == msg.sender, "Only the prosumer of this panel can acknowledge the fee");

        require(!panel.acknowledgeTransportFee, "Transport fee already acknowledged");

        require(bytes(acknowledgmentTransactions[transactionId].transactionId).length == 0, "Transaction ID already exists");

        require(amount > 0, "Transport fee amount must be greater than zero");

        require(panel.totalContributions >= amount, "Insufficient contributions in the panel");
        panel.totalContributions -= amount;

        EscrowAccount storage account = escrowAccounts["escrow_account"];
        require(account.balance >= amount, "Insufficient account balance");
        account.balance -= amount;

        // Create a description for the acknowledgment
        string memory description = string(abi.encodePacked("Transport fee acknowledged for panel ", panelId));

        // Store the transaction
        acknowledgmentTransactions[transactionId] = AcknowledgeTransaction({
            transactionId: transactionId,
            panelId: panelId,
            description: description,
            prosumer: msg.sender,
            amount: amount,
            date: date
        });

        panel.acknowledgeTransportFee = true;
    }

    function sendToRecycler(string memory panelId, address recycler) public returns (string memory) {
        // Ensure the panel exists
        require(bytes(solarPanels[panelId].id).length > 0, "Solar panel does not exist");

        require(
            keccak256(bytes(solarPanels[panelId].metadata.status)) != keccak256(bytes("Transferred to Recycler")),
            "Panel has already been sent to recycler"
        );

        // Ensure the sender is the correct prosumer associated with the panel
        require(solarPanels[panelId].prosumer == msg.sender, "Only the prosumer of this panel can send it to the recycler");

        // Ensure the provided recycler matches the registered one
        require(solarPanels[panelId].recyclingCompany == recycler, "Invalid recycler: Not registered for this panel");

        // Change the status of the panel to "Transferred to Recycler"
        solarPanels[panelId].metadata.status = "Transferred to Recycler";

        // Emit event for tracking
        emit PanelTransferredToRecycler("Transferred to Recycler");

        return "Transferred to Recycler";
    }

    // Function for acknowledging receipt of panel
    function acknowledgeReceipt(string memory panelId, string memory transactionId, string memory date) public returns (string memory) {
        // Ensure the panel exists and retrieve status and recycler
        require(bytes(solarPanels[panelId].id).length > 0, "Solar panel does not exist");

        require(bytes(acknowledgmentReceipts[transactionId].transactionId).length == 0, "Transaction ID already exists");

        string memory status = string(abi.encodePacked(solarPanels[panelId].metadata.status));
        address recycler = solarPanels[panelId].recyclingCompany;

        // Ensure panel has been transferred
        require(keccak256(abi.encodePacked(status)) == keccak256(abi.encodePacked("Transferred to Recycler")), "Panel not yet transferred");

        // Ensure caller is the correct recycler
        require(recycler == msg.sender, "Only the assigned recycler can acknowledge receipt");

        // Create description
        string memory description = string(abi.encodePacked("Panel received for recycling: ", panelId));

        // Store acknowledgment in the mapping
        acknowledgmentReceipts[transactionId] = AcknowledgeReceipt({
            transactionId: transactionId,
            panelId: panelId,
            description: description,
            recycler: msg.sender,
            date: date
        });

        // Update status to "Received by Recycler"
        solarPanels[panelId].metadata.status = "Received by Recycler";

        // Emit event for tracking receipt acknowledgment
        emit PanelTransferredToRecycler("Received by Recycler");

        return "Received by Recycler";
    }

    // Function for acknowledging payment for recycling
    function acknowledgePayment(string memory panelId, string memory transactionId, uint amount, string memory date) public {
        SolarPanelData storage panel = solarPanels[panelId];

        // Ensure the panel exists and retrieve status and recycler
        require(bytes(panel.id).length > 0, "Solar panel does not exist");

        require(!panel.acknowledgeRecyclerFee, "Recycler fee already acknowledged");

        require(bytes(acknowledgmentTransactions[transactionId].transactionId).length == 0, "Transaction ID already exists");
        
        string memory status = string(abi.encodePacked(panel.metadata.status));
        address recycler = panel.recyclingCompany;

        // Ensure caller is the correct recycler and panel is in the right status
        require(recycler == msg.sender, "Only the assigned recycler can acknowledge payment");
        require(keccak256(abi.encodePacked(status)) == keccak256(abi.encodePacked("Received by Recycler")), "Panel is not yet received by the recycler");

        require(amount >= panel.recyclingCost, "Amount must be greater or equal than the panel's recycling cost");

        require(panel.totalContributions >= amount, "Insufficient contributions in the panel");
        panel.totalContributions -= amount;
        
        EscrowAccount storage account = escrowAccounts["escrow_account"];
        require(account.balance >= amount, "Insufficient escrow balance");
        account.balance -= amount;

        // Create description
        string memory description = string(abi.encodePacked("Payment received for recycling panel ", panelId));

        // Store acknowledgment in mapping
        acknowledgmentTransactions[transactionId] = AcknowledgeTransaction({
            transactionId: transactionId,
            panelId: panelId,
            description: description,
            prosumer: msg.sender,    // Here it is recycler.
            amount: amount,
            date: date
        });

        panel.acknowledgeRecyclerFee = true;
    }

    // Case 2:
    // Function to record panel failure
    function recordFailure(
        string memory panelID,
        string memory transactionID,
        string memory failureDate,
        string memory cause,
        string memory warrantyClaim
    ) public returns (string memory) {
        // Ensure the panel exists
        require(bytes(solarPanels[panelID].id).length > 0, "Panel does not exist");

        require(bytes(panelFailureTransactions[transactionID].transactionID).length == 0, "Transaction ID already exists");

        // Retrieve panel details
        SolarPanelData memory panel = solarPanels[panelID];
        
        // Ensure caller is the registered prosumer
        require(msg.sender == panel.prosumer, "Caller is not the registered prosumer");

        // Ensure the panel is active and has not failed already
        require(keccak256(abi.encodePacked(panel.metadata.status)) != keccak256(abi.encodePacked("failed")), "Panel has already failed");

        // Calculate remaining recycling cost
        uint256 remainingRecyclingCost = (panel.recyclingCost > panel.totalContributions)
            ? (panel.recyclingCost - panel.totalContributions)
            : 0;

        // Create and store failure transaction
        panelFailureTransactions[transactionID] = PanelTransactionBeforeWarranty({
            transactionID: transactionID,
            panelID: panelID,
            failureDate: failureDate,
            cause: cause,
            remainingRecyclingCost: remainingRecyclingCost,
            warrantyClaim: warrantyClaim,
            manufacturer: panel.manufacturer,
            prosumer: msg.sender
        });

        // Update the panel's status to "failed"
        solarPanels[panelID].metadata.status = "failed";

        return "failed";
    }

    // Function to record the manufacturer deposit
    function manufacturerDeposit(
        string memory panelID,
        uint256 amount,
        string memory transactionID,
        uint256 transportFee,
        string memory date
    ) public {
        SolarPanelData storage panel = solarPanels[panelID];

        // Ensure the panel exists
        require(bytes(panel.id).length > 0, "Panel does not exist");

        // Ensure only the manufacturer can deposit
        require(msg.sender == panel.manufacturer, "Caller is not the manufacturer");

        // Ensure the panel is in "failed" status
        require(
            keccak256(abi.encodePacked(panel.metadata.status)) == keccak256(abi.encodePacked("failed")),
            "Panel is not in failed state"
        );

        // Calculate the remaining recycling cost
        uint256 remainingRecyclingCost = panel.recyclingCost - panel.totalContributions;

        // Total deposit amount required
        uint256 totalCost = remainingRecyclingCost + transportFee;
        require(amount >= totalCost, "Insufficient deposit amount");

        // Generate a transaction description
        string memory description = string(abi.encodePacked("Manufacturer deposit for panel ", panelID, " on ", date));

        // Record the transaction in the Utility contract
        addTransaction(transactionID, "credit", amount, description, date, msg.sender);
    }

    // Case 3:
    // Function to record failure after warranty expiry
    function recordFailureAfterWarranty(
        string memory panelID, 
        string memory failureDate,
        string memory cause,
        string memory transactionID
    ) public returns (string memory, uint256, address) {
        SolarPanelData storage panel = solarPanels[panelID];
        
        // Ensure the panel exists
        require(bytes(panel.id).length > 0, "Panel does not exist");

        // Ensure caller is the registered prosumer
        require(msg.sender == panel.prosumer, "Caller is not the registered prosumer");

        // Ensure the panel is active and has not already failed
        require(keccak256(abi.encodePacked(panel.metadata.status)) != keccak256(abi.encodePacked("failed")), "Panel has already failed");

        require(bytes(panelFailureTransactions[transactionID].transactionID).length == 0, "Transaction ID already exists");

        // Calculate remaining recycling cost
        uint256 remainingRecyclingCost = (panel.recyclingCost > panel.totalContributions) 
            ? (panel.recyclingCost - panel.totalContributions) 
            : 0;
        
        require(remainingRecyclingCost > 0, "No remaining recycling cost");

        // Calculate 1/3 share for each stakeholder
        uint256 share = remainingRecyclingCost / 3;

        // Update the remaining contributors' share (since there's no ManufacturerContract, we assume this update is logged within the panel or elsewhere)
        panel.remainingContributors = share;

        // Store failure transaction
        panelFailureTransactions[transactionID] = PanelTransactionBeforeWarranty({
            transactionID: transactionID,
            panelID: panelID,
            failureDate: failureDate,
            cause: cause,
            remainingRecyclingCost: remainingRecyclingCost,
            warrantyClaim: "", // No warranty claim after warranty expiry
            manufacturer: panel.manufacturer,
            prosumer: msg.sender
        });

        // Update panel status to "failed"
        panel.metadata.status = "failed";

        // Return the relevant information
        return (cause, remainingRecyclingCost, msg.sender);
    }

    function payRecyclingContribution(string memory panelID, string memory transactionID, uint256 amount, string memory date) public {
        // Ensure the panel exists
        require(bytes(solarPanels[panelID].id).length != 0, "Panel does not exist");

        // Retrieve the panel
        SolarPanelData storage panel = solarPanels[panelID];

        // Ensure the panel status is "failed" before allowing contributions
        require(keccak256(abi.encodePacked(panel.metadata.status)) == keccak256(abi.encodePacked("failed")), "Panel must be in failed state");

        // Ensure caller is an authorized contributor
        require(
            msg.sender == panel.prosumer || msg.sender == panel.manufacturer || msg.sender == panel.recyclingCompany,
            "Caller is not an authorized contributor"
        );

        // Get the expected share (already pre-calculated and stored in remainingContributors)
        uint256 expectedShare = panel.remainingContributors;

        // Ensure the amount is correct
        if (amount < expectedShare) {
            revert(string(abi.encodePacked("Amount must be equal to or greater than the required share: ", uint2str(expectedShare))));
        }
        
        string memory description = string(
            abi.encodePacked("Recycling contribution for panel ", panelID, " on ", date)
        );

        addTransaction(transactionID, "credit", amount, description, date, msg.sender);
    }

    // Interface and other functions:
    // Add Transaction to Escrow
    function addTransaction(
        string memory transactionID,
        string memory transactionType,
        uint amount,
        string memory description,
        string memory transactionDate,
        address contributor
    ) internal {
        EscrowAccount storage account = escrowAccounts["escrow_account"];

        require(bytes(account.transactions[transactionID].transactionID).length == 0, "Transaction ID already exists");

        Transaction storage newTransaction = account.transactions[transactionID];
        newTransaction.transactionID = transactionID;
        newTransaction.transactionType = transactionType;
        newTransaction.amount = amount;
        newTransaction.description = description;
        newTransaction.transactionDate = transactionDate;
        newTransaction.contributor = contributor;
        newTransaction.passingCount = 0;
        newTransaction.verifiedCount = 0;
        newTransaction.status = "pending";
        newTransaction.isVerified = false;

        account.transactionIds.push(transactionID);
    }

    // Verify Transaction (Only Manufacturer, Utility, or Recycler associated with the panel)
    function verifyTransaction(string memory transactionID, string memory panelId, bool isPass) public {
        SolarPanelData storage panel = solarPanels[panelId];
        EscrowAccount storage account = escrowAccounts["escrow_account"];

        require(bytes(panel.id).length > 0, "Panel does not exist");

        require(bytes(account.transactions[transactionID].transactionID).length > 0, "Transaction not found");

        // Ensure caller is an associated stakeholder
        require(
            msg.sender == panel.manufacturer || msg.sender == panel.recyclingCompany || msg.sender == utility,
            "Caller is not an authorized stakeholder"
        );

        // Access transaction directly using mapping
        Transaction storage txn = account.transactions[transactionID];

        require(!txn.verifiedBy[msg.sender], "You have already verified this transaction");

        txn.verifiedBy[msg.sender] = true;
        txn.verifiedCount++;

        if (isPass) {
            txn.passingCount++;
        }

        // Check if all stakeholders have verified
        if (txn.verifiedCount == 3) {
            txn.isVerified = true;

            if (txn.passingCount >= 2) {
                txn.status = "pass";

                // Process escrow balance
                if (keccak256(abi.encodePacked(txn.transactionType)) == keccak256("credit")) {
                    account.balance += txn.amount;
                    panel.totalContributions += txn.amount;
                } else if (keccak256(abi.encodePacked(txn.transactionType)) == keccak256("debit")) {
                    require(account.balance >= txn.amount, "Insufficient funds in escrow");
                    account.balance -= txn.amount;
                    panel.totalContributions -= txn.amount;
                }
            } else {
                txn.status = "failed";
            }

            updateMerkleRoot(transactionID);
            
            delete account.transactions[transactionID];
            // Emit event indicating transaction verification is complete
            emit TransactionVerified(transactionID, txn.isVerified, txn.status);
        }
    }

    function updateMerkleRoot(string memory transactionID) internal {
        bytes32 transactionHash = keccak256(abi.encodePacked(transactionID));

        if (merkleRoot == bytes32(0)) {
            // First transaction case: Hash the transaction ID with itself
            merkleRoot = keccak256(abi.encodePacked(transactionHash, transactionHash));
        } else {
            // Otherwise, update by hashing previous root with the new transaction hash
            merkleRoot = keccak256(abi.encodePacked(merkleRoot, transactionHash));
        }

        merkleRootCounter++;
    }

    function getEscrowTransactions() external override returns (
        uint balance, uint transactionCount, address[] memory activeContributors
    ){
        EscrowAccount storage account = escrowAccounts["escrow_account"];

        require(account.transactionIds.length > 0, "No transactions to summarize");
        
        // Track unique active contributors
        address[] memory tempContributors = new address[](account.transactionIds.length);
        uint activeCount = 0;

        for (uint i = 0; i < account.transactionIds.length; i++) {
            string memory transactionID = account.transactionIds[i];
            address contributor = account.transactions[transactionID].contributor;

            // Check if already added
            bool alreadyAdded = false;
            for (uint j = 0; j < activeCount; j++) {
                if (tempContributors[j] == contributor) {
                    alreadyAdded = true;
                    break;
                }
            }

            // If not added, include the contributor in the active list
            if (!alreadyAdded) {
                tempContributors[activeCount] = contributor;
                activeCount++;
            }
        }

        // Create exact-sized array
        activeContributors = new address[](activeCount);
        for (uint i = 0; i < activeCount; i++) {
            activeContributors[i] = tempContributors[i];
        }

        balance = account.balance;
        transactionCount = account.transactionIds.length;

        // Clear transaction history after summarization
        delete account.transactionIds;

        return (balance, transactionCount, activeContributors);
    }

    // Helper function:
    function uint2str(uint _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        while (_i != 0) {
            len--;
            bstr[len] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }

    function getSolarPanelDetails(string memory panelID) public {
        // Ensure the panel exists
        require(bytes(solarPanels[panelID].id).length > 0, "Panel does not exist");

        SolarPanelData storage panel = solarPanels[panelID];

        // Emit event
        emit SolarPanelDetails(panel.id, panel.manufacturer, panel.prosumer, panel.recyclingCompany,
            panel.recyclingCost, panel.metadata.warrantyClaim, panel.metadata.status,
            panel.metadata.purchaseDate, panel.metadata.eolDate, panel.totalContributions,
            panel.remainingContributors
        );
    }

    function getSolarPanelDetailsStruct(string memory panelID) public view returns (SolarPanelData memory) {
        require(bytes(solarPanels[panelID].id).length > 0, "Panel does not exist");
        return solarPanels[panelID];
    }
}
