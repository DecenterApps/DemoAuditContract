pragma solidity ^0.4.24;

import './SafeMath.sol';

contract HashAuction {
    using SafeMath for uint;

    struct Hash {
        address owner;
        bytes32 hash;
        bool challengePeriodStarted;
        uint challengePeriodEnd;
        uint commitPeriodEnd;
        uint revealPeriodEnd;
        uint votesFor;
        uint votesAgainst;
        bool depositedForAuction;
        uint auctionStartOn;
        uint auctionStartPrice;
        uint auctionEndPrice;
        uint auctionDuration;
        bool inAuction;
        mapping(address => Vote) vote;
    }

    struct Vote {
        bytes32 secretHash;
        bool option;
        uint amount;
        uint revealedOn;
        uint claimedRewardOn;
    }

    uint challengeDuration;
    uint commitDuration;
    uint revealDuration;
    uint generateCost;
    uint regenerateCost;
    uint challengeCost;
    uint voteAmount;
    uint auctionCut;
    address auctionCutCollector;
    address owner;
    mapping (address => address[]) public userHashes;
    mapping (address => Hash) public hashes;

    constructor(
        uint _challengeDuration,
        uint _commitDuration,
        uint _revealDuration,
        uint _generateCost,
        uint _regenerateCost,
        uint _challengeCost,
        uint _auctionCut,
        address _auctionCutCollector,
        address _owner
    ) public {
        challengeDuration = _challengeDuration;
        commitDuration = _commitDuration;
        revealDuration = _revealDuration;
        generateCost = _generateCost;
        regenerateCost = _regenerateCost;
        challengeCost = _challengeCost;
        auctionCut = _auctionCut;
        auctionCutCollector = _auctionCutCollector;
        owner = _owner;
    }

    /**
    * @dev Generates awesome hash.
    */
    function generateHash(
        uint _seed
    ) public payable {
        require(msg.value >= generateCost);

        createHash(_seed);
    }

    /**
    * @dev Regenerates hash and deletes the last one for msg.sender.
    */
    function regenerateHash(
        uint _seed
    ) public payable {
        require(msg.value >= regenerateCost);
        require(userHashes[msg.sender].length > 0);

        delete userHashes[msg.sender][userHashes[msg.sender].length - 1];
        userHashes[msg.sender].length--;

        createHash(_seed);
    }

    /**
    * @dev Creates hash and pushes to hashes array.
    */
    function createHash(
        uint _seed
    ) private {
        address key = address(keccak256(abi.encodePacked(msg.sender, userHashes[msg.sender].length)));
        hashes[key] = Hash({
            owner: msg.sender,
            hash: keccak256(abi.encodePacked(_seed, msg.sender, msg.data, block.number)),
            challengePeriodStarted: false,
            challengePeriodEnd: 0,
            commitPeriodEnd: 0,
            revealPeriodEnd: 0,
            votesFor: 0,
            votesAgainst: 0,
            depositedForAuction: false,
            auctionStartOn: 0,
            auctionStartPrice: 0,
            auctionEndPrice: 0,
            auctionDuration: 0,
            inAuction: false
            });

        userHashes[msg.sender].push(key);
    }

    /**
    * @dev Starts challenge period for specific hash.
    */
    function startChallengePeriod(address _hashAddress) public {
        require(hashes[_hashAddress].owner == msg.sender);
        require(!hashes[_hashAddress].challengePeriodStarted);

        hashes[_hashAddress].challengePeriodStarted = true;
    }

    function challenge(
        address _hashAddress
    ) public payable {
        require(hashes[_hashAddress].challengePeriodStarted && now < hashes[_hashAddress].challengePeriodEnd);
        require(msg.value >= challengeCost);

        hashes[_hashAddress].commitPeriodEnd = now + commitDuration;
        hashes[_hashAddress].revealPeriodEnd = now + commitDuration + revealDuration;
    }


    function commitVote(
        address _hashAddress,
        bytes32 _secret
    ) public payable {
        require(now < hashes[_hashAddress].commitPeriodEnd);
        require(msg.value >= voteAmount);

        hashes[_hashAddress].vote[msg.sender].secretHash = _secret;
        hashes[_hashAddress].vote[msg.sender].amount = msg.value;
    }

    function revealVote(
        address _hashAddress,
        bool _voteOption,
        bytes32 _seed
    ) public {
        require(now > hashes[_hashAddress].commitPeriodEnd && now < hashes[_hashAddress].revealPeriodEnd);
        require(hashes[_hashAddress].vote[msg.sender].secretHash == keccak256(abi.encodePacked(_voteOption, _seed)));

        hashes[_hashAddress].vote[msg.sender].option = _voteOption;
        hashes[_hashAddress].vote[msg.sender].revealedOn = now;
        if (_voteOption) {
            hashes[_hashAddress].votesFor.add(hashes[_hashAddress].vote[msg.sender].amount);
        } else {
            hashes[_hashAddress].votesAgainst.add(hashes[_hashAddress].vote[msg.sender].amount);
        }
        msg.sender.transfer(hashes[_hashAddress].vote[msg.sender].amount);
    }

    function depositForAuction(
        address _hashAddress
    ) public {
        require((hashes[_hashAddress].revealPeriodEnd == 0 && hashes[_hashAddress].challengePeriodEnd < now) || (hashes[_hashAddress].revealPeriodEnd > now && isVotedFor(_hashAddress)));
        require(!hashes[_hashAddress].inAuction);

        auctionCutCollector.transfer(generateCost * auctionCut / 100);
        hashes[_hashAddress].depositedForAuction = true;
    }

    function startAuction(
        address _hashAddress,
        uint _auctionStartPrice,
        uint _auctionEndPrice,
        uint _auctionDuration
    ) public {
        require(hashes[_hashAddress].depositedForAuction);
        require(!hashes[_hashAddress].inAuction);
        require(_auctionDuration >= 5 minutes);

        hashes[_hashAddress].auctionStartOn = now;
        hashes[_hashAddress].auctionStartPrice = _auctionStartPrice;
        hashes[_hashAddress].auctionEndPrice = _auctionEndPrice;
        hashes[_hashAddress].auctionDuration = _auctionDuration;
        hashes[_hashAddress].inAuction = true;
    }

    function cancelFromAuction(
        address _hashAddress
    ) public {
        require(hashes[_hashAddress].inAuction);

        hashes[_hashAddress].inAuction = false;
    }

    function buyFromAuction(
        address _hashAddress,
        address _owner
    ) public payable {
        require(hashes[_hashAddress].inAuction);
        require(msg.value > calculatePrice(_hashAddress));

        for (uint i = 0; i < userHashes[_owner].length; i++) {
            if (userHashes[_owner][i] == _hashAddress) {
                transfer(_owner, msg.sender, _hashAddress);
                hashes[_hashAddress].owner.transfer(msg.value);
                hashes[_hashAddress].owner = msg.sender;
                hashes[_hashAddress].inAuction = false;
            }
        }
    }

    function calculatePrice(
        address _hashAddress
    ) public view returns (uint) {
        require(hashes[_hashAddress].inAuction);

        if (now >= hashes[_hashAddress].auctionDuration + hashes[_hashAddress].auctionStartOn) {
            return hashes[_hashAddress].auctionEndPrice;
        } else {
            int currentPriceChange = (int(hashes[_hashAddress].auctionEndPrice) - int(hashes[_hashAddress].auctionStartPrice)) * int(now - hashes[_hashAddress].auctionStartOn) / int(hashes[_hashAddress].auctionDuration);
            return uint(int(hashes[_hashAddress].auctionStartPrice) + currentPriceChange);
        }
    }

    function isVotedFor(
        address _hashAddress
    ) public view returns (bool) {
        require(hashes[_hashAddress].revealPeriodEnd > now);

        return hashes[_hashAddress].votesFor > hashes[_hashAddress].votesAgainst;
    }

    function transfer(
        address _from,
        address _to,
        address _hashAddress
    ) private {
        for (uint i = 0; i < userHashes[_from].length; i++) {
            if (userHashes[_from][i] == _hashAddress) {
                delete userHashes[_from][i];
                userHashes[_from].length--;
            }
        }

        userHashes[_to].push(_hashAddress);
    }

    function setChallengeDuration(
        uint _challengeDuration
    ) public onlyOwner {
        challengeDuration = _challengeDuration;
    }

    function setCommitDuration(
        uint _commitDuration
    ) public onlyOwner {
        commitDuration = _commitDuration;
    }

    function setRevealDuration(
        uint _revealDuration
    ) public onlyOwner {
        revealDuration = _revealDuration;
    }

    function setGenerateCost(
        uint _generateCost
    ) public onlyOwner {
        generateCost = _generateCost;
    }

    function setRegenerateCost(
        uint _regenerateCost
    ) public onlyOwner {
        regenerateCost = _regenerateCost;
    }

    function setChallengeCost(
        uint _generateCost
    ) public onlyOwner {
        generateCost = _generateCost;
    }

    function setAuctionCut(
        uint _auctionCut
    ) public onlyOwner {
        auctionCut = _auctionCut;
    }

    function setAuctionCutCollector(
        address _auctionCutCollector
    ) public onlyOwner {
        auctionCutCollector = _auctionCutCollector;
    }

    function changeOwner(
        address _owner
    ) public onlyOwner {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
