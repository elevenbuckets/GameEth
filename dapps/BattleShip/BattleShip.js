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
   {name: 'nonce', length: 32, allowLess: true, default: new Buffer([]) },
   {name: 'validatorAddress', length: 20, allowZero: false, default: new Buffer([]) },
   {name: 'originAddress', length: 20, allowZero: false, default: new Buffer([]) },
   {name: 'timestamp', length: 32, allowLess: true, default: new Buffer([]) },
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
				}

				return this.gameStarted;
			});
		}	

		this.testOutcome = (raw, blockNo) => 
		{
			let secret = ethUtils.bufferToHex(ethUtils.sha256(raw));
			return this.call(this.ctrName)('testOutcome')(secret, blockNo).then((r) => { return [...r, secret]});
		} 

		this.register = () => 
		{
			//let msgSHA256Buffer = Buffer.from(secret.slice(2), 'hex');
			let fee = '10000000000000000';
			return this.client.call('ethNetStatus').then((rc) => {
				if (rc.blockHeight <= this.initHeight + 7) {
					return this.sendTk(this.ctrName)('challenge')()(fee);
						   .then((qid) => {
							console.log(`DEBUG: QID = ${qid}`);
							return this.getReceipts(qid).then((rc) => {
								let rx = rc[0];
		
								if (rx.status !== '0x1') throw "failed to join the round";
								
								return rx;
							});
						})
						.catch((err) => { console.log(err); throw err; })
				}
			})

		}
/*
		this.winnerTakes = (stats) => 
		{
			if (stats.blockHeight <= this.initHeight + this.gamePeriod) return;
			this.stopTrial();

			return this.call(this.ctrName)('winner')().then((winner) => {
				if (winner === this.address) {
					return this.sendTk(this.ctrName)('withdraw')()()
						   .then((qid) => {
							this.gameStarted = false; 
							return this.getReceipts(qid).then((rc) => {
								console.dir(rc[0]);
						   	})
						   });
				} else {
					console.log(`Yeah Right...`);
					this.gameStarted = false; 
					return;
				}
			})
		}

		this.submitAnswer = (stats) => 
		{
			if (this.gameANS[this.initHeight].secret !== this.bestANS.secret) {
				console.log("secret altered after registration... Abort!");
				return this.stopTrial();
			} else if (stats.blockHeight < Number(this.gameANS[this.initHeight].submitted) + 5) {
				console.log(`Still waiting block number >= ${Number(this.gameANS[this.initHeight].submitted) + 5} ...`);
				return;
			} else if (stats.blockHeight > this.initHeight + this.gamePeriod) {
				console.log(`Game round ${this.initHeight} is now ended`);
				this.gameStarted = false;
				return this.stopTrial();
			}

			this.stopTrial();

			return this.sendTk(this.ctrName)('revealSecret')(this.gameANS[this.initHeight].secret, this.bestANS.score, this.bestANS.slots, this.bestANS.blockNo)()
				.then((qid) => {
					return this.getReceipts(qid).then((rc) => {
						console.dir(rc[0]);
						this.client.subscribe('ethstats');
						this.client.on('ethstats', this.winnerTakes);
					})
				})
		}
*/

		this.checkMerkle = (stats) => {
			return this.call(this.ctrName)('merkleRoot')().then((mr) => {
				// submit another tx to reveal secret
				// stopTrial and start watching for the end block of the game
			})
		}
	
		this.trial = (stats) => 
		{
			if (!this.gameStarted) return;
			if (stats.blockHeight < this.initHeight + 5) return;
			if (typeof(this.setAtBlock) === 'undefined') this.setAtBlock = stats.blockHeight;
			if ( stats.blockHeight == this.initHeight + 8 
			  || ( stats.blockHeight >= this.initHeight + 6 && typeof(this.setAtBlock) !== 'undefined' && stats.blockHeight >= this.setAtBlock + 1) ) 
			{
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
					return this.submitChannel(ethUtils.keccak256(this.bestANS.score))
						   .then((rlpx) => {
							this.client.subscribe('ethstats');
							this.client.on('ethstats', this.checkMerkle);
							return this.ipfs_pubsub_publish(this.channelName, rlpx);
						   });
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
					this.register().then((tx) => 
					{ 	
						console.dir(tx); 
						this.client.subscribe('ethstats');
						this.client.on('ethstats', this.trial);
					})
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
			let rlpx = Buffer.from(msgObj.data);
			let data = {};

			// access levelDB searching for nonce of address 
			const __checkNonce = (address) => (resolve, reject) => 
			{
				let localMax = 0;
	
				db.createReadStream({gte: address})
				    .on('data', function (data) {
				       //if (data.value.nonce >= 2) { console.dir(data.value); }
				       if(data.key.substr(0, 42) === address) {
						let _nonce = Number(data.key.substr(43));
						if(_nonce > localMax) localMax = _nonce;
				       }
	   			    })
	   			    .on('error', (err) => {
	       				console.trace(err);
					reject(localMax);
	   			    })
				    .on('close', () => {
	   				console.log('Stream closed')
					resolve(localMax);
	 			    })
	 			    .on('end', () => {
	   				console.log('Stream ended')
					resolve(localMax);
	 			    })
			}

			try {
				ethUtils.defineProperties(data, fields, rlpx); // decode
			} catch(err) {
				console.trace(err);
				return; // TODO: may add source filter to prevent spam
			}

			if ( !(v in data) || !(r in data) || !(s in data) ) return;

			let sigout = {v: ethUtils.bufferToInt(data.v), r: data.r, s: data.s};

			// signature is signed against packed data fields
			let rawout = this.abi.encodePacked(
				[
                                 		'uint',
                                 		'address',
                                 		'address',
                                 		'uint',
                                 		'bytes32'
				],
				[
					ethUtils.bufferToInt(data.nonce),
					ethUtils.bufferToHex(data.validatorAddress),
					ethUtils.bufferToHex(data.originAddress),
					ethUtils.bufferToInt(data.timestamp),
					ethUtils.bufferToHex(data.payload)
				]
			);

			let chkhash = ethUtils.hashPersonalMessage(Buffer.from(rawout)); // Buffer
			sigout = { ...sigout, chkhash, netID: this.configs.networkID };
			
			// verify signature before checking nonce of the signed address
			if (pubkeyToAddress(sigout)) {
				let stage = new Promise(__checkNonce(ethUtils.bufferToHex(data.originAddress)));

				stage.catch((n) => { return n });
				stage = stage.then((nonce) => {
					return this.call(this.ctrName)('getPlayerInfo')(address).then((results) => {
						let maxNonce = Number(results[2]); // max possbile nonce by root-chain purchase records

						if (nonce <= maxNonce) {
							this.leaves.push(data.payload);
							// store file on local pool for IPFS publish
						} else {
							console.log(`DEBUG: player ${address} reached max tx allowance nonce: ${nonce}, max: ${maxNonce}.`)
							return; // discard
						}
			    		})
			    	})
				.catch((err) => { console.trace(err); return; });
			}
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

                this.submitChannel = (hashedScore) =>
                {
                        let params = 
                        {
                                nonce: 0,
                                validatorAddress: this.validator,
                                originAddress: this.address,
                                timestamp: Math.floor(Date.now() / 1000),
                                payload: hashedScore  // or ticketNumber (or hash(ticketNumber))
                        };
                        let data = biapi.abi.encodeParameters(
                            ['uint', 'address', 'address', 'uint', 'bytes32' ],
                            [params.nonce, params.validatorAddress, params.originAddress, params.timestamp, params.payload]
                        );
                        let datahash = ethUtils.hashPersonalMessage(new Buffer(data));
	                let mesh11 = {};

			return this.client.call('unlockAndSign', [this.address, datahash]).then((signature) => {
                        	ethUtils.defineProperties(mesh11, fields, [...params, ...signature]);
                        	return mesh11.serialize();
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
