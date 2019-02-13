var Erebor = artifacts.require("Erebor");
var ERC20 = artifacts.require("ERC20");
var StandardToken = artifacts.require("StandardToken");
var RNT = artifacts.require("RNT");
var SafeMath = artifacts.require("SafeMath");
var MemberShip = artifacts.require("MemberShip");


module.exports = function(deployer) {
    deployer.deploy(SafeMath);
    deployer.link(SafeMath, [StandardToken, RNT, Erebor]);
    deployer.deploy(StandardToken);
    deployer.link(StandardToken, RNT);
    let ELEMAddr = '0x5c0C5B0E0f93D7e15C67E76153111cEAC6d17AAc';
    deployer.deploy(MemberShip, ELEMAddr);
    deployer.deploy(RNT).then((iRNT) => {
        let RNTAddr = RNT.address;
        let memberContractAddr = MemberShip.address;
        return deployer.deploy(
            Erebor,
            '0xa82e7cfb30f103af78a1ad41f28bdb986073ff45b80db71f6f632271add7a32e',
            RNTAddr,
            ELEMAddr,
            memberContractAddr,
            {value: '10000000000000000'}).then(() => {
                let EreborAddr = Erebor.address;
                return iRNT.setMining(EreborAddr).then(() => {
                    return {RNTAddr, EreborAddr}
                })
            })
    }).then((result) => {
        console.dir(result);
    }).catch((err) => { console.trace(err); });
};
