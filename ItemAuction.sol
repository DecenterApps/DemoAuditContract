pragma solidity ^0.4.24;

import './SafeMath.sol';

contract ItemAuction {
    using SafeMath for uint;
    
    struct Item {
        bool exists;
        bytes32 hash;
        string name;
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

    uint challengeDuration = 1000;
    uint commitDuration = 1000;
    uint revealDuration = 1000;
    uint depositAmount = 0.05 ether;
    uint voteAmount = 0.02 ether;
    uint auctionCut;
    address auctionCutCollector;
    mapping (address => address[]) public userItems;
    mapping (address => Item) public items;

    constructor(address _auctionCutCollector, uint _auctionCut) public {
        auctionCutCollector = _auctionCutCollector;
        auctionCut = _auctionCut;
    }

    function generateItem(uint _seed, string _name) public payable {
        require(msg.value >= depositAmount);
        
        if (msg.value > depositAmount) {
            msg.sender.transfer(msg.value.sub(depositAmount));
        }

        createItem(_seed, _name);
    }
    
    function regenarateItem(uint _seed, string _name) public {
        require(userItems[msg.sender].length > 0);
        
        delete userItems[msg.sender][userItems[msg.sender].length - 1];
        userItems[msg.sender].length--;
        
        createItem(_seed, _name);
    }
    
    function createItem(uint _seed, string _name) private {
        address key = address(keccak256(abi.encodePacked(msg.sender, userItems[msg.sender].length)));
        items[key] = Item({
            exists: true,
            hash: keccak256(abi.encodePacked(_seed, msg.sender, msg.data, block.number)),
            name: _name,
            challengePeriodEnd: now + challengeDuration,
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

        userItems[msg.sender].push(key);
    }
    
    function challenge(address _itemAddress) public {
        require(items[_itemAddress].exists && now < items[_itemAddress].challengePeriodEnd);
        
        items[_itemAddress].commitPeriodEnd = now + commitDuration;
        items[_itemAddress].revealPeriodEnd = now + commitDuration + revealDuration;
    }
    
    function commitVote(address _itemAddress, bytes32 _secret) public payable {
        require(now < items[_itemAddress].commitPeriodEnd);
        require(msg.value >= voteAmount);
        
        if (msg.value > voteAmount) {
            msg.sender.transfer(msg.value.sub(voteAmount));
        }
        
        items[_itemAddress].vote[msg.sender].secretHash = _secret;
    }
    
    function revealVote(address _itemAddress, bool _voteOption, bytes32 _seed) public {
        require(now > items[_itemAddress].commitPeriodEnd && now < items[_itemAddress].revealPeriodEnd);
        require(items[_itemAddress].vote[msg.sender].secretHash == keccak256(abi.encodePacked(_voteOption, _seed)));
        
        items[_itemAddress].vote[msg.sender].option = _voteOption;
        items[_itemAddress].vote[msg.sender].revealedOn = now;
        if (_voteOption) {
            items[_itemAddress].votesFor.add(voteAmount);
        } else {
            items[_itemAddress].votesAgainst.add(voteAmount);
        }
        msg.sender.transfer(voteAmount);
    }
    
    function depositForAuction(address _itemAddress) public {
        require((items[_itemAddress].commitPeriodEnd == 0 && items[_itemAddress].challengePeriodEnd < now) || (items[_itemAddress].commitPeriodEnd > now && isVotedFor(_itemAddress)));
        require(!items[_itemAddress].inAuction);
        
        auctionCutCollector.transfer(depositAmount * auctionCut / 100);
        items[_itemAddress].depositedForAuction = true;
    }
    
    function startAuction(address _itemAddress, uint _auctionStartPrice, uint _auctionEndPrice, uint _auctionDuration) public {
        require(items[_itemAddress].depositedForAuction);
        require(!items[_itemAddress].inAuction);
        require(_auctionDuration >= 5 minutes);
        
        items[_itemAddress].auctionStartOn = now;
        items[_itemAddress].auctionStartPrice = _auctionStartPrice;
        items[_itemAddress].auctionEndPrice = _auctionEndPrice;
        items[_itemAddress].auctionDuration = _auctionDuration;
        items[_itemAddress].inAuction = true;
    }
    
    function buyFromAuction(address _itemAddress, address owner) public payable {
        require(items[_itemAddress].inAuction);
        require(msg.value > calculatePrice(_itemAddress));
        
        for (uint i = 0; i < userItems[owner].length; i++) {
            if (userItems[owner][i] == _itemAddress) {
                transfer(owner, msg.sender, _itemAddress);        
                items[_itemAddress].inAuction = false;
            }
        }
    }
    
    function cancelFromAuction(address _itemAddress) public {
        require(items[_itemAddress].inAuction);
        
        items[_itemAddress].inAuction = false;
    }
    
    function calculatePrice(address _itemAddress ) public view returns (uint) {
        require(items[_itemAddress].inAuction);
        
        if (now >= items[_itemAddress].auctionDuration + items[_itemAddress].auctionStartOn) {
            return items[_itemAddress].auctionEndPrice;
        } else {
            int currentPriceChange = (int(items[_itemAddress].auctionEndPrice) - int(items[_itemAddress].auctionStartPrice)) * int(now - items[_itemAddress].auctionStartOn) / int(items[_itemAddress].auctionDuration);
            return uint(int(items[_itemAddress].auctionStartPrice) + currentPriceChange);
        }
    }
    
    function isVotedFor(address _itemAddress) public view returns (bool) {
        require(items[_itemAddress].revealPeriodEnd > now);
        
        return items[_itemAddress].votesFor > items[_itemAddress].votesAgainst;
    }
    
    function transfer(address _from, address _to, address _itemAddress) private {
        for (uint i = 0; i < userItems[_from].length; i++) {
            if (userItems[_from][i] == _itemAddress) {
                delete userItems[_from][i];
                userItems[_from].length--;
            }
        }
        
        userItems[_to].push(_itemAddress);
    }
}
