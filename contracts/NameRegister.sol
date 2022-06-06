//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./StringUtils.sol";
import "hardhat/console.sol";

/// @title Name Register
/// @notice Lets you register and renew name records
contract NameRegister is Ownable {
  using StringUtils for *;


  struct Record {
    address owner;
    uint256 ttl;
  }
  /// @dev mapping for name -> Record
  /// @return owner The Record of the name
  mapping(string => Record) public Records;

  /// @notice the collected fees from the registiration fee, withdrawable for the owner
  uint public feesCollected;  

  uint public immutable lockAmount;
  uint public immutable lockPeriod;
  uint public immutable minCommitmentAge;
  uint public immutable maxCommitmentAge;

  /// @dev mapping of commitment -> timestamp
  /// @return timestamp timestamp of the commitment
  mapping(bytes32=>uint) public commitments;

  /// @notice Emitted when a name is registered
  /// @param name  The name which gets registered
  /// @param owner The owner of the name
  /// @param cost The fee paid for the name
  /// @param expires The expiry timestamp of the name
  event NameRegistered(string name, address indexed owner, uint cost, uint expires);
  /// @notice Emitted when a name is renewed
  /// @param name The name which gets renewed
  /// @param cost The fee paid fot the renewal
  /// @param expires The new expiry timestamp
  event NameRenewed(string name, uint cost, uint expires);

  /// @param _lockAmount The default locked ETH for a name
  /// @param _lockPeriod The default lock period of the name and the locked ETH
  /// @param _minCommitmentAge The minimum age the commitiment befor it can be consumed
  /// @param _maxCommitmentAge The maximum age the commitiment until it can be consumed
  constructor(uint _lockAmount, uint _lockPeriod, uint _minCommitmentAge, uint _maxCommitmentAge) {
      require(_maxCommitmentAge > _minCommitmentAge);
      lockAmount = _lockAmount;
      lockPeriod = _lockPeriod;
      minCommitmentAge = _minCommitmentAge;
      maxCommitmentAge = _maxCommitmentAge;
  }

  /// @return ttl Returns the time to live of a name
  function nameTTL (string calldata name) public view returns (uint256) {
    return Records[name].ttl;
  }

  /// @return bool Returns if a name is expired
  function isNameExpired (string calldata name) public view returns (bool) {
    return nameTTL(name) < block.timestamp;
  }

  /// @return bool Returns if a name is already registered
  function isNameAlreadyRegistered(string calldata name) public view returns (bool) {
    return Records[name].owner != address(0x0);
  }
  
  /// @notice The price depends on the length of the name
  /// @return price Returns the fee to be paid for the name registering and renewal
  function rentPrice(string calldata name) pure public returns(uint) {
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

  /// @notice generates a commitment to register a name for an owner
  /// @param name The name to be registered
  /// @param owner The owner address of the name
  /// @param secret The secret to protect the commitment
  /// @return commitiment Returns the generated commitment
  function makeCommitment(string calldata name, address owner, bytes32 secret) pure public returns(bytes32) {
      bytes32 label = keccak256(bytes(name));
      return keccak256(abi.encodePacked(label, owner, secret));
  }

  /// @notice Commits the commitiment
  /// @param commitment The commitiment that was generated throught makeCommitment
  function commit(bytes32 commitment) public {
      require(commitments[commitment] + maxCommitmentAge < block.timestamp);
      commitments[commitment] = block.timestamp;
  }

  /// @notice Registers a name after a commitiment was committed and the minCommitimentAge passed
  /// @param name The name to be registered
  /// @param owner The owner address of the name
  /// @param secret The secret which was used for the commitment
  function register(string calldata name, address owner, bytes32 secret) external payable {
      bytes32 commitment = makeCommitment(name, owner, secret);
      uint cost = _consumeCommitment(name, commitment);
      uint expires = block.timestamp + lockPeriod;

      Records[name].owner = msg.sender;
      Records[name].ttl = expires;
      feesCollected = feesCollected + cost;

      // Refund any extra payment
      if(msg.value > cost) {
          payable(msg.sender).transfer(msg.value - cost);
      }
      emit NameRegistered(name, owner, cost, expires);
  }

  /// @notice Renews a given name if fee is paid - also extends expiry / lock period
  /// @param name The name to be renewed
  function renew(string calldata name) external payable {
      require(isNameAlreadyRegistered(name), "no owner - register first");
      require(!isNameExpired(name), "is expired - register first");
      uint expires = block.timestamp + lockPeriod;
      uint cost = rentPrice(name);
      require(msg.value >= cost);

      Records[name].ttl = expires;
      feesCollected = feesCollected + cost;
      // Refund any extra payment
      if(msg.value > cost) {
          payable(msg.sender).transfer(msg.value - cost);
      }
      emit NameRenewed(name, cost, expires);
  }

  /// @notice Consumes a commitment for name and checks if it is valid
  /// @param name The name to be registered
  /// @param commitment The commitment to the name
  /// @return fee The fee to be paid for the registration
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

  /// @notice If a name expires the owner withdraw the locked ETH
  /// @param name The name that expired
  function withdrawUnlockedEther(string calldata name) external {
    Record memory record = Records[name];
    require(record.owner == msg.sender, "not owner of name");
    require(record.ttl < block.timestamp, "name not yet expired");
    delete(Records[name]);
    payable(msg.sender).transfer(lockAmount);
  }

  /// @notice Withdraws the fees collected
  function withdraw() public onlyOwner {
      uint withdrawAmount = feesCollected;
      feesCollected = 0;
      payable(msg.sender).transfer(withdrawAmount);
  }
}