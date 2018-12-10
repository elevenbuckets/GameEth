var Gameths = artifacts.require("./Gameths.sol");
var Randoms = artifacts.require("./random.sol");

module.exports = function(deployer) {
  deployer.deploy(Gameths);
  deployer.deploy(Randoms);
};
