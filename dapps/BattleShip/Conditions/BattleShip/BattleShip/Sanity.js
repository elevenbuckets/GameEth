module.exports = 
{
	BattleShip_withdraw_sanity(addr, jobObj) 
	{
		let initHeight = this.CUE[jobObj.type][jobObj.contract].initHeight();
		let period = this.CUE[jobObj.type][jobObj.contract].period();

		if ( addr === this.CUE[jobObj.type][jobObj.contract].winner() 
		  && this.web3.eth.blockNumber > initHeight + period
		){
			return true;
		} else {
			return false;
		}
	},

	BattleShip_fortify_sanity(addr, jobObj)
	{
		if ( addr === this.CUE[jobObj.type][jobObj.contract].defender()
		  && jobObj.txObj.value >= this.CUE[jobObj.type][job.contract].fee()
		  && this.CUE[jobObj.type][job.contract].setup === false
		) {
			return true;
		} else {
			return false;
		}
	},

	BattleShip_challenge_sanity(addr, jobObj)
	{
		let initHeight = this.CUE[jobObj.type][jobObj.contract].initHeight();
		let since = this.CUE[jobObj.type][jobOBj.contract].myInfo()[0];

		if ( addr !== this.CUE[jobObj.type][jobObj.contract].defender()
		  && jobObj.txObj.value >= this.CUE[jobObj.type][job.contract].fee()
		  && this.CUE[jobObj.type][job.contract].setup === true
		  && since < initHeight
		) {
			return true;
		} else {
			return false;
		}
	},

	BattleShip_revealSecret_sanity(addr, jobObj)
	{
		let initHeight = this.CUE[jobObj.type][jobObj.contract].initHeight();
		let period = this.CUE[jobObj.type][jobObj.contract].period();
		let since = this.CUE[jobObj.type][jobOBj.contract].myInfo()[0];
		let blockNumber = this.web3.eth.blockNumber;

		// revealSecret(secret, score, slots, blockNo)
		let [ secret, score, slots, blockNo ] = jobObj.args.map((i) => { return jobObj[i] });

		if ( addr !== this.CUE[jobObj.type][jobObj.contract].defender()
		  && this.CUE[jobObj.type][job.contract].setup === true
		  && since > initHeight
		  && blockNumber <= initHeight + period
		  && blockNumber >= since + 5
		  && blockNumber - blockNo < period - 5
		  && blockNo <= blockNumber - 1
	 	  && blockNo < initHeight + period
		  && blockNo >= initHeight + 5  // Note that here we skip signature checking
		) {
			return true;
		} else {
			return false;
		}
	}
}
