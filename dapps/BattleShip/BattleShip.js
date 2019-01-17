'use strict';

const fs   = require('fs');
const path = require('path');
const ethUtils = require('ethereumjs-utils');
const biapi = require('bladeiron_api');
const MerkleTree = require('merkle_tree');
const mkdirp = require('mkdirp');

// 11BE BladeIron Client API
const BladeIronClient = require('bladeiron_api');

const fields = 
[
   {name: 'nonce', length: 32, allowLess: true, default: new Buffer([]) },
//   {name: 'validatorAddress', length: 20, allowZero: false, default: new Buffer([]) },
   {name: 'originAddress', length: 20, allowZero: true, default: new Buffer([]) },
   {name: 'submitBlock', length: 32, allowLess: true, default: new Buffer([]) },
   {name: 'ticket', length: 32, allowLess: true, default: new Buffer([]) },
   {name: 'payload', length: 32, allowLess: true, default: new Buffer([]) },
   {name: 'v', allowZero: true, default: new Buffer([0x1c]) },
   {name: 'r', allowZero: true, length: 32, default: new Buffer([]) },
   {name: 's', allowZero: true, length: 32, default: new Buffer([]) }
];

const verifySignature = (sigObj) =>
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

const mkdir_promise = (dirpath) =>
{
	const __mkdirp = (dirpath) => (resolve, reject) => 
	{ 
		mkdirp(dirpath, (err) => {
			if (err) return reject(err);
			resolve(true);
		})
	}

	return new Promise(__mkdirp(dirpath));
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
		this.winRecords = {}; // validator only

		this.probe = () => 
		{
			let p = ['setup', 'board', 'initHeight', 'period_all', 'validator'].map((i) => { return this.call(this.ctrName)(i)() });

			return Promise.all(p).then((plist) => {
				console.dir(plist);
				this.gameStarted = plist[0];

				if (this.gameStarted) {
					this.board = plist[1];
					this.initHeight = Number(plist[2]);
					this.gamePeriod = Number(plist[3]);
					this.validator = plist[4];
                        		this.channelName = ethUtils.bufferToHex(ethUtils.sha256(this.board));
					
					// Reset
					this.setAtBlock = undefined;
					this.myClaims = {};
					this.blockBest = {};
					this.bestANS = null;

					if (typeof(this.results[this.initHeight]) === 'undefined') this.results[this.initHeight] = [];
					if (typeof(this.winRecords[this.initHeight]) === 'undefined') { this.winRecords[this.initHeight] = {}; }
					if (typeof(this.gameANS[this.initHeight]) === 'undefined') { this.gameANS[this.initHeight] = {}; }

					return mkdir_promise(path.join(this.configs.database, String(this.initHeight))).then((r) => { 
						return this.gameStarted;
					})
				}

				return this.gameStarted;
			})
			.catch((err) => { console.trace(err); })
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
				if (rc.blockHeight <= this.initHeight + 10) {
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
			let p = ['merkleRoot', 'ipfsAddr'].map((c) => { return this.call(this.ctrName)(c)() });
			Promise.all(p).then((plist) => {
				let mr = plist[0]; // block merkle root
				let bd = plist[1]; // IPFS hash of block

				if (mr !== '0x0' && bd != '' && this.results[this.initHeight].length > 0) 
				{
					this.stopTrial();
					// double check all submitted winning tickets are included
					let myClaimHash = this.verifyClaimHash();
					// preparing data structure to call withdraw, if any
					this.validateMerkleProof(myClaimHash, bd).then((rc) => 
					{
						// By now, this.myClaims should be ready to use
						if (rc) {
							let args = 
							[
								this.myClaims.secret,
								this.myClaims.slots,
								this.myClaims.blockNo,
								this.myClaims.submitBlocks,
								this.myClaims.winningTickets,
								this.myClaims.proof,
								this.myClaims.isLeft
							];

							return this.sendTk(this.ctrName)('claimLotteReward')(...args)
								   .then((qid) => { return this.getReceipts(qid); })
								   .then((rx) => { 
								   	let tx = rx[0];
									console.dir(tx);
									if (tx.status !== '0x1') {
										throw "Claim Lottery Error!";
									} else {
										console.log(`***** Congretulation!!! YOU WON!!! *****`);
										console.dir(this.results);
										console.dir(this.myClaims);
										console.log(`MerkleRoot: ${mr}`);
										console.log(`ClaimHash: ${myClaimHash}`);
									}
								   })
								   .catch((err) => { console.trace(err); return; });
						} else {
							console.log(`Merkle Proof Process FAILED!!!!!!`);
						}
					})
				}
			})
		}

		this.calcTickets = (stats) => 
		{
			if ( stats.blockHeight <= this.initHeight + 8 ) {
				return Promise.resolve(false);
			} else if ( 
			        stats.blockHeight > this.initHeight + this.gamePeriod
			) {
				this.stopTrial();
			        if (this.results[this.initHeight].length > 0) {
					console.log(`Address ${this.userWallet} won ${this.results[this.initHeight].length} times! Awaiting Merkle root to withdraw prize...`);
					this.client.subscribe('ethstats');
					this.client.on('ethstats', this.checkMerkle);
				} else {
					console.log(`Thank you for playing ${this.ctrName}. Hope you will get some luck next time!!!`);
				}
				return Promise.resolve(false);
			} else if (
			 	stats.blockHeight > this.initHeight + 8 
			     && Object.keys(this.gameANS[this.initHeight].tickets).length != 0
			){
				return Promise.resolve(true);
			} else {
				return this.call(this.ctrName)('getBlockhash')(Number(this.initHeight) + 8).then( (blockhash) => {
					// check how many tickets earned
					let initials = this.toBigNumber(this.gameANS[this.initHeight].score.substr(0,7));
					let total = 1;
		
					if (initials.eq(0)) {
						total = 5;
					} else if (initials.lt(16)) {
						total = 4;
					} else if (initials.lt(256)) {
						total = 3;
					} else if (initials.lt(4096)) {
						total = 2;
					}
		
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
						console.log(`Ticket ${i}: ${this.gameANS[this.initHeight].tickets[i]}`);
					}
					
					return true;
				})
			}
		}

		this.newDraws = (stats) => 
		{
			this.calcTickets(stats).then((rc) => {
				if (!rc) return false;
				this.call(this.ctrName)('winningNumber')(stats.blockHeight - 1).then((raffle) => {
					Object.values(this.gameANS[this.initHeight].tickets).map((ticket) => {
						if (raffle.substr(65) === ticket.substr(65)) { // compare to determine if winning
							console.log(`One winning ticket found!`);
							let data = this.abi.encodeParameters(
							[
								'bytes32',
								'string',
								'uint',
								'uint',
								'bytes32'
							],
							[
								this.bestANS.secret,
								this.bestANS.slots.map((s) => { return s ? 1 : 0 }).join(''),
								this.bestANS.blockNo,
								stats.blockHeight - 1,
								ticket
							])

							// FIXME: BladeIron unlockAndSign low-level API expect message buffer and will
							// add the Ethereum message signature header for you!!! should we change this behavior?
							let tickethash = ethUtils.hashPersonalMessage(Buffer.from(data));
							this.client.call('unlockAndSign', [this.userWallet, Buffer.from(data)]).then((sig) => 
							{
								let nonce = this.results[this.initHeight].length + 1;
								let v = Number(sig.v);
								let r = Buffer.from(sig.r);
								let s = Buffer.from(sig.s);

								this.results[this.initHeight].push({
									nonce,
									secret: this.bestANS.secret,
									slots: this.bestANS.slots.map((s) => { return s ? 1 : 0 }).join(''),
									blockNo: this.bestANS.blockNo,
									submitBlock: stats.blockHeight - 1,
									ticket,
									v,r,s
								});

								let m = {};
								let params = {
									nonce,
									originAddress: this.userWallet, 
									submitBlock: stats.blockHeight - 1,
									ticket,
									payload: tickethash
								};

                        					ethUtils.defineProperties(m, fields, {...params, v,r,s});
			
								// verify signature from decoding serialized data for debug purposes
								this.results[this.initHeight][nonce - 1]['rlp'] = m;

								let sigout = {
									chkhash: m.payload, 
									v: ethUtils.bufferToInt(m.v), r: m.r, s: m.s, 
									originAddress: m.originAddress, 
									netID: this.configs.networkID
								};

								if(verifySignature(sigout)) {
									return this.ipfs_pubsub_publish(this.channelName, m.serialize());
								} else {
									console.log('Signature self-test failed!');
									console.log('Locally generate (rlp): '); console.dir(m);
									this.stopTrial();
								}
							})
							.catch((err) => { console.trace(err); });
						}
					})
				})
			})
		}

		this.verify = (stats) => 
		{
			if (!this.gameStarted) return;
			if (stats.blockHeight < this.initHeight + 8) return;
			if (stats.blockHeight >= this.initHeight + this.gamePeriod) {
				this.stopTrial();
				//this.ipfs_pubsub_publish(this.channelName, Buffer.from(rc.hash));
				// Instead of broadcasting IPFS hash on pubsub, we simply write it into smart contract! 
				this.unsubscribeChannel();
				this.makeMerkleTreeAndUploadRoot();
			}
		}	

		this.trial = (stats) => 
		{
			console.log("\n"); console.dir(stats);
			if (!this.gameStarted) return;
			if (stats.blockHeight <= this.initHeight + 7) return;
			if ( stats.blockHeight >= this.initHeight + 10 
			  || ( stats.blockHeight > this.initHeight + 7 && typeof(this.setAtBlock) !== 'undefined' && stats.blockHeight >= this.setAtBlock + 1) 
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
					console.log(`Too late or not managed to calculate score to participate this round...`);
					return;
				}
			}
			if (typeof(this.setAtBlock) === 'undefined') {
				this.setAtBlock = Number(stats.blockHeight);
				console.log(`Start calculating score at ${this.setAtBlock}`);
			}

			console.log('New Stats'); console.dir(stats);

			let blockNo = stats.blockHeight - 1; console.log(`BlockNo: ${blockNo}`);
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
				.catch((err) => { console.log(`Test Outcome`);  console.trace(err); })
			})
		}

		this.stopTrial = () => 
		{
			this.client.unsubscribe('ethstats');
			this.client.off('ethstats');
			console.log('Trial stopped !!!');
		}

		this.startTrial = (tryMore = 1183) => 
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
					if (this.userWallet === this.validator) {
						console.log('Welcome, Validator!!!');
						this.subscribeChannel('validator');
						this.client.on('ethstats', this.verify);
					} else {
						this.client.on('ethstats', this.trial);
					}
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
			let rlpx = Buffer.from(msgObj.msg.data);

			try {
				ethUtils.defineProperties(data, fields, rlpx); // decode
				address = ethUtils.bufferToHex(data.originAddress);
				if (typeof(this.winRecords[this.initHeight][address]) === 'undefined') {
				     this.winRecords[this.initHeight][address] = [];
				} else if ( this.winRecords[this.initHeight][address].length > 10) {
					throw `address ${address} exceeds round limit ... ignored`;
				}
			} catch(err) {
				console.trace(err);
				return;
			}

			return this.call(this.ctrName)('getPlayerInfo')(address).then((results) => 
			{
				let since = results[0];
				let scoreHash = results[1];

				if (scoreHash === '0x0' || since < this.initHeight) {
					console.log(`DEBUG: Address ${address} did not participate in this round`)
					return; // discard
				}
	
				if ( !('v' in data) || !('r' in data) || !('s' in data) ) return; console.dir(data);

				this.call(this.ctrName)('winningNumber')(ethUtils.bufferToInt(data.submitBlock)).then((raffle) => {
					if (raffle.substr(65) !== ethUtils.bufferToHex(data.ticket).substr(65)) return;
	
					let sigout = {
						v: ethUtils.bufferToInt(data.v), 
						r: data.r, s: data.s,
						originAddress: data.originAddress,
						chkhash: data.payload,
						netID: this.configs.networkID
					};

					// verify signature before checking nonce of the signed address
					if (verifySignature(sigout)) {
						// store tx in mem pool for IPFS publish
						console.log(`---> Received winning claim from ${address} ...`); console.dir(data);
						this.winRecords[this.initHeight][address].push(data);
					}
				})
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
                }

                this.unsubscribeChannel = () =>
                {
                        this.ipfs_pubsub_unsubscribe(this.channelName).then((rc) => {
                                if (rc) this.channelName = '';
                        })
                }

		this.verifyClaimHash = () => 
		{
			let fmtArray = ['address'];
			let pkgArray = [ address ];

			this.myClaims = 
			{ 
				  secret: this.bestANS.secret, 
			   	   slots: this.bestANS.slots.map((s) => { return s ? 1 : 0 }).join(''),
			         blockNo: this.bestANS.blockNo,
			    submitBlocks: [],
			  winningTickets: []
			}

			const compare = (a,b) => { if (ethUtils.bufferToInt(a.nonce) > ethUtils.bufferToInt(b.nonce)) { return 1 } else { return -1 }; return 0 };

			this.call(this.ctrName)('generateTickets')(this.bestANS.score).then((tlist) => {
				this.results[this.initHeight].sort(compare).slice(0, 10).map((txObj) => {
					let __submitBlock = ethUtils.bufferToInt(txObj.submitBlock);
					let __ticket      = ethUtils.bufferToHex(txObj.ticket);
					pkgArray.push(__submitBlock); fmtArray.push('uint');
					pkgArray.push(__ticket); fmtArray.push('bytes32');
					this.myClaims.submitBlocks.push(__submitBlock);
					this.myClaims.winnerTickets.push(tlist.indexOf(__ticket));
				});
			})

			let claimset = this.abi.encodeParameters(fmtArray, pkgArray);

			return ethUtils.bufferToHex(ethUtils.keccak256(claimset));
		}

		this.calcClaimHash = (address) => 
		{
			let fmtArray = ['address'];
			let pkgArray = [ address ];

			const compare = (a,b) => { if (ethUtils.bufferToInt(a.nonce) > ethUtils.bufferToInt(b.nonce)) { return 1 } else { return -1 }; return 0 };

			this.winRecords[this.initHeight][address].sort(compare).slice(0, 10).map((txObj) => {
				pkgArray.push(ethUtils.bufferToInt(txObj.submitBlock)); fmtArray.push('uint');
				pkgArray.push(ethUtils.bufferToHex(txObj.ticket)); fmtArray.push('bytes32');
			});

			let claimset = this.abi.encodeParameters(fmtArray, pkgArray);

			return ethUtils.bufferToHex(ethUtils.keccak256(claimset));
		}

                // Perhaps user sign-in should be entirely off-chain, i.e., no playerDB in contract. 
                // 1. It's possible that user has registered on-chain (added to playerDB) 
                //    and somehow failed to submit here. Perhaps user data entirely off-chain?
                // 2. hard to make sure this annoucement and generation/submision of Merkle Tree
                //    is on time
                this.makeMerkleTreeAndUploadRoot = () => 
		{
			// Currently, we will group all block data into single JSON and publish it on IPFS
			let blkObj =  {initHeight: this.initHeight, data: {} };
                	let merkleTree = new MerkleTree();
			let leaves = [];

			Object.keys(this.winRecords[blkObj.initHeight]).map((addr) => {
				if (this.winRecords[blkObj.initHeight][addr].length === 0) return;
				let claimhash = this.calcClaimHash(addr);
				blkObj.data[addr] = {[claimhash]: this.winRecords[blkObj.initHeight][addr]};
				leaves.push(claimhash);
			})

                        merkleTree.addLeaves(leaves); 
                        merkleTree.makeTree();
                        merkleRoot = ethUtils.bufferToHex(merkleTree.getMerkleRoot());

			let stage = this.generateBlock(blkObj);
			stage = stage.then((rc) => {
	                	return this.call(this.ctrName)('submitMerkleRoot')(blkObj.initHeight, merkleRoot, rc.hash);
			});
			
			return stage;
                }

		// for current round by validator only
		this.generateBlock = (blkObj) => 
		{
			const __genBlockBlob = (blkObj) => (resolve, reject) => 
			{
				fs.writeFile(path.join(this.configs.database, blkObj.initHeight, 'blockBlob'), blkObj, (err) => {
					if (err) return reject(err);
					resolve(path.join(this.configs.database, String(blkObj.initHeight), 'blockBlob'));
				})
			}

			let stage = new Promise(__genBlockBlob(blkObj));
			stage = stage.then((blockBlobPath) => { return this.client.ipfsPut(blockBlobPath) } )
				     .catch((err) => { console.trace(err); });

			return stage;
		}

		this.loadPreviousLeaves = (ipfsHash) => 
		{
			// load block data from IPFS
			// get all tickethash from all rlpx contents
			// put them in leaves for merkleTree calculation
			return this.ipfsRead(ipfsHash).then((blockBuffer) => {
				let blockJSON = JSON.parse(blockBuffer.toString());

				if (Number(blockJSON.initHeight) !== this.initHeight) {
					console.log(`Oh No! Did not get IPFS data for ${this.initHeight}, got data for round ${blockJSON.initHeight} instead`);
					return [];
				}
				let leaves = Object.keys(blockJSON.data);
				return leaves;
			})
		}

                this.validateMerkleProof = (targetLeaf, ipfsHash) => 
		{
			return this.loadPreviousLeaves(ipfsHash).then((leaves) => {
	                	let merkleTree = new MerkleTree();
	                        merkleTree.addLeaves(leaves); 
	                        merkleTree.makeTree();
	
	                        if (merkleTree.isReady) {
	                                let txIdx = merkleTree.leaves.findIndex( (x) => { Buffer.compare(x, targetLeaf) == 0 } );
	                                if (txIdx == -1) return false;
	                        }
	
	                        let proofArr = merkleTree.getProof(txIdx, true);
	                        let proof = proofArr[1].map((x) => {return ethUtils.bufferToHex(x);});
	                        let isLeft = proofArr[0];
	
	                        targetLeaf = ethUtils.bufferToHex(merkleTree.getLeaf(txIdx));
	                        let merkleRoot = ethUtils.bufferToHex(merkleTree.getMerkleRoot());
	
	                        return this.call(this.ctrName)('merkleTreeValidator')(proof, isLeft, targetLeaf, merkleRoot).then((rc) => {
					if (rc) this.myClaims = { ...this.myClaims, proof, isLeft };
					return rc;
				})
			})
                }
	}
}

module.exports = BattleShip;
