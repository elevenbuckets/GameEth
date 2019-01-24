module.exports = {
    compilers: {
        solc:{
            version: '0.5.2',
            docker: true
        },
    },
    networks: {
        development: {
            host: "localhost",
            port: 8545,
            gas: 6400000,
            network_id: "*" // Match any network id
        }
    }
};
