var Erebor = artifacts.require("./Erebor.sol");
var ERC20 = artifacts.require("./ERC20.sol");
var StandardToken = artifacts.require("./StandardToken.sol");
var RNT = artifacts.require("./RNT.sol");
var SafeMath = artifacts.require("./SafeMath.sol");
var ELEMInterface = artifacts.require("./ELEMInterface.sol");

module.exports = function(deployer) {
    deployer.deploy(SafeMath);
    deployer.link(SafeMath, [StandardToken, RNT, Erebor]);
    deployer.deploy(StandardToken);
    deployer.deploy(RNT).then(() => {
        let RNTAddr = RNT.address;
        let ELEMAddr = '';  // need to fill in an address
        return deployer.deploy(
            Erebor,
            '0xa82e7cfb30f103af78a1ad41f28bdb986073ff45b80db71f6f632271add7a32e',
            RNTAddr,
            ELEMAddr,
            {value: '10000000000000000'}).then(() => {
                let EreborAddr = Erebor.address;
                return RNT.at(RNTAddr).setMining(EreborAddr).then(() => {
                    return {RNTAddr, EreborAddr}
                })
            })
    }).then((result) => {
        console.dir(result);
    }).catch((err) => { console.trace(err); });
};
