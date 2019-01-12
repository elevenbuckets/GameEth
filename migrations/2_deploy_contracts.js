var BattleShip = artifacts.require("./BattleShip.sol");
var ERC20 = artifacts.require("./ERC20.sol");
var StandardToken = artifacts.require("./StandardToken.sol");
var RNT = artifacts.require("./RNT.sol");
var SafeMath = artifacts.require("./SafeMath.sol");

module.exports = function(deployer) {
  deployer.deploy(SafeMath);
  deployer.deploy(StandardToken);
  deployer.link(StandardToken, SafeMath);
  deployer.deploy(RNT).then(() => {
  	deployer.link(RNT, SafeMath);
	let RNTAddr = RNT.address; 
  	return deployer.deploy(BattleShip, '0xa82e7cfb30f103af78a1ad41f28bdb986073ff45b80db71f6f632271add7a32e', {value: '10000000000000000'}).then(() => {
  		deployer.link(BattleShip, SafeMath);
		let BSAddr = BattleShip.address;
		return RNT.at(RNTAddr).setMining(BSAddr).then(() => {
			return {RNTAddr, BSAddr}
		})
	})
  })
  .then((result) => {
	console.dir(result);
  })
  .catch((err) => { console.trace(err); });
};
