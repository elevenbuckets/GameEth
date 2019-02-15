// const fs = require("fs");
var Web3 = require('web3');
var Erebor = artifacts.require("Erebor");
var ERC20 = artifacts.require("ERC20");
var StandardToken = artifacts.require("StandardToken");
var RNT = artifacts.require("RNT");
var SafeMath = artifacts.require("SafeMath");
var MemberShip = artifacts.require("MemberShip");
// var iELEM = artifacts.require("iELEM");
// Elemmire.json from deployed contract; "dELEM" is deployed ELEM
// console.log(process.cwd());
// fs.copyFileSync("../Elemmire.json", "../build/contracts/Elemmire.json");
const iELEM = require("../Elemmire.json");  
const w3 = new Web3();  // this is web3 0.19
// w3.setProvider(new Web3.providers.HttpProvider('http://172.17.0.2:8545'));  // for docker
w3.setProvider(new Web3.providers.HttpProvider('http://127.0.0.1:8545'));
const dELEM = w3.eth.contract(iELEM.abi).at(iELEM.networks[4].address);

module.exports = function(deployer) {
    deployer.deploy(SafeMath);
    deployer.link(SafeMath, [StandardToken, RNT, Erebor]);
    deployer.deploy(StandardToken);
    deployer.link(StandardToken, RNT);
    let ELEMAddr = '0x6d6327c5d56E1C2b848bca19ef55E05aDc2997f2';
    deployer.deploy(MemberShip, ELEMAddr).then( (iMemberShip) => {
        return dELEM.setMining(MemberShip.address, 0, {from: w3.eth.accounts[0]}, (err, r) => {
            if (err) { console.trace(err); throw "bad" };
            return iMemberShip.allocateCoreManagersNFT();
        })
    });
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
                dELEM.setMining(EreborAddr, 1, {from: w3.eth.accounts[0]}, (err,r) => {
                    if (err) { console.trace(err); throw "bad2" };
                    console.log(`setMining for EreborAddr`)
                })
                return iRNT.setMining(EreborAddr).then(() => {
                    return {RNTAddr, EreborAddr}
                })
            })
    }).then((result) => {
        console.dir(result);
    }).catch((err) => { console.trace(err); });
};
