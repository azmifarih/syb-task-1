module.exports = {
    publicPath: '/progressive-weather-app/',
    pwa: {
        themeColor: '#6CB9C8',
        msTileColor: '#484F60'
    },
    css: {
	extract: false,
    },
    configureWebpack: {
        optimization: {
            splitChunks: false
        }
    }
}
