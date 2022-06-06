// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // deploy args
  const lockAmount = ethers.utils.parseEther("1");
  const lockPeriod = 60*60*24*365; //1 year
  const minCommitmentAge = 60; // 1 minute
  const maxCommitmentAge = 60*60*24 // 24 hours

  // We get the contract to deploy
  const Register = await ethers.getContractFactory("NameRegister");
  const register = await Register.deploy(lockAmount, lockPeriod, minCommitmentAge, maxCommitmentAge);
  await register.deployed();



  console.log("register deployed to:", register.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
