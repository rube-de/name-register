//SPDX-License-Identifier: Unlicense^
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./StringUtils.sol";
import "hardhat/console.sol";

contract NameRegister is Ownable {
  using StringUtils for *;


  struct Record {
    address owner;
    uint256 ttl;
  }

  mapping(string => Record) public Records;

  uint public feesCollected;  

  uint public immutable lockAmount;
  uint public immutable lockPeriod;
  uint public minCommitmentAge;
  uint public maxCommitmentAge;

  mapping(bytes32=>uint) public commitments;

  event NameRegistered(string name, address indexed owner, uint cost, uint expires);
  event NameRenewed(string name, uint cost, uint expires);

  constructor(uint _lockAmount, uint _lockPeriod, uint _minCommitmentAge, uint _maxCommitmentAge) {
      require(_maxCommitmentAge > _minCommitmentAge);
      lockAmount = _lockAmount;
      lockPeriod = _lockPeriod;
      minCommitmentAge = _minCommitmentAge;
      maxCommitmentAge = _maxCommitmentAge;
  }

  function nameTTL (string calldata name) public view returns (uint256) {
    return Records[name].ttl;
  }

  function isNameExpired (string calldata name) public view returns (bool) {
    return nameTTL(name) < block.timestamp;
  }

  function isNameAlreadyRegistered(string calldata name) public view returns (bool) {
    return Records[name].owner != address(0x0);
  }

  function rentPrice(string memory name) pure public returns(uint) {
      uint length = name.strlen();
      if (length == 1) {
        return 5 ether;
      } else if (length == 2) {
        return 4 ether;
      } else if (length == 3) {
        return 3 ether ;
      } else if (length == 4) {
        return 2 ether;
      } else {
        return 1 ether;
      }
  }

  function makeCommitment(string memory name, address owner, bytes32 secret) pure public returns(bytes32) {
      bytes32 label = keccak256(bytes(name));
      return keccak256(abi.encodePacked(label, owner, secret));
  }

  function commit(bytes32 commitment) public {
      require(commitments[commitment] + maxCommitmentAge < block.timestamp);
      commitments[commitment] = block.timestamp;
  }

  function register(string calldata name, address owner, bytes32 secret) external payable {
      bytes32 commitment = makeCommitment(name, owner, secret);
      uint cost = _consumeCommitment(name, commitment);

      
      uint expires = block.timestamp + lockPeriod;

      Records[name].owner = msg.sender;
      Records[name].ttl = expires;


      emit NameRegistered(name, owner, cost, expires);

      // Refund any extra payment
      if(msg.value > cost) {
          payable(msg.sender).transfer(msg.value - cost);
      }
      feesCollected = feesCollected + cost;
  }

  function renew(string calldata name) external payable {
      require(isNameAlreadyRegistered(name), "no owner - register first");
      require(!isNameExpired(name), "is expired - register first");
      uint expires = block.timestamp + lockPeriod;
      uint cost = rentPrice(name);
      require(msg.value >= cost);

      Records[name].ttl = expires;

      if(msg.value > cost) {
          payable(msg.sender).transfer(msg.value - cost);
      }

      feesCollected = feesCollected + cost;
      emit NameRenewed(name, cost, expires);
  }

  function setCommitmentAges(uint _minCommitmentAge, uint _maxCommitmentAge) public onlyOwner {
      minCommitmentAge = _minCommitmentAge;
      maxCommitmentAge = _maxCommitmentAge;
  }


  function _consumeCommitment(string calldata name, bytes32 commitment) internal returns (uint256) {
      // Require a valid commitment
      require(commitments[commitment] + minCommitmentAge <= block.timestamp);

      // If the commitment is too old, or the name is registered, stop
      require(commitments[commitment] + maxCommitmentAge > block.timestamp);
      require(!isNameAlreadyRegistered(name) || isNameExpired(name));

      delete(commitments[commitment]);

      uint cost = rentPrice(name);
      require(msg.value >= cost);

      return cost;
  }

  function withdrawUnlockedEther(string calldata name) public {
    Record memory record = Records[name];
    require(record.owner == msg.sender, "not owner of name");
    require(record.ttl < block.timestamp, "name not yet expired");
    delete(Records[name]);
    payable(msg.sender).transfer(lockAmount);
  }

  function withdraw() public onlyOwner {
      uint withdrawAmount = feesCollected;
      feesCollected = 0;
      payable(msg.sender).transfer(withdrawAmount);
  }
}