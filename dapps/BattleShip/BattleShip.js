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
                        		this.channelName = ethUtils.bufferToHex(ethUtils.sha256(this.board)); // state channel, for player to send
                        		this.channelACK  = [ ...this.channelName ].reverse().join(''); // validator ACK channel, for player to listen
					
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
			this.call(this.ctrName)('getBlockInfo')(this.initHeight)
			    .then((plist) => {
				let mr = plist[0]; // block merkle root
				let bd = plist[1]; // IPFS hash of block

				if (mr !== '0x0' && bd !== '' && this.results[this.initHeight].length > 0) 
				{
					this.stopTrial();
					// double check all submitted winning tickets are included
					this.verifyClaimHash().then((myClaimHash) => {
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
									this.myClaims.isLeft,
									this.myClaims.score,
									myClaimHash
								];
								console.log(`DEBUG: claimLotteReward call args:`); console.dir(args);
	
								return this.sendTk(this.ctrName)('claimLotteReward')(...args)()
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
											console.log(`BlockData (IPFS): ${bd}`);
											console.log(`ClaimHash: ${myClaimHash}`);
										}
									   })
									   .catch((err) => { console.trace(err); return; });
							} else {
								console.log('Merkle Proof Process FAILED!!!!!!'); 
								console.dir(this.results);
								console.dir(this.myClaims);
								console.log(`MerkleRoot: ${mr}`);
								console.log(`BlockData (IPFS): ${bd}`);
								console.log(`ClaimHash: ${myClaimHash}`);
								// TODO: What now?
							}
						})
					})
				}
			})
			.catch((err) => { console.log('ERROR in checkMerkle'); console.trace(err); });
		}

		this.calcTickets = (stats) => 
		{
			if ( stats.blockHeight <= this.initHeight + 8 ) {
				return Promise.resolve(false);
			} else if ( 
			        stats.blockHeight >= this.initHeight + this.gamePeriod
			) {
				this.stopTrial();
				this.ipfs_pubsub_unsubscribe(this.channelACK);
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

					// player will listen to validator ACK channel
					this.ipfs_pubsub_subscribe(this.channelACK)((msgObj) => 
					{

						let msgs = Buffer.from(msgObj.msg.data).toString().split('_');
						//{ submitBlock: msgs[0], fromPlayer: msgs[1], ticket: msgs[2] };
						if (msgs[1] !== this.userWallet) return;

						this.results[this.initHeight].map((robj, idx) => {
							if ( Number(robj.submitBlock) === Number(msgs[0])
							  && robj.ticket === msgs[2] 
							){
								this.results[this.initHeight][idx]['sent'] = true;
								console.log(`-- Signed message submitted: Block = ${robj.submitBlock}, Ticket: ${robj.ticket}`);
							}
						})
					});			
	
					return true;
				})
			}
		}

		this.newDraws = (stats) => 
		{
			this.calcTickets(stats).then((rc) => {
				if (!rc) return false;
				this.call(this.ctrName)('winningNumber')(stats.blockHeight - 1, this.board).then((raffle) => {
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

								let m = {};
								let params = {
									nonce,
									originAddress: this.userWallet, 
									submitBlock: stats.blockHeight - 1,
									ticket,
									payload: tickethash
								};

                        					ethUtils.defineProperties(m, fields, {...params, v,r,s});
			
								this.results[this.initHeight].push({
									nonce,
									secret: this.bestANS.secret,
									slots: this.bestANS.slots.map((s) => { return s ? 1 : 0 }).join(''),
									blockNo: this.bestANS.blockNo,
									submitBlock: stats.blockHeight - 1,
									ticket,
									v,r,s,
									sent: false
								});

								this.results[this.initHeight][nonce - 1]['rlp'] = m;
							})
							.catch((err) => { console.trace(err); });
						}
					})

					this.sendClaims(this.initHeight, this.channelName);
				})
			})
		}

		this.sendClaims = (initHeight, channel) => 
		{
			this.results[initHeight].map((robj, idx) => {
				if (!robj.sent) {
					return this.ipfs_pubsub_publish(channel, robj.rlp.serialize()).then((rc) => { 
						console.log(`- Signed message broadcasted: Block = ${robj.submitBlock}, Ticket: ${robj.ticket}`);
					})
					.catch((err) => { console.log(`Error in sendClaims`); console.trace(err); return false});
				}
			})
		}

		/*
		this.sendClaim = (rlpx, channel) =>
		{
			return this.ipfs_pubsub_publish(channel, rlpx).then((rc) => { 
				if (!rc) {
					console.log(`Statge channel communication failed ... retrying ...`);
					return setTimeout(this.sendClaim, 1100, rlpx, channel);
				} else {
					console.log(`Signed message broadcasted!!!`);
					return rc;
				}
			});
		}
		*/

		this.verify = (stats) => 
		{
			if (!this.gameStarted) return;
			if (stats.blockHeight < this.initHeight + 8) return;
			if (stats.blockHeight > this.initHeight + this.gamePeriod) {
				this.stopTrial();
				//this.ipfs_pubsub_publish(this.channelName, Buffer.from(rc.hash));
				// Instead of broadcasting IPFS hash on pubsub, we simply write it into smart contract! 
				this.unsubscribeChannel();
				this.makeMerkleTreeAndUploadRoot();
			}
		}	

		this.trial = (stats) => 
		{
			//console.log("\n"); console.dir(stats);
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

					//console.log(`Best Answer:`); console.dir(this.bestANS);
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

			//console.log('New Stats'); console.dir(stats);

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
					this.client.subscribe('ethstats');
					if (this.userWallet === this.validator) {
						console.log('Welcome, Validator!!!');
						this.subscribeChannel('validator');
						this.client.on('ethstats', this.verify);
					} else {
						console.log('Game started !!!');
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
				if ( typeof(this.winRecords[this.initHeight][address]) === 'undefined' ) {
				     this.winRecords[this.initHeight][address] = [];
				} else if ( this.winRecords[this.initHeight][address].findIndex((x) => { return Buffer.compare(x.nonce, data.nonce) == 0 } ) !== -1) {
					console.log(`Duplicate nonce (${address}): received nonce ${ethUtils.bufferToInt(data.nonce)} more than once`);
					return;
				} else if ( this.winRecords[this.initHeight][address].findIndex((x) => { return Buffer.compare(x.payload, data.payload) == 0 } ) !== -1) {
					console.log(`Duplicate payload (${address}): ${ethUtils.bufferToHex(data.payload)}`)
					return;
				} else if ( this.winRecords[this.initHeight][address].length === 10) {
					console.log(`Max nonce reached (${address}): exceeds round limit of 10... ignored`);
					return;
				}
			} catch(err) {
				console.trace(err);
				return;
			}

			return this.call(this.ctrName)('getPlayerInfo')(address).then((results) => 
			{
				let since = Number(results[0]);
				let scoreHash = results[1];

				if (scoreHash === '0x' || since !== this.initHeight) {
					console.log(`DEBUG: Address ${address} did not participate in this round`)
					return; // discard
				}
	
				if ( !('v' in data) || !('r' in data) || !('s' in data) ) return;

				this.call(this.ctrName)('winningNumber')(ethUtils.bufferToInt(data.submitBlock), this.board).then((raffle) => {
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
						console.log(`---> Received winning claim from ${address}, Ticket: ${ethUtils.bufferToHex(data.ticket)}`);
						this.winRecords[this.initHeight][address].push(data);
						this.ipfs_pubsub_publish(
							this.channelACK, 
							Buffer.from(ethUtils.bufferToInt(data.submitBlock) + '_' + address + '_' + ethUtils.bufferToHex(data.ticket))
						);
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
			let pkgArray = [ this.userWallet ];

			this.myClaims = 
			{ 
				  secret: this.bestANS.secret, 
			   	   slots: this.bestANS.slots.map((s) => { return s ? 1 : 0 }).join(''),
			         blockNo: this.bestANS.blockNo,
			    submitBlocks: [],
			  winningTickets: []
			}

			const compare = (a,b) => { if (a.nonce > b.nonce) { return 1 } else { return -1 }; return 0 };

			return this.call(this.ctrName)('getNumOfTickets')(this.bestANS.score).then((tlen) => {
			     return this.call(this.ctrName)('generateTickets')(this.bestANS.score, tlen).then((tlist) => 
				{
					this.results[this.initHeight].sort(compare).slice(0, 10).map((txObj) => {
						let __submitBlock = txObj.submitBlock;
						let __ticket      = txObj.ticket;
						pkgArray.push(__submitBlock); fmtArray.push('uint');
						pkgArray.push(__ticket); fmtArray.push('bytes32');
						this.myClaims.submitBlocks.push(__submitBlock);
						this.myClaims.winningTickets.push(tlist.indexOf(__ticket));
					});
	
					console.log('DEBUG: Claim Data Structure (fmtArray, pkgArray):');
					console.dir(fmtArray); console.dir(pkgArray);
	
					let claimset = this.abi.encodeParameters(fmtArray, pkgArray);
					let claimhash = ethUtils.bufferToHex(ethUtils.keccak256(claimset));
	
					console.log(`ClaimHash (address: ${this.userWallet}): ${claimhash}`);
	
					return claimhash;
			        })
				.catch((err) => { console.log(`ERROR in verifyClaimHash`); console.trace(err); });
			})
			.catch((err) => { console.log(`ERROR in verifyClaimHash`); console.trace(err); });
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

			console.log('DEBUG: Claim Data Structure (fmtArray, pkgArray):');
			console.dir(fmtArray); console.dir(pkgArray);

			let claimset = this.abi.encodeParameters(fmtArray, pkgArray);
			let claimhash = ethUtils.bufferToHex(ethUtils.keccak256(claimset));

			console.log(`ClaimHash (address: ${address}): ${claimhash}`);

			return claimhash;
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
                        let merkleRoot = ethUtils.bufferToHex(merkleTree.getMerkleRoot());
			console.log(`Block Merkle Root: ${merkleRoot}`);

			let stage = this.generateBlock(blkObj);
			stage = stage.then((rc) => {
				console.log('IPFS Put Results'); console.dir(rc);
	                	return this.sendTk(this.ctrName)('submitMerkleRoot')(blkObj.initHeight, merkleRoot, rc[0].hash)();
			})
			.catch((err) => { console.log(`ERROR in makeMerkleTreeAndUploadRoot`); console.trace(err); });
			
			return stage;
                }

		// for current round by validator only
		this.generateBlock = (blkObj) => 
		{
			const __genBlockBlob = (blkObj) => (resolve, reject) => 
			{
				fs.writeFile(path.join(this.configs.database, String(blkObj.initHeight), 'blockBlob'), JSON.stringify(blkObj), (err) => {
					if (err) return reject(err);
					resolve(path.join(this.configs.database, String(blkObj.initHeight), 'blockBlob'));
				})
			}

			let stage = new Promise(__genBlockBlob(blkObj));
			stage = stage.then((blockBlobPath) => 
			{
				console.log(`Local block data cache: ${blockBlobPath}`); 
				return this.ipfsPut(blockBlobPath);
			})
			.catch((err) => { console.log(`ERROR in generateBlock`); console.trace(err); });

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

				let leaves = [];
				Object.values(blockJSON.data).map((obj) => { return leaves = [ ...leaves, ...Object.keys(obj) ]; });

				return leaves;
			})
		}

                this.validateMerkleProof = (targetLeaf, ipfsHash) => 
		{
			return this.loadPreviousLeaves(ipfsHash).then((leaves) => {
	                	let merkleTree = new MerkleTree();
	                        merkleTree.addLeaves(leaves); 
	                        merkleTree.makeTree();

				let __leafBuffer = Buffer.from(targetLeaf.slice(2), 'hex');
                                let txIdx = merkleTree.tree.leaves.findIndex( (x) => { return Buffer.compare(x, __leafBuffer) == 0 } );
                                if (txIdx == -1) {
					console.log('Cannot find leave in tree!');
					return false;
				} else {
					console.log(`Found leave in tree! Index: ${txIdx}`);
				}
	
	                        let proofArr = merkleTree.getProof(txIdx, true);
	                        let proof = proofArr[1].map((x) => {return ethUtils.bufferToHex(x);});
	                        let isLeft = proofArr[0];
	
	                        //targetLeaf = ethUtils.bufferToHex(merkleTree.getLeaf(txIdx));
	                        let merkleRoot = ethUtils.bufferToHex(merkleTree.getMerkleRoot());
	
	                        return this.call(this.ctrName)('merkleTreeValidator')(proof, isLeft, targetLeaf, merkleRoot).then((rc) => {
					if (rc) {
						this.myClaims = { ...this.myClaims, proof, isLeft, score: this.gameANS[this.initHeight].score };
					} else {
						console.log('Warning! On-chain merkle validation will FAIL!!!');
					}
					return rc;
				})
			})
			.catch((err) => { console.log(`ERROR in validateMerkleProof`); console.trace(err); return false; })
                }
	}
}

module.exports = BattleShip;
