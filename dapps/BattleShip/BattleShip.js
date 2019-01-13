'use strict';

const fs   = require('fs');
const path = require('path');
const ethUtils = require('ethereumjs-utils');
const biapi = require('bladeiron_api');
const MerkleTree = require('merkle_tree');
const level = require('level');

// 11BE BladeIron Client API
const BladeIronClient = require('bladeiron_api');

const fields = 
[
//   {name: 'nonce', length: 32, allowLess: true, default: new Buffer([]) },
//   {name: 'validatorAddress', length: 20, allowZero: false, default: new Buffer([]) },
   {name: 'originAddress', length: 20, allowZero: false, default: new Buffer([]) },
//   {name: 'timestamp', length: 32, allowLess: true, default: new Buffer([]) },
   {name: 'payload', length: 32, allowLess: false, default: new Buffer([]) },
   {name: 'v', allowZero: true, default: new Buffer([0x1c]) },
   {name: 'r', allowZero: true, length: 32, default: new Buffer([]) },
   {name: 's', allowZero: true, length: 32, default: new Buffer([]) }
];

const pubKeyToAddress = (sigObj) =>
{
        let signer = '0x' +
              ethUtils.bufferToHex(
                ethUtils.sha3(
                  ethUtils.bufferToHex(
                        ethUtils.ecrecover(sigObj.chkhash, sigObj.v, sigObj.r, sigObj.s, sigObj.netID)
                  )
                )
              ).slice(26);

        console.log(`signer address: ${signer}`);

        return signer === ethUtils.bufferToHex(sigObj.originAddress);
}

class BattleShip extends BladeIronClient {
	constructor(rpcport, rpchost, options)
        {
		super(rpcport, rpchost, options);
		this.ctrName = 'BattleShip';
		this.secretBank = ['The','Times','03','Jan','2009','Chancellor','on','brink','of','second','bailout','for','banks'];
		this.target = '0x0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff';
		this.address = this.configs.account;
		this.gameStarted = false;
		this.initHeight  = 0;
		this.results = {};
		this.blockBest = {};
		this.bestANS = null;
		this.gameANS = {};
                this.gamePeriod;
		this.db = level(this.configs.database);
                this.leaves = [];
		this.winRecords = {};

		this.probe = () => 
		{
			let p = ['setup', 'board', 'initHeight', 'period_all', 'validator'].map((i) => { return this.call(this.ctrName)(i)() });

			return Promise.all(p).then((plist) => {
				console.dir(plist);
				this.gameStarted = plist[0];

				if (this.gameStarted) {
					this.board = plist[1];
					this.initHeight = plist[2];
					this.gamePeriod = plist[3];
					this.validator = plist[4];
                        		this.channelName = ethUtils.bufferToHex(ethUtils.sha256(this.board));

					if (typeof(this.results[this.initHeight]) === 'undefined') this.results[this.initHeight] = [];
					if (
					     this.userWallet === this.validator 
					  && typeof(this.winRecords[this.initHeight]) === 'undefined'
					) { this.winRecords[this.initHeight] = {}; }
				}

				return this.gameStarted;
			})
			.catch((err) => { console.trace(err);})
		}	

		this.testOutcome = (raw, blockNo) => 
		{
			let secret = ethUtils.bufferToHex(ethUtils.sha256(raw));
			return this.call(this.ctrName)('testOutcome')(secret, blockNo).then((r) => { return [...r, secret]});
		} 

		this.register = (scorehash) => 
		{
			//let msgSHA256Buffer = Buffer.from(secret.slice(2), 'hex');
			let fee = '10000000000000000';
			return this.client.call('ethNetStatus').then((rc) => {
				if (rc.blockHeight <= this.initHeight + 7) {
					return this.sendTk(this.ctrName)('challenge')(scorehash)(fee)
						   .then((qid) => {
							console.log(`DEBUG: QID = ${qid}`);
							return this.getReceipts(qid).then((rc) => {
								let rx = rc[0];
		
								if (rx.status !== '0x1') throw "failed to join the round";
								this.bestANS['submitted'] = rx.blockNumber;
								this.gameANS[this.initHeight] = { ...this.bestANS, tickets: {} };
								
								return rx;
							});
						})
						.catch((err) => { console.log(err); throw err; })
				}
			})

		}

		this.checkMerkle = (stats) => 
		{
			return this.call(this.ctrName)('merkleRoot')().then((mr) => {
				if (mr !== '0x0') {
					// double check all submitted winning tickets are included
					// preparing data structure to call withdraw, if any
				}
			})
		}

		this.calcTicket = () => 
		{
			if ( stats.blockHeight <= this.initHeight + 8 ) {
				return Promise.resolve(false);
			} else if (
			 	stats.blockHeight > this.initHeight + 8 
			     && Object.keys(this.gameANS[this.initHeight].tickets).length != 0
			){
				return Promise.resolve(true);
			} else {
				return this.call(this.ctrName)('getBlockhash')(Number(this.initHeight) + 8).then( (blockhash) => {
					// check how many tickets earned
					let initials = this.toBigNumber(this.toHex(this.gameANS[this.initHeight].score.substr(2,7)));
					let total = 1;
		
					if (initials.eq(0)) total = 5;
					if (initials.lt(16)) total = 4;
					if (initials.lt(256)) total = 3;
					if (initials.lt(4096)) total = 2;
		
					for (let i = 1; i <= total; i++) {
						let packed = this.abi.encodeParameters(
						[
							'bytes32',
							'bytes32',
							'uint'
						],
						[
							this.gameANS[this.initHeight].score,
							blockhash,
							Number(i)
						])
		
						// calculating tickets
						this.gameANS[this.initHeight].tickets[i] = ethUtils.bufferToHex(ethUtils.keccak256(packed));
					}
					
					return true;
				})
			}
		}

		this.newDraws = (stats) => 
		{
			this.calcTickets().then((rc) => {
				if (!rc) return false;
				this.call(this.ctrName)('winningNumber')(stats.blockHeight).then((raffle) => {
					Object.values(this.gameANS[this.initHeight].tickets).map((ticket) => {
						if (raffle.substr(64) === ticket.substr(64)) {
							let data = this.abi.encodeParameters(
							[
								'bytes32',
								'string',
								'uint',
								'uint',
								'bytes32
							],
							[
								this.bestANS.secret,
								this.bestANS.slots.map((s) => { return s ? 1 : 0 }).join(''),
								this.bestANS.blockNo,
								stats.blockHeight,
								ticket
							])

							let tickethash = ethUtils.hashPersonalMessage(Buffer.from(data));
							this.client.call('unlockAndSign', [this.userWallet, tickethash]).then((signature) => 
							{
								let m = {};
								let params = { originAddress: this.userWallet, payload: ethUtils.bufferToHex(tickethash) };
                        					ethUtils.defineProperties(m, fields, {...params, ...signature});
								this.ipfs_pubsub_publish(this.channelName, m.serialize());
							})
						}
					})
				})
			})
		}
	
		this.trial = (stats) => 
		{
			if (!this.gameStarted) return;
			if (stats.blockHeight < this.initHeight + 5) return;
			if (typeof(this.setAtBlock) === 'undefined') this.setAtBlock = stats.blockHeight;
			if ( stats.blockHeight == this.initHeight + 8 
			  || ( stats.blockHeight >= this.initHeight + 6 && typeof(this.setAtBlock) !== 'undefined' && stats.blockHeight >= this.setAtBlock + 1) 
			){
				this.stopTrial();

				if (Object.values(this.blockBest).length > 0) {
					this.bestANS = Object.values(this.blockBest).reduce((a,c) => 
					{
						if(this.byte32ToBigNumber(c.score).lte(this.byte32ToBigNumber(a.score))) {
							return c;
						} else {
							return a;
						}
					})

					console.log(`Best Answer:`); console.dir(this.bestANS);
					let scorehash = ethUtils.bufferToHex(ethUtils.keccak256(this.bestANS.score));

					return this.register(scorehash)
						   .then((tx) => 
						   {
							console.dir(tx);
							if (tx.status === '0x1') {
								this.client.subscribe('ethstats');
								this.client.on('ethstats', this.newDraws);
							}
						   })
				} else {
					return;
				}
			}

			console.log('New Stats'); console.dir(stats);

			let blockNo = stats.blockHeight - 1; console.log(blockNo);
			let localANS = []; let best; 
			let trialNonce = '0x' + parseInt(Math.random() * 1000, 16); 
			this.secretBank.map((s,idx) => 
			{
				s = s + trialNonce;
				this.testOutcome(s, blockNo).then((results) => 
				{
					let myboard = results[0]; 
					let slots = results[1]; 
					let secret = results[2];

					let score = [ ...myboard ];
	
					for (let i = 0; i <= 31; i ++) {
						if (!slots[i]) {
							score[2+i*2] = this.board.charAt(2+i*2);
							score[2+i*2+1] = this.board.charAt(2+i*2+1);
						}
					}
	
					localANS.push({myboard, score: score.join(''), secret, blockNo, slots, raw: s});
					//console.dir({score: score.join(''), secret, blockNo, slots});
					if (idx === this.secretBank.length - 1) {
						console.log("Batch " + blockNo + " done, calculating best answer ...");
						best = localANS.reduce((a,c) => 
						{
							if(this.byte32ToBigNumber(c.score).lte(this.byte32ToBigNumber(a.score))) {
								return c;
							} else {
								return a;
							}
						});
						this.blockBest[blockNo] = best;
					}
				})
			})

		}

		this.stopTrial = () => 
		{
			this.client.unsubscribe('ethstats');
			this.client.off('ethstats');
			console.log('Trial stopped !!!');
		}

		this.startTrial = (tryMore = 1000) => 
		{
                        if (tryMore > 0) { 
				if (tryMore > 2000) tryMore = 2000;
				this.moreSecret(tryMore); 
			};

			this.probe().then((started) => 
			{
				if(started) {
					console.log('Game started !!!');
					this.client.subscribe('ethstats');
					this.client.on('ethstats', this.trial);
				} else {
					console.log('Game has not yet been set ...');
				}
			})
		}

                this.moreSecret = (sizeOfSecrets) =>
                {
                        for (var i = 0; i<sizeOfSecrets; i++) { this.secretBank.push(String(Math.random())); }
                }

		this.handleValidate = (msgObj) => 
		{
			let address;
			let data = {};
			let rlpx = Buffer.from(msgObj.data);

			try {
				ethUtils.defineProperties(data, fields, rlpx); // decode
				address = ethUtils.bufferToHex(data.originAddress);
				if ( this.winRecords[address] > 10) {
					throw `address ${address} exceeds round limit ... ignored`;
				}
			} catch(err) {
				console.trace(err);
				return;
			}

			return this.call(this.ctrName)('getPlayerInfo')(address).then((results) => 
			{
				let since = results[0];
				let scoreHash = results[2]; // max possbile nonce by root-chain purchase records

				if (scoreHash === '0x0' || since < this.initHeight) {
					console.log(`DEBUG: Address ${address} did not play`)
					return; // discard
				}
	
				if ( !(v in data) || !(r in data) || !(s in data) ) return;
	
				let sigout = {v: ethUtils.bufferToInt(data.v), r: data.r, s: data.s};
	
				// signature is signed against payload
				let chkhash = Buffer.from(data.payload.slice(2), 'hex'); // Buffer
				sigout = { originAddress: address, ...sigout, chkhash, netID: this.configs.networkID };
				
				// verify signature before checking nonce of the signed address
				if (pubkeyToAddress(sigout)) {
					this.leaves.push(data.payload);
					// store file on local pool for IPFS publish
				}
	    		})
			.catch((err) => { console.trace(err); return; });


		}

                // below are several functions for state channel, the 'v_' ones are for validator
                this.subscribeChannel = (role) =>
                {
			// validator handler
			let handler;
			if (role === 'validator') {
				handler = this.handleValidate
			} else if (role === 'player') {
				// regular user *only* need to monitor for stop block submission message
				handler = this.handleState
			}

                        return this.ipfs_pubsub_subscribe(this.channelName)(handler);
                };

                this.unsubscribeChannel = () =>
                {
                        this.ipfs_pubsub_unsubscribe(this.channelName).then(()=>{
                                this.channelName = '';
                        })
                };

                this.v_announce = () => 
                {
                        this.ipfs_pubsub_publish(this.channelName, Buffer.from('Stop submiting scores') ).then(() => {
                                this.v_uploadMerkleTree(this.leaves);
                        }); 
                        // Perhaps user sign-in should be entirely off-chain, i.e., no playerDB in contract. 
                        // 1. It's possible that user has registered on-chain (added to playerDB) 
                        //    and somehow failed to submit here. Perhaps user data entirely off-chain?
                        // 2. hard to make sure this annoucement and generation/submision of Merkle Tree
                        //    is on time
                };

                this.merkleTree = new MerkleTree();
                this.v_makeMerkleTreeAndUploadRoot = (leaves) => {
                        merkleTree.addLeaves(leaves); 
                        merkleTree.makeTree();
                        merkleRoot = ethUtils.bufferToHex(merkleTree.getMerkleRoot());
	                return this.call(this.ctrName)('submitMerkleRoot')(merkleRoot, 0);
                };

                this.validateMerkleProof = (targetLeaf) => {
                        if (this.merkleTree.isReady) {
                                let txIdx = this.merkleTree.leaves.findIndex(x=> Buffer.compare(x, targetLeaf)==0);
                                if (txIdx == -1) {
                                        return false;
                                };
                        };
                        let proofArr = merkleTree.getProof(txIdx, true);
                        let proof = proofArr[1].map((x) => {return ethUtils.bufferToHex(x);});
                        let isLeft = proofArr[0];
                        targetLeaf = ethUtils.bufferToHex(merkleTree.getLeaf(txIdx));
                        let merkleRoot = ethUtils.bufferToHex(merkleTree.getMerkleRoot());
                        return this.call('MerkleTreeValidator')('validate')(proof, isLeft, targetLeaf, merkleRoot).then((tf) => { return tf;});
                };

                this.submitMerkleRoot = (id) =>  // id : either 0 or 1
                {
                        merkleRoot = this.makeMerkleTree();  // how to obtain leaves?
			return this.call(this.ctrName)('submitMerkleRoot')(merkleRoot, id);
                };
	}
}

module.exports = BattleShip;
