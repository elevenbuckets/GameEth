module.exports = 
{
	BattleShip_withdraw_sanity(addr, jobObj) 
	{
		return true;
	},

	BattleShip_fortify_sanity(addr, jobObj)
	{
		if ( addr === this.CUE[jobObj.type][jobObj.contract].defender()
		  && jobObj.txObj.value >= this.CUE[jobObj.type][jobObj.contract].fee()
		  && this.CUE[jobObj.type][jobObj.contract].setup() === false
		) {
			return true;
		} else {
			return false;
		}
	},

	BattleShip_challenge_sanity(addr, jobObj)
	{
		return true;
	},

	BattleShip_claimLotteReward_sanity(addr, jobObj)
	{
		return true;
	},

	BattleShip_submitMerkleRoot_sanity(addr, jobObj)
	{
		return true;
	}
}
