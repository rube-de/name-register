const { use, expect } = require("chai");
const { ethers } = require("hardhat");
const { solidity } = require("ethereum-waffle");

const getRandomValues = require('get-random-values'); 

use(solidity);

describe("Register", function () {
  let register;

  let owner, adr1, adr2, adr3, adr4;
  const lockAmount = ethers.utils.parseEther("1");
  const lockPeriod = 60*60*24*365; //1 year
  const minCommitmentAge = 60; // 1 minute
  const maxCommitmentAge = 60*60*24 // 24 hours

  before(async () => {
    [owner,adr1,adr2,adr3,adr4] = await ethers.getSigners();

    const Register = await ethers.getContractFactory("NameRegister");
    register = await Register.deploy(lockAmount, lockPeriod, minCommitmentAge, maxCommitmentAge);
    await register.deployed();
  });

  it("Should be deployed", async () => {
    expect(register.address).to.exist;
  });

  it("Should be able to register name", async () => {
    const name = "test";
    const random = new Uint8Array(32);
    getRandomValues(random);
    const salt = "0x" + Array.from(random).map(b => b.toString(16).padStart(2, "0")).join("");

    // Submit our commitment to the smart contract
    const commitment = await register.connect(adr1).makeCommitment(name, adr1.address, salt);
    const tx = await register.connect(adr1).commit(commitment);
    // Add 10% to account for price fluctuation; the difference is refunded.
    const price = (await register.connect(adr1).rentPrice(name)).mul(110).div(100);
    // Wait 60 seconds before registering
    await ethers.provider.send("evm_increaseTime", [minCommitmentAge]);
    await ethers.provider.send("evm_mine");
    // Submit our registration request
    await register.connect(adr1).register(name, adr1.address, salt, {value: price});
  });

  it("Should revert if min wait time isn't passed", async () => {
    const name = "test1";
    const random = new Uint8Array(32);
    getRandomValues(random);
    const salt = "0x" + Array.from(random).map(b => b.toString(16).padStart(2, "0")).join("");

    // Submit our commitment to the smart contract
    const commitment = await register.connect(adr1).makeCommitment(name, adr1.address, salt);
    const tx = await register.connect(adr1).commit(commitment);
    // Add 10% to account for price fluctuation; the difference is refunded.
    const price = (await register.connect(adr1).rentPrice(name)).mul(110).div(100);
    // Wait less than 60 seconds before registering
    await ethers.provider.send("evm_increaseTime", [50]);
    await ethers.provider.send("evm_mine");
    // Submit our registration request
    await expect(register.connect(adr1).register(name, adr1.address, salt, {value: price}))
      .to.be.reverted;
  });

  it("Should revert if not commitment was done", async () => {
    const name = "test2";
    const random = new Uint8Array(32);
    getRandomValues(random);
    const salt = "0x" + Array.from(random).map(b => b.toString(16).padStart(2, "0")).join("");

    // Submit our commitment to the smart contract
    const commitment = await register.connect(adr1).makeCommitment(name, adr1.address, salt);
    // Add 10% to account for price fluctuation; the difference is refunded.
    const price = (await register.connect(adr1).rentPrice(name)).mul(110).div(100);
    // Wait 60 seconds before registering
    await ethers.provider.send("evm_increaseTime", [minCommitmentAge]);
    await ethers.provider.send("evm_mine");
    // Submit our registration request
    await expect(register.connect(adr1).register(name, adr1.address, salt, {value: price}))
      .to.be.reverted; 

  });

  it("Should revert if owner in register isn't one of commitment", async () => {
    const name = "test3";
    const random = new Uint8Array(32);
    getRandomValues(random);
    const salt = "0x" + Array.from(random).map(b => b.toString(16).padStart(2, "0")).join("");

    // Submit our commitment to the smart contract
    const commitment = await register.connect(adr1).makeCommitment(name, adr1.address, salt);
    const tx = await register.connect(adr1).commit(commitment);
    // Add 10% to account for price fluctuation; the difference is refunded.
    const price = (await register.connect(adr1).rentPrice(name)).mul(110).div(100);
    // Wait 60 seconds before registering
    await ethers.provider.send("evm_increaseTime", [minCommitmentAge]);
    await ethers.provider.send("evm_mine");
    // Submit our registration request
    await expect(register.connect(adr2).register(name, adr2.address, salt, {value: price}))
      .to.be.reverted;
  });

  it("Should revert if try to withdraw if not yet expired", async () => {
    await expect(register.connect(adr1).withdrawUnlockedEther("test")).to.be.reverted;
  });

  it("Should revert if try to withdraw not owner", async () => {
    await expect(register.connect(adr2).withdrawUnlockedEther("test")).to.be.reverted;
  });

  it("Should witdhraw unlocked ", async () => {
    const balanceBefore = await ethers.provider.getBalance(adr1.address);
    await ethers.provider.send("evm_increaseTime", [lockPeriod]);
    await ethers.provider.send("evm_mine");
    const tx = await register.connect(adr1).withdrawUnlockedEther("test");
    const { effectiveGasPrice, cumulativeGasUsed} = await tx.wait();
    // get how much eth was paid for tx
    const gasPaid = effectiveGasPrice.mul(cumulativeGasUsed);
    const balanceAfter = await ethers.provider.getBalance(adr1.address);
    expect(balanceBefore.sub(gasPaid).add(lockAmount)).to.be.equals(balanceAfter);
  });

  it("Should  revert renew if expired", async () => {
    await expect(register.connect(adr2).renew("test")).to.be.reverted;
  });

  it("Should renew if not expired", async () => {
    const name = "test";
    const random = new Uint8Array(32);
    getRandomValues(random);
    const salt = "0x" + Array.from(random).map(b => b.toString(16).padStart(2, "0")).join("");

    // Submit our commitment to the smart contract
    const commitment = await register.connect(adr1).makeCommitment(name, adr1.address, salt);
    const tx = await register.connect(adr1).commit(commitment);
    // Add 10% to account for price fluctuation; the difference is refunded.
    const price = (await register.connect(adr1).rentPrice(name)).mul(110).div(100);
    // Wait 60 seconds before registering
    await ethers.provider.send("evm_increaseTime", [minCommitmentAge]);
    await ethers.provider.send("evm_mine");
    // Submit our registration request
    await register.connect(adr1).register(name, adr1.address, salt, {value: price});
    await register.connect(adr1).renew("test", {value: price});
    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    const testRecordRenew = await register.connect(adr1).Records("test");
    expect(ethers.BigNumber.from(block.timestamp).add(lockPeriod)).to.be.equals(testRecordRenew.ttl);



  })
});
