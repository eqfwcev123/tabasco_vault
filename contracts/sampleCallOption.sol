// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SampleCallOption {
    AggregatorV3Interface internal ethFeed;
    AggregatorV3Interface internal linkFeed;

    LinkTokenInterface internal LINK;
    uint256 ethPrice;
    uint256 linkPrice;
    // Precompute hash of strings;
    bytes32 ethHash = keccak256(abi.encodePacked("ETH"));
    bytes32 linkHash = keccak256(abi.encodePacked("LINK"));
    address payable contractAddr;

    struct Option {
        uint256 strike;
        uint256 premium;
        uint256 expiry;
        uint256 amount;
        bool exercised;
        bool canceled;
        uint256 id;
        uint256 latestCost;
        address payable writer;
        address payable buyer;
    }

    Option[] public ethOpts;
    Option[] public linkOpts;

    constructor() public {
        // ETH/USD Rinkeby Feed
        ethFeed = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e);
        //LINK/USD Rinkeby feed
        linkFeed = AggregatorV3Interface(0xd8bD0a1cB028a31AA859A21A3758685a95dE4623);
        //LINK token address on Rinkeby
        LINK = LinkTokenInterface(0xa36085F69e2889c224210F603D836748e7dC0088);
        contractAddr = payable(address(this));
    }

    function getEthPrice() public view returns (uint256){ 
        (
            uint80 roundID,
            int price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = ethFeed.latestRoundData();
        // If the round is not complete yet, timestammp is 0
        require(timeStamp > 0, "Round not yet completed");
        // Price should never be negative thus in to uint is ok
        // Price is 8 decimal places and will require 1e10 correction later to 18 places
        return uint256(price);
    }

    function getLinkPrice() public view returns (uint256) {
        (
            uint80 roundID,
            int price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = linkFeed.latestRoundData();
        // If the round is not complete yet, timestammp is 0
        require(timeStamp > 0, "Round not yet completed");
        // Price should never be negative thus in to uint is ok
        // Price is 8 decimal places and will require 1e10 correction later to 18 places
        return uint256(price);
    }

    function updatePrices() internal { 
        ethPrice = getEthPrice();
        linkPrice = getLinkPrice();
    }


    // Allows user to write a covered call option
    // Takes which token, a strike price(USD per token w/18 decimal places), premium(same unit as token), expiration time(unix) and how many tokens the contract is for
    function writeOption(
        string memory _token,
        uint256 _strike,
        uint256 _premium,
        uint256 _expiry,
        uint256 _tknAmount
    ) public payable {
        // Cannot compare strings in solidity using ==
        // Hash each string to a 32byte hash with keccak256() and compare the hashes directly
        bytes32 tokenHash = keccak256(abi.encodePacked(_token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK tokens are supported");
        // Update LINK and ETH price
        updatePrices();

        if (tokenHash == ethHash) {
            require(msg.value == _tknAmount, "Incorrect amount of ETH supplied");
            // Current cost to exercise the option
            // ETH price is multiplied by 10**10 because Chainlink price feeds are 8 decimals but default will be 18 decimals
            uint256 latestCost = (_strike * _tknAmount) / (ethPrice * 10**10);
            ethOpts.push(Option(
                _strike, 
                _premium, 
                _expiry, 
                _tknAmount, 
                false, 
                false, 
                ethOpts.length, 
                latestCost, 
                payable(msg.sender), 
                payable(address(0)
                )));
        } else {
            // msg.value only provides the amount of ETH in transaction
            // It is better to interact directly with the LINK token contract
            require(LINK.transferFrom(msg.sender, contractAddr, _tknAmount),"Incorrect amount of LINK supplied");
            uint256 latestCost = (_strike * _tknAmount) / linkPrice * 10**10;
            linkOpts.push(
                Option(
                    _strike,
                    _premium,
                    _expiry,
                    _tknAmount,
                    false, 
                    false,
                    linkOpts.length,
                    latestCost, 
                    payable(msg.sender),
                    payable(address(0))
                )
            );
        }
    }

    function cancelOption(string memory _token, uint256 ID) public payable {
        bytes32 tokenHash = keccak256(abi.encodePacked(_token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK tokens are supported");
        if (tokenHash == ethHash){
            require(msg.sender == ethOpts[ID].writer, "You did not write this Option");
            require(!ethOpts[ID].canceled && ethOpts[ID].buyer == address(0), "This option cannot be canceled");
            ethOpts[ID].writer.transfer(ethOpts[ID].amount);
            ethOpts[ID].canceled = true;
        } else {
            require(msg.sender == linkOpts[ID].writer, "You did not write this option");
            require(!linkOpts[ID].canceled && linkOpts[ID].buyer == address(0), "This option cannot be canceled");
            require(LINK.transferFrom(address(this), linkOpts[ID].writer, linkOpts[ID].amount), "Incorrect amount of LINK sent");
            linkOpts[ID].canceled = true;
        }

    }

    function buyOption(string memory _token, uint256 ID) public payable {
        bytes32 tokenHash = keccak256(abi.encodePacked(_token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK is supported");
        updatePrices();

        if(tokenHash == ethHash){
            require(!ethOpts[ID].canceled && ethOpts[ID].expiry > block.timestamp , "Option is canceled/expired and cannot be bought");
            require(msg.value == ethOpts[ID].premium, "Incorrect amount of ETH sent for premium");
            ethOpts[ID].writer.transfer(ethOpts[ID].premium);
            ethOpts[ID].buyer = payable(msg.sender);
        } else {
            require(!linkOpts[ID].canceled && linkOpts[ID].expiry > block.timestamp, "Option is canceled/expired and cannot be bought");
            require(LINK.transferFrom(msg.sender, linkOpts[ID].writer, linkOpts[ID].premium));
            linkOpts[ID].buyer = payable(msg.sender);
        }
    }

    function exercise(string memory _token, uint256 ID) public payable {
        bytes32 tokenHash = keccak256(abi.encodePacked(_token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK is supported");
        if(tokenHash == ethHash) {
            require(ethOpts[ID].buyer == msg.sender, "You do not own this option");
            require(!ethOpts[ID].exercised, "Option has alredy been exercised");
            require(ethOpts[ID].expiry > block.timestamp, "Option is expired");
            updatePrices();
            uint256 exerciseVal = ethOpts[ID].strike *ethOpts[ID].amount;
            // Equivalent ETH value using Chainlink Feed
            uint256 equivEth = exerciseVal / (ethPrice * 10**10);
            // Buyer exercises option by paying strike * amount equivalent ETH value
            require(msg.value == equivEth, "Incorrect LINK amount sent to exercise");
            // Pay writer the exercise cost
            ethOpts[ID].writer.transfer(equivEth);
            // Pay buyer contract amount of ETH
            payable(msg.sender).transfer(ethOpts[ID].amount);
            ethOpts[ID].exercised = true;
        } else {
            require(linkOpts[ID].buyer == msg.sender, "You do not own this option");
            require(!linkOpts[ID].exercised, "Option has already been exercised");
            require(linkOpts[ID].expiry > block.timestamp, "Option has already been expired");
            updatePrices();
            uint256 exerciseVal = linkOpts[ID].strike * linkOpts[ID].amount;
            uint256 equivLink = exerciseVal / (linkPrice * 10**10);
            // Buyer exercise option, exercise cost paid to writer
            require(LINK.transferFrom(msg.sender, linkOpts[ID].writer, equivLink), "Incorrect amount of LINK sent to exercise");
            // Pay buyer contract amount of LINK
            require(LINK.transfer(msg.sender, linkOpts[ID].amount), "Error: Buyer was not paid");
            linkOpts[ID].exercised = true;
        }
    }

    function retrieveExpiredFunds(string memory _token, uint256 ID) public payable {
        bytes32 tokenHash = keccak256(abi.encodePacked(_token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK is supported");
        if(tokenHash == ethHash) {
            require(msg.sender == ethOpts[ID].writer, "You did not write this option");
            // Must be expired, not exercised and not canceled
            require(ethOpts[ID].expiry <= block.timestamp && !ethOpts[ID].exercised && !ethOpts[ID].canceled, "This is not eligible for withdraw");
            ethOpts[ID].writer.transfer(ethOpts[ID].amount);
            ethOpts[ID].canceled = true;
        } else {
            require(msg.sender == linkOpts[ID].writer, "You did not write this Option");
            require(linkOpts[ID].expiry <= block.timestamp && !linkOpts[ID].exercised && !linkOpts[ID].canceled, "This option is not eligible for withdraw");
            require(LINK.transferFrom(address(this), linkOpts[ID].writer, linkOpts[ID].amount), "Incorrect amount of LINK sent");
            linkOpts[ID].canceled = true;
        }
    }

    function updateExerciseCost(string memory _token, uint256 ID) public {
        bytes32 tokenHash = keccak256(abi.encodePacked(_token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK is supported");
        updatePrices();
        if(tokenHash == ethHash){
            ethOpts[ID].latestCost = ethOpts[ID].strike * ethOpts[ID].amount / (ethPrice * (10**10));
        } else {
            linkOpts[ID].latestCost = linkOpts[ID].strike * linkOpts[ID].amount / (linkPrice * 10 ** 10);
        }
    }

}