pragma solidity ^0.4.24;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

/**
 * @title HashAuction
 * @dev Math operations with safety checks that throw on error
 */
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
        require(_auctionCut < 100);
        require(_commitDuration > 5 minutes);
        require(_revealDuration > 5 minutes);
        require(_owner != 0x0);

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
    * @dev Generates awesome hash that's truly yours.
    * @param _seed Seed is a number used for generating random hash
    */
    function generateHash(
        uint _seed
    ) public payable {
        require(msg.value >= generateCost);

        createHash(_seed);
    }

    /**
    * @dev Regenerates hash and deletes the last one for msg.sender.
    * @param _seed Seed is a number used for regenerating random hash
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
    * @dev Creates and stores hash for msg.sender.
    * @param _seed Seed is a number used for generating random hash
    */
    function createHash(
        uint _seed
    ) private {
        address key = address(keccak256(abi.encodePacked(msg.sender, userHashes[msg.sender].length)));
        hashes[key] = Hash({
            owner: msg.sender,
            hash: generateRandomHash(_seed),
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
    * @dev Generates random hash
    * @param _seed Seed is a number used for generating random hash
    */
    function generateRandomHash(
        uint _seed
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_seed, msg.sender, msg.data, block.number));
    }

    /**
    * @dev Starts challenge period for specific hash.
    * @param _hashAddress is address of hash
    */
    function startChallengePeriod(address _hashAddress) public {
        require(hashes[_hashAddress].owner == msg.sender);
        require(!hashes[_hashAddress].challengePeriodStarted);

        hashes[_hashAddress].challengePeriodStarted = true;
        hashes[_hashAddress].challengePeriodEnd = now + challengeDuration;
    }

    /**
    * @dev Challenges a specific hash.
    * @param _hashAddress Address of hash
    */
    function challenge(
        address _hashAddress
    ) public payable {
        require(hashes[_hashAddress].challengePeriodStarted && now < hashes[_hashAddress].challengePeriodEnd);
        require(hashes[_hashAddress].commitPeriodEnd == 0);
        require(msg.value >= challengeCost);

        hashes[_hashAddress].commitPeriodEnd = now + commitDuration;
        hashes[_hashAddress].revealPeriodEnd = now + commitDuration + revealDuration;
    }

    /**
    * @dev Challenges a specific hash.
    * @param _hashAddress Address of hash
    * @param _secretHash Encrypted vote option with salt. sha3(voteOption, salt)
    */
    function commitVote(
        address _hashAddress,
        bytes32 _secretHash
    ) public payable {
        require(now < hashes[_hashAddress].commitPeriodEnd);
        require(msg.value >= voteAmount);

        hashes[_hashAddress].vote[msg.sender].secretHash = _secretHash;
        hashes[_hashAddress].vote[msg.sender].amount = msg.value;
    }

    /**
    * @dev Reveals previously committed vote
    * @param _hashAddress Address of hash
    * @param _voteOption Vote option voter previously voted with
    * @param _salt Salt with which user previously encrypted his vote option
    */
    function revealVote(
        address _hashAddress,
        bool _voteOption,
        bytes32 _salt
    ) public {
        require(now > hashes[_hashAddress].commitPeriodEnd && now < hashes[_hashAddress].revealPeriodEnd);
        require(hashes[_hashAddress].vote[msg.sender].revealedOn == 0);
        require(hashes[_hashAddress].vote[msg.sender].secretHash == keccak256(abi.encodePacked(_voteOption, _salt)));

        hashes[_hashAddress].vote[msg.sender].option = _voteOption;
        hashes[_hashAddress].vote[msg.sender].revealedOn = now;
        if (_voteOption) {
            hashes[_hashAddress].votesFor.add(hashes[_hashAddress].vote[msg.sender].amount);
        } else {
            hashes[_hashAddress].votesAgainst.add(hashes[_hashAddress].vote[msg.sender].amount);
        }
        msg.sender.transfer(hashes[_hashAddress].vote[msg.sender].amount);
    }

    /**
    * @dev Deposits a hash for auction. Callable only for hashes that passed challenge period successfully
    * @param _hashAddress Address of hash
    */
    function depositForAuction(
        address _hashAddress
    ) public {
        require((hashes[_hashAddress].revealPeriodEnd == 0 && hashes[_hashAddress].challengePeriodEnd < now) ||
            (hashes[_hashAddress].revealPeriodEnd > now && isVotedFor(_hashAddress)));
        require(!hashes[_hashAddress].inAuction);

        auctionCutCollector.transfer(generateCost * auctionCut / 100);
        hashes[_hashAddress].depositedForAuction = true;
    }

    /**
    * @dev Starts auction for specific hash
    * @param _hashAddress Address of hash
    * @param _auctionStartPrice Start price of hash
    * @param _auctionEndPrice End price of hash
    * @param _auctionDuration Duration of auction
    */

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

    /**
    * @dev Cancels auction for specific hash
    * @param _hashAddress Address of hash
    */
    function cancelFromAuction(
        address _hashAddress
    ) public {
        require(hashes[_hashAddress].inAuction);

        hashes[_hashAddress].inAuction = false;
    }

    /**
    * @dev Buys hash from auction
    * @param _owner Address of owner
    * @param _index Index of
    */

    function buyFromAuction(
        address _owner,
        uint _index
    ) public payable {
        address hashAddress = userHashes[_owner][_index];
        require(hashes[hashAddress].inAuction);
        require(msg.value > calculatePrice(userHashes[_owner][_index]));

        transfer(_owner, msg.sender, _index);
        hashes[hashAddress].owner.transfer(msg.value);
        hashes[hashAddress].owner = msg.sender;
        hashes[hashAddress].inAuction = false;
    }

    /**
    * @dev Calculates price of hash
    * @param _owner Address of owner
    */
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
        uint _index
    ) private {
        address hashAddress = userHashes[_from][_index];
        userHashes[_from][_index] = userHashes[_from][userHashes[_from].length - 1];
        userHashes[_from].length--;

        userHashes[_to].push(hashAddress);
    }

    function setAuctionCut(
        uint _auctionCut
    ) public onlyOwner {
        require(_auctionCut < 100);
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
