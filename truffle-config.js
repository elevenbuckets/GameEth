module.exports = {
    compilers: {
        solc:{
            version: '0.5.2',
            docker: true
        },
    },
    networks: {
        development: {
            host: "172.17.0.2",
            port: 8545,
            gas: 6400000,
            network_id: "*" // Match any network id
        }
    }
};
