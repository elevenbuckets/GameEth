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
                this.gamePeriod = 11;  // defined in the smart contract

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
	
		this.trial = (stats) => 
		{
			if (!this.gameStarted) return;
			if (stats.blockHeight < this.initHeight + 5) return;
			if (typeof(this.setAtBlock) === 'undefined') this.setAtBlock = stats.blockHeight;
			if (stats.blockHeight > this.initHeight + 6 || (typeof(this.setAtBlock) !== 'undefined' && stats.blockHeight >= this.setAtBlock + 7) ) {
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

		}

		this.stopTrial = () => 
		{
			this.client.unsubscribe('ethstats');
			this.client.off('ethstats');
			console.log('Trial stopped !!!');
		}

		this.startTrial = (tryMore = 0) => 
		{
                        if (tryMore > 0) { 
				if (tryMore > 2000) tryMore = 2000;
				this.moreSecret(tryMore); 
			};

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

                this.moreSecret = (sizeOfSecrets) =>
                {
                        for (var i = 0; i<sizeOfSecrets; i++) { this.secretBank.push(String(Math.random())); }
                }
	}
}

module.exports = BattleShip;
