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
	
		this.trial = (stats) => 
		{
			if (!this.gameStarted) return [];
			if (stats.blockHeight < this.initHeight + 5) return [];
			if (stats.blockHeight >= this.initHeight + 110) {
				this.stopTrial();
				if (Object(this.blockBest).length > 0) {
					this.bestANS = Object(this.blockBest).values.reduce((a,c) => 
					{
						if(this.byte32ToBigNumber(c.score).lte(this.byte32ToBigNumber(a.score))) {
							return c;
						} else {
							return a;
						}
					})

					console.log(`Best Answer:`); console.dir(this.bestANS);			
					return "Please submit your answer (bestANS) before the game ends!!!!!";
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

		this.startTrial = () => 
		{
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
	}
}

module.exports = BattleShip;
