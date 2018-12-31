'use strict';

const fs   = require('fs');
const path = require('path');
const ethUtils = require('ethereumjs-utils');

// 11BE BladeIron Client API
const BladeIronClient = require('bladeiron_api');

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
                this.gamePeriod = 125;  // defined in the smart contract

		this.probe = () => 
		{
			return this.call(this.ctrName)('setup')()
			    .then((rc) => 
			    { 
				this.gameStarted = rc; console.log(`The game started = ${rc}`);
				return this.call(this.ctrName)('board')()
			    })
			    .then((rc) => 
			    { 
			    	this.board = rc; console.log(`The Board: ${rc}`); 
				if (this.gameStarted) {
					return this.call(this.ctrName)('initHeight')().then((rc) => { 
						this.initHeight = Number(rc); console.log(`Init Block Height = ${rc}`); 
						if (typeof(this.results[this.initHeight]) === 'undefined') this.results[this.initHeight] = [];
					})
					.then(() => { return this.gameStarted; });
				} else {
					return this.gameStarted;
				}
			    });
		}	

		this.testOutcome = (raw, blockNo) => 
		{
			let secret = ethUtils.bufferToHex(ethUtils.sha256(raw));
			return this.call(this.ctrName)('testOutcome')(secret, blockNo).then((r) => { return [...r, secret]});
		} 

		this.testSimple = (stats) => 
		{
			let raw = '11BE test';
			let blockNo = stats.blockHeight;
			return this.testOutcome(raw, blockNo);
		}

		this.register = (secret) => 
		{
			let msgSHA256Buffer = Buffer.from(secret.slice(2), 'hex');
			let gameANS = {};
			return this.client.call('unlockAndSign', [this.address, msgSHA256Buffer])
				.then((data) => {
					let fee = '10000000000000000';
					let v = data.v;
					let r = ethUtils.bufferToHex(Buffer.from(data.r));
					let s = ethUtils.bufferToHex(Buffer.from(data.s));
					gameANS = {secret, v,r,s};
					return this.sendTk(this.ctrName)('challenge')(v,r,s)(fee);
				})
				.then((qid) => {
					console.log(`DEBUG: QID = ${qid}`);
					return this.getReceipts(qid).then((rc) => {
						let rx = rc[0];

						if (rx.status === '0x1') {
							gameANS['submitted'] = rx.blockNumber;
							this.gameANS[this.initHeight] = gameANS; console.dir(this.gameANS);
						}
						return rx;
					});
				})
				.catch((err) => { console.log(err); throw err; })
		}

		this.winnerTakes = () => 
		{
			let winner = this.call(this.ctrName)('winner')();

			if (winner === this.address) {
				return this.sendTk(this.ctrName)('withdraw')()
			} else {
				console.log(`Yeah Right...`);
				return;
			}
		}

		this.submitAnswer = (stats) => 
		{
			if (this.gameANS[this.initHeight].secret !== this.bestANS.secret) {
				console.log("secret altered after registration... Abort!");
				return this.stopTrial();
			} else if (stats.blockHeight < Number(this.gameANS[this.initHeight].submitted) + 5) {
				console.log(`Still waiting block number >= ${Number(this.gameANS[this.initHeight].submitted) + 5} ...`);
				return;
			} else if (stats.blockHeight > this.initHeight + 125) {
				console.log(`Game round ${this.initHeight} is now ended`);
				this.gameStarted = false;
				return this.stopTrial();
			}

			return sendTk(this.ctrName)('revealSecret')(this.gameANS[this.initHeight].secret, this.bestANS.score, this.bestANS.slots, this.bestANS.blockNo)()
				.then((qid) => {
					return this.getReceipts(qid).then((rc) => {
						console.dir(rc[0]);
						this.gameStarted = false;
						this.stopTrial();
					})
				})
		}
	
		this.trial = (stats) => 
		{
			if (!this.gameStarted) return [];
			if (stats.blockHeight < this.initHeight + 5) return [];
			if (typeof(this.setAtBlock) === 'undefined') this.setAtBlock = stats.blockHeight;
			if (stats.blockHeight >= this.initHeight + 120 || (typeof(this.setAtBlock) !== 'undefined' && stats.blockHeight >= this.setAtBlock + 3) ) {
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
					return this.register(this.bestANS.secret)
						   .then((rc) => {
							console.dir(rc); 
							this.client.subscribe('ethstats');
							this.client.on('ethstats', this.submitAnswer);
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
                        if (this.tryMore) { this.trySecret(this.tryMore, blockNo);}
		}

		this.stopTrial = () => 
		{
			this.client.unsubscribe('ethstats');
			this.client.off('ethstats');
			console.log('Trial stopped !!!');
		}


                this.tryMore = null;
		this.startTrial = () => 
		{
                        if (!isNaN(tryMore)) {
                                if (tryMore > 1000) { console.warn(`Warning: your dictionary contains ${tryMore} words, may cause problems in some machines.`);}
                                this.tryMore= tryMore;
                        }
			this.probe().then((started) => 
			{
				if(started) {
					this.client.subscribe('ethstats');
					this.client.on('ethstats', this.trial);
					console.log('Game started !!!');
				} else {
					console.log('Game has not yet been set ...');
				}
			})
		}

                this.blockInsideGame = (blockNo) =>
                {
                        if (blockNo < this.initHeight || blockNo > this.initHeight + this.gamePeriod) {
                                return false;
                        } else if (typeof(blockNo) === 'undefined') {
                                return false;
                        } else {
                                return true;
                        }
                };

                this.trySecret = (sizeOfSecrets, blockNo = this.initHeight + 5) =>
                {
                        if (!this.blockInsideGame(blockNo)) return ['not in game'];  // uncomment this line for test
			if (blockNo < this.initHeight + 5) return [`wait until block ${this.initHeight+5}`];
                        // if (typeof sizeOfSecrets !== 'number') {console.log('Pls input number'); return null}
                        let secrets = [];
                        for (var i = 0; i<sizeOfSecrets; i++) { secrets.push(String(Math.random()));}
                        this.findBestSecret(secrets, blockNo);
                        // this.currentBestANS();
                };

                this.findBestSecret = (secrets, blockNo) =>
                {
                        let localANS = [];
                        let best;
			secrets.map((s,idx) =>
			{
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
                                        if (idx === secrets.length - 1) {
                                                if (this.bestANS !== null ) { localANS.push(this.bestANS);}
                                                best = localANS.reduce((a,c) =>
                                                {
                                                        if(this.byte32ToBigNumber(c.score).lte(this.byte32ToBigNumber(a.score))) {
                                                                // console.dir(c);
                                                                return c;
                                                        } else {
                                                                return a;
                                                        }
                                                });
                                                this.blockBest[blockNo] = best;
                                        }
                                });
                        });
		};

                this.currentBestANS = () =>
                {
                        if (Object.values(this.blockBest).length > 0) {
                                this.bestANS = Object.values(this.blockBest).reduce((a,c) =>
                                {
                                        if(this.byte32ToBigNumber(c.score).lte(this.byte32ToBigNumber(a.score))) {
                                                return c;
                                        } else {
                                                return a;
                                        }
                                });
                                console.log('Best Answer:'); console.dir(this.bestANS);
                        } else {
                                return;
                        }
                };

	}
}

module.exports = BattleShip;
