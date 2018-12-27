var BattleShip = artifacts.require("./BattleShip.sol");
var ERC20 = artifacts.require("./ERC20.sol");

module.exports = function(deployer) {
  deployer.deploy(BattleShip, '0xa82e7cfb30f103af78a1ad41f28bdb986073ff45b80db71f6f632271add7a32e', {value: '10000000000000000'});
};
