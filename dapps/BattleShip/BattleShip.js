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

		this.probe = () => 
		{
			this.call(this.ctrName)('board')().then((rc) => { this.board = rc; console.log(`The Board: ${rc}`); });
			this.call(this.ctrName)('setup')().then((rc) => { this.gameStarted = rc; console.log(`The game started = ${rc}`); });
			this.call(this.ctrName)('initHeight')().then((rc) => { 
				this.initHeight = rc; console.log(`Init Block Height = ${rc}`); 
				if (typeof(this.results[this.initHeight]) === 'undefined') this.results[this.initHeight] = [];
			});

			return Promise.resolve(this.gameStarted);
		}	
	
		this.trial = (stats) => 
		{
			if (!this.gameStarted) return [];
			if (stats.blockHeight < this.initHeight + 5) return [];

			let blockNo = stats.blockHeight;
			this.secretBank.map((s) => 
			{
				let secret = ethUtils.sha256(s);
				let [myboard, slots] = this.call(this.ctrName)('testOutcome')(secret, blockNo);
				let score = [ ...myboard ];

				for (i = 0; i <= 31; i ++) {
					if (!slots[i]) {
						score[2+i*2] = board.charAt(2+i*2);
						score[2+i*2+1] = board.charAt(2+i*2+1);
					}
				}

				this.results[this.initHeight].push({score: score.join(''), secret, blockNo, slots});
			})
		}

		this.stopTrial = () => 
		{
			this.client.unsubscribe('ethstats');
			this.client.off('ethstats');
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
					console.log('Game is not yet set ...');
				}
			})
		}
	}
}

module.exports = BattleShip;
