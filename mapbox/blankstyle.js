export default {
                version: 8,
                layers: [{
                    id: 'background_',
                    paint: {
                        'background-color': 'white'
                    },
                    type: 'background'
                }],
                name: 'very simple',
                sources: {
                    empty: {
                        type: 'geojson',
                        data: {
                            "type": "FeatureCollection",
                            "name": "cropped",
                            "crs": { "type": "name", "properties": { "name": "urn:ogc:def:crs:OGC:1.3:CRS84" } },
                            "features": []
                        }
                    }
                }
            }
